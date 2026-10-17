import Foundation

@MainActor
final class MemoryTarget: LiveTextTarget {
    var field: LiveFieldSnapshot
    var focused = true
    var writes = 0
    var delay: UInt64 = 0
    init(_ value: String = "", _ selection: NSRange? = nil) {
        field = LiveFieldSnapshot(value: value, selection: selection ?? NSRange(location: value.utf16.count, length: 0))
    }
    func snapshot() -> LiveFieldSnapshot? { focused ? field : nil }
    func replace(_ range: NSRange, with text: String, expected: LiveFieldSnapshot) async -> LiveFieldSnapshot? {
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        guard !Task.isCancelled, snapshot() == expected else { return nil }
        field = AXLiveTextTarget.replacing(LiveFieldSnapshot(value: expected.value, selection: range), with: text)
        writes += 1
        return field
    }
}

@main
struct DictationRegressionTests {
    @MainActor static func main() async {
        var passed = 0
        func check(_ ok: Bool, _ message: String) {
            precondition(ok, message)
            passed += 1
            print("PASS \(message)")
        }
        let typer = LiveTyper()
        let target = MemoryTarget("USER  SUFFIX", NSRange(location: 5, length: 0))
        check(typer.begin(target: target), "start at captured caret")
        typer.render(target: "кот", frozen: 0)
        await typer.flush()
        typer.render(target: "код", frozen: 3)
        await typer.flush()
        check(target.field.value == "USER код SUFFIX", "final correction applied before freeze; surrounding text preserved")
        typer.render(target: "код работает", frozen: 3)
        await typer.flush()
        check(target.field.value == "USER код работает SUFFIX", "append after committed fragment")
        let retract = MemoryTarget()
        let retractTyper = LiveTyper()
        _ = retractTyper.begin(target: retract)
        retractTyper.render(target: "одно два", frozen: 0); await retractTyper.flush()
        retractTyper.render(target: "одно", frozen: 0); await retractTyper.flush()
        check(retract.field.value == "одно", "partial may retract its suffix without new text")
        target.field.selection = NSRange(location: 2, length: 0)
        let before = target.field
        typer.render(target: "код работал", frozen: 3)
        await typer.flush()
        check(target.field == before, "caret move prevents any replacement")

        let manual = MemoryTarget()
        _ = typer.begin(target: manual)
        typer.render(target: "hello", frozen: 0); await typer.flush()
        manual.field.value += " USER"
        manual.field.selection.location += 5
        let edited = manual.field
        typer.render(target: "help", frozen: 0); await typer.flush()
        check(manual.field == edited, "manual input is preserved")

        let switched = MemoryTarget()
        _ = typer.begin(target: switched)
        typer.render(target: "old field", frozen: 0); await typer.flush()
        switched.focused = false
        typer.render(target: "new revision", frozen: 0); await typer.flush()
        check(switched.field.value == "old field", "focus loss rejects writes")

        let long = MemoryTarget()
        _ = typer.begin(target: long)
        typer.render(target: String(repeating: "a", count: 1000), frozen: 0); await typer.flush()
        typer.render(target: "b", frozen: 1); await typer.flush()
        check(long.field.value == "b" && typer.screen == "b", "1000-character replacement remains synchronized")

        let delayed = MemoryTarget(); delayed.delay = 20_000_000
        _ = typer.begin(target: delayed)
        typer.render(target: "late", frozen: 0)
        await Task.yield()
        typer.cancel()
        try? await Task.sleep(nanoseconds: 30_000_000)
        check(delayed.writes == 0, "cancel prevents queued/in-flight writes")
        let fresh = MemoryTarget("new ")
        _ = typer.begin(target: fresh)
        typer.render(target: "session", frozen: 7); await typer.flush()
        check(fresh.field.value == "new session", "restart captures a new caret without old text")

        let selection = MemoryTarget("before SELECT after", NSRange(location: 7, length: 6))
        _ = typer.begin(target: selection)
        typer.render(target: "", frozen: 0); await typer.flush()
        check(selection.field.value == "before SELECT after", "empty recognition does not delete initial selection")
        typer.render(target: "замена", frozen: 6); await typer.flush()
        check(selection.field.value == "before замена after", "intentional initial selection replaced precisely")
        let emoji = "prefix 👨‍👩‍👧‍👦 👩🏽‍💻 cafe\u{301} suffix"
        check(AXLiveTextTarget.chunks(emoji).joined() == emoji, "Unicode chunks preserve complete graphemes")

        let rules = DeveloperDictionary.entries
        check(TranscriptCorrector.correct("создай некст джей эс", rules: rules) == "создай Next.js", "dictionary token contraction")

        for phrase in ["перенос строки", "с новой строки", "на новую строку", "перевод строки", "new line", "line break"] {
            check(VoiceCommands.applyInline(to: "привет \(phrase) мир") == "привет\nмир", "line command: \(phrase)")
        }
        for phrase in ["абзац", "новый абзац", "с нового абзаца", "new paragraph", "paragraph"] {
            check(VoiceCommands.applyInline(to: "привет \(phrase) мир") == "привет\n\nмир", "paragraph command: \(phrase)")
        }
        check(VoiceCommands.applyInline(to: "с новой строки мир", followsText: true) == "\nмир", "line command opens a span that continues committed text")
        check(VoiceCommands.applyInline(to: "абзац") == "абзац", "leading command with nothing before it stays text")

        // Segment finalization: each utterance is joined onto committed text once,
        // and a leading line-break command opens without a stray space.
        check(LiveJoin.join("привет", "мир") == "привет мир", "segments join with a space")
        check(LiveJoin.join("привет", "\nмир") == "привет\nмир", "a line command's leading newline is not doubled with a space")
        check(LiveJoin.join("", "мир") == "мир" && LiveJoin.join("привет", "") == "привет", "joining with an empty segment returns the other side unchanged")
        check(LiveJoin.join("Первое. ", "Второе") == "Первое. Второе", "a trailing sentence space is not doubled")
        check(LiveJoin.spaceAfterPunctuation("Первое.Второе,третье!Четвёртое") == "Первое. Второе, третье! Четвёртое", "missing spaces inside a phrase are restored")
        check(LiveJoin.spaceAfterPunctuation("Готово.", atEnd: true) == "Готово. ", "a finalized sentence keeps a trailing space")
        check(LiveJoin.spaceAfterPunctuation("Готово?", atEnd: true) == "Готово? " && LiveJoin.spaceAfterPunctuation("Готово,", atEnd: true) == "Готово, ", "other trailing punctuation also receives a space")
        check(LiveJoin.spaceAfterPunctuation("Готово. ", atEnd: true) == "Готово. ", "an existing sentence space is not doubled")
        check(LiveJoin.spaceAfterPunctuation(VoiceCommands.applyInline(to: "Привет точка"), atEnd: true) == "Привет. ", "spoken punctuation receives a trailing space")
        check(LiveJoin.spaceAfterPunctuation("3.14, 2,5 и Next.js на example.com") == "3.14, 2,5 и Next.js на example.com", "numbers and common domains keep their punctuation")
        check(WhisperTranscriptFilter.isFiller("Продолжение следует...") && WhisperTranscriptFilter.isFiller("  ПРОДОЛЖЕНИЕ СЛЕДУЕТ…  "), "Whisper's silence hallucination is discarded")
        check(!WhisperTranscriptFilter.isFiller("Продолжение следует, но мы ещё здесь") && !WhisperTranscriptFilter.isFiller("you"), "normal speech containing stock words is preserved")
        var sentencePause = WhisperLiveCommitter()
        check(sentencePause.finalize(LiveJoin.spaceAfterPunctuation("Первое.", atEnd: true)).delta == "Первое. ", "pause inserts a space after the first sentence")
        check(sentencePause.partial("Второе предложение") == "Второе ", "speech after a pause does not add another space")
        check(sentencePause.finalize(LiveJoin.spaceAfterPunctuation("Второе предложение.", atEnd: true)).delta == "предложение. " && sentencePause.committed == "Первое. Второе предложение. ", "Fn release leaves a space after the last punctuation mark")

        var live = WhisperLiveCommitter()
        check(live.partial("привет ми") == "привет ", "first Whisper hypothesis pastes a complete word")
        check(live.partial("привет мир сегодня") == "мир ", "next hypothesis appends without waiting for a duplicate")
        check(live.partial("привет мир сегодня хорошо") == "сегодня ", "later words append without replay")
        let firstFinal = live.finalize("привет мир сегодня хорошо")
        check(firstFinal.delta == "хорошо" && firstFinal.segment == "привет мир сегодня хорошо", "finalization pastes only the remaining word")
        check(live.partial("дальше текст") == " дальше ", "next segment starts with one separator and a complete word")
        let secondFinal = live.finalize("дальше текст")
        check(secondFinal.delta == "текст" && live.committed == "привет мир сегодня хорошо дальше текст", "next segment finalizes without replay")
        var revised = WhisperLiveCommitter()
        check(revised.partial("Hello wor") == "Hello ", "unstable last word is withheld")
        check(revised.partial("Hello world") == "", "unchanged complete prefix is not replayed")
        let revisedFinal = revised.finalize("Hallo world")
        check(revisedFinal.delta == "world" && revisedFinal.segment == "Hello world", "revision does not duplicate already pasted words")
        var emptyFinal = WhisperLiveCommitter()
        check(emptyFinal.partial("живое слово") == "живое ", "recognized prefix reaches the cursor")
        check(emptyFinal.finalize("").delta.isEmpty && emptyFinal.committed == "живое ", "empty final result preserves an already inserted prefix")
        check(emptyFinal.partial("новая фраза") == "новая ", "recognition resumes after an empty segment")

        let personal = DictEntry(spoken: "некст джей эс", written: "MyFramework")
        check(TranscriptCorrector.correct("некст джей эс", rules: [personal] + rules) == "MyFramework", "personal dictionary priority")
        check(DictionaryContext.contextualStrings(personal: [], developerEnabled: false, frequencyEnabled: false).isEmpty, "disabled dictionary/context returns no hints")
        check(DictionaryContext.contextualStrings(personal: [personal], developerEnabled: false, frequencyEnabled: false) == ["MyFramework"], "personal hints remain available independently")
        let correction = CorrectionObserver.extractCorrection(oldValue:"before Bubble Bar after", typed:"Bubble Bar", newValue:"before BabelBar after", ownedRange:NSRange(location:7,length:10))
        check(correction?.spoken == "Bubble Bar" && correction?.written == "BabelBar", "learn only correction inside owned range")
        check(CorrectionObserver.extractCorrection(oldValue:"before Bubble Bar after", typed:"Bubble Bar", newValue:"different BabelBar after", ownedRange:NSRange(location:7,length:10)) == nil, "edits outside owned range do not train dictionary")
        var settings = AppSettings()
        settings.openHotKey = KeyCombo(keyCode:37,option:true)
        settings.selectionHotKey = KeyCombo(keyCode:8,command:true)
        settings.setVoiceShortcut(ModifierCombo(fn:true,shift:true), for: .dictateTranslateToCursor)
        settings.setVoiceShortcut(ModifierCombo(fn:true,command:true), for: .dictateToCursor)
        settings.dictationMode = .afterPhrase
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        check(decoded.openHotKey == settings.openHotKey && decoded.selectionHotKey == settings.selectionHotKey && decoded.translateDictateHotkey == settings.translateDictateHotkey && decoded.dictateHotkey == settings.dictateHotkey && decoded.dictationMode == .afterPhrase, "selected mode and custom shortcuts survive settings round trip")
        settings.setVoiceShortcut(ModifierCombo(fn:true,shift:true), for: .dictateToCursor)
        check(settings.translateDictateHotkey.isEmpty && settings.dictateHotkey == ModifierCombo(fn:true,shift:true), "reassigning a voice shortcut moves it from the translation command")
        settings.setVoiceShortcut(ModifierCombo(), for: .dictateToCursor)
        check(settings.dictateHotkey.isEmpty, "primary dictation shortcut can be cleared")

        func legacySettings(batch: ModifierCombo, live: ModifierCombo, liveEnabled: Bool) -> AppSettings {
            var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
            json.removeValue(forKey: "dictationMode")
            json["dictateHotkey"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
            json["liveDictateHotkey"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(live))
            json["liveDictationEnabled"] = liveEnabled
            return try! JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let previousBatch = legacySettings(batch: ModifierCombo(fn: true), live: ModifierCombo(), liveEnabled: true)
        check(previousBatch.dictationMode == .afterPhrase && previousBatch.dictateHotkey == ModifierCombo(fn: true), "current Fn batch setup migrates without changing its behavior")
        let previousLive = legacySettings(batch: ModifierCombo(), live: ModifierCombo(fn: true), liveEnabled: true)
        check(previousLive.dictationMode == .live && previousLive.dictateHotkey == ModifierCombo(fn: true), "previous live shortcut migrates to the unified control")

        // Replay actual shortcut event sequences without installing an event tap
        // or opening the microphone. These exercise Fn/Shift+Fn arbitration and
        // release/cancellation while capture is starting asynchronously.
        let hotkeys = VoiceHotkeys.shared
        var starts: [VoiceAction] = [], stops: [VoiceAction] = []
        hotkeys.onStart = { starts.append($0) }
        hotkeys.onStop = { stops.append($0) }
        let fn = ModifierCombo(fn: true), shiftFn = ModifierCombo(fn: true, shift: true)
        hotkeys.bindings = { [(fn, .dictateToCursor), (shiftFn, .dictateTranslateToCursor)] }
        hotkeys.process(current: fn, at: 100)
        check(starts == [.dictateToCursor], "batch Fn starts immediately even with a Shift+Fn binding")
        hotkeys.process(current: shiftFn, at: 100.03)
        hotkeys.process(current: ModifierCombo(), at: 100.6)
        check(starts.count == 1 && stops == [.dictateTranslateToCursor], "Fn-first translation chord reuses capture and selects translation on stop")
        starts = []; stops = []
        hotkeys.process(current: fn, at: 101)
        hotkeys.process(current: ModifierCombo(), at: 101.5)
        check(starts == [.dictateToCursor] && stops == [.dictateToCursor], "a held Fn release stops exactly one immediate capture")
        starts = []; stops = []
        hotkeys.process(current: fn, at: 102)
        hotkeys.process(current: ModifierCombo(), at: 102.08)
        check(starts.count == 1 && stops.isEmpty, "a quick Fn tap keeps the pending capture in toggle mode")
        hotkeys.process(current: fn, at: 103)
        hotkeys.process(current: ModifierCombo(), at: 103.08)
        check(starts.count == 1 && stops == [.dictateToCursor], "second Fn tap ends toggle capture without another start")
        starts = []; stops = []
        hotkeys.bindings = { [(fn, .liveDictateToCursor), (shiftFn, .dictateTranslateToCursor)] }
        hotkeys.process(current: fn, at: 104)
        check(starts.isEmpty, "different live/batch capture paths wait for an ambiguous chord")
        hotkeys.process(current: shiftFn, at: 104.03)
        try? await Task.sleep(nanoseconds: 180_000_000)
        check(starts == [.dictateTranslateToCursor], "Shift+Fn never starts the wrong live recognizer")
        hotkeys.process(current: ModifierCombo(), at: 104.6)
        check(stops == [.dictateTranslateToCursor], "settled translation chord stops its batch capture")
        starts = []; stops = []
        hotkeys.process(current: fn, at: 105)
        hotkeys.cancelActiveSession()
        try? await Task.sleep(nanoseconds: 180_000_000)
        check(starts.isEmpty && stops.isEmpty, "canceling a pending chord prevents a late microphone start")
        hotkeys.bindings = { [(fn, .liveDictateToCursor)] }
        hotkeys.process(current: fn, at: 106)
        check(starts == [.liveDictateToCursor], "an unambiguous live Fn starts immediately")
        hotkeys.cancelActiveSession()
        hotkeys.onStart = nil; hotkeys.onStop = nil
        print("\(passed) regression checks passed")
    }
}
