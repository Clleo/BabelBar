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

        let history = ["один", "два", "три", "четыре"]
        check(LiveTranscript.withoutReplay(["три", "четыре", "пять"], history: history) == ["пять"], "replay matches suffix, not history prefix")
        check(LiveTranscript.withoutReplay(["три"], history: history).isEmpty, "incomplete replay held")
        check(LiveTranscript.withoutReplay(["три", "четыре", "пять", "шесть"], history: history) == ["пять", "шесть"], "replay stripped on every cumulative partial")
        check(LiveTranscript.prefixBoundary(["по", "этому"], in: ["поэтому", "сделай"]) == 1, "token contraction preserves next word")
        check(LiveTranscript.prefixBoundary(["сделай", "новый"], in: ["создай", "новый", "компонент"]) == 2, "revised frozen wording does not duplicate new words")
        let rules = DeveloperDictionary.entries
        let correct: (String) -> String = { TranscriptCorrector.correct($0, rules: rules) }
        var mapping = LiveTranscript()
        mapping.update("создай некст джей эс", timed: [], correct: correct); mapping.freeze()
        mapping.update("создай Next.js компонент", timed: [], correct: correct)
        check(mapping.volatile == "компонент", "dictionary token contraction does not drop next word")
        var timed = LiveTranscript()
        timed.update("один два", timed: [LiveSpeechWord(text:"один",start:0,end:1), LiveSpeechWord(text:"два",start:1,end:2)], correct: {$0})
        timed.freeze(); timed.restarted()
        timed.update("два три", timed: [LiveSpeechWord(text:"два",start:1,end:2), LiveSpeechWord(text:"три",start:2,end:3)], correct: {$0})
        check(timed.target == "один два три", "audio timestamps suppress overlapping replay")

        for phrase in ["перенос строки", "с новой строки", "на новую строку", "перевод строки", "new line", "line break"] {
            check(VoiceCommands.applyInline(to: "привет \(phrase) мир") == "привет\nмир", "line command: \(phrase)")
        }
        for phrase in ["абзац", "новый абзац", "с нового абзаца", "new paragraph", "paragraph"] {
            check(VoiceCommands.applyInline(to: "привет \(phrase) мир") == "привет\n\nмир", "paragraph command: \(phrase)")
        }
        check(VoiceCommands.applyInline(to: "с новой строки мир", followsText: true) == "\nмир", "line command opens a span that continues committed text")
        check(VoiceCommands.applyInline(to: "абзац") == "абзац", "leading command with nothing before it stays text")
        var lines = LiveTranscript()
        lines.update("привет", timed: [LiveSpeechWord(text:"привет",start:0,end:1)], correct: {$0}); lines.freeze()
        lines.update("привет с новой строки мир", timed: [LiveSpeechWord(text:"привет",start:0,end:1), LiveSpeechWord(text:"с",start:1,end:1.2), LiveSpeechWord(text:"новой",start:1.2,end:1.5), LiveSpeechWord(text:"строки",start:1.5,end:2), LiveSpeechWord(text:"мир",start:2,end:2.5)],
                     correct: { VoiceCommands.applyInline(to: $0) }, correctSpan: { VoiceCommands.applyInline(to: $0, followsText: true) })
        check(lines.target == "привет\nмир", "line command after a pause joins without a stray space")

        func timedWords(_ words: [String]) -> [LiveSpeechWord] {
            words.enumerated().map { LiveSpeechWord(text: $1, start: Double($0), end: Double($0) + 0.8) }
        }
        var phrase = LiveTranscript()
        let first = "сделай мне новый компонент каталога товаров".components(separatedBy: " ")
        phrase.update(first.joined(separator: " "), timed: timedWords(first), correct: {$0})
        check(phrase.freezeStable(holding: 2) == "сделай мне новый компонент", "phrase mode commits all but the held words")
        check(phrase.committed == "сделай мне новый компонент" && phrase.volatile == "каталога товаров", "held words stay volatile")
        let second = first + ["с", "адаптивной", "сеткой"]
        phrase.update(second.joined(separator: " "), timed: timedWords(second), correct: {$0})
        check(phrase.volatile == "каталога товаров с адаптивной сеткой", "held words continue into the next update")
        phrase.update("сделай мне новый компонент каталога товаров с адаптивной сеткой", timed: [], correct: {$0})
        phrase.freeze()
        check(phrase.committed == "сделай мне новый компонент каталога товаров с адаптивной сеткой", "final freeze flushes the held words once")
        var revised = LiveTranscript()
        let a = "открой файл и запусти тесты".components(separatedBy: " ")
        revised.update(a.joined(separator: " "), timed: [], correct: {$0})
        revised.freezeStable(holding: 2)
        revised.update("открой файл и запусти тесты потом", timed: [], correct: {$0})
        check(revised.volatile == "запусти тесты потом", "phrase mode without timestamps aligns by text")
        var wordRevised = LiveTranscript()
        wordRevised.update("открой файл и запусти тест", timed: [], correct: {$0})
        wordRevised.freezeStable(holding: 2)
        wordRevised.update("открой файл и запусти тесты потом", timed: [], correct: {$0})
        check(wordRevised.committed == "открой файл и" && wordRevised.volatile == "запусти тесты потом", "a revised held word is not duplicated")

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
        settings.translateDictateHotkey = ModifierCombo(fn:true,shift:true)
        settings.liveDictateHotkey = ModifierCombo(fn:true,command:true)
        settings.useFnOnly()
        check(!settings.openHotKey.isAssigned && !settings.selectionHotKey.isAssigned && !settings.screenshotHotKey.isAssigned && settings.dictateHotkey.isEmpty && settings.translateDictateHotkey.isEmpty && settings.liveDictateHotkey == ModifierCombo(fn:true), "customized legacy shortcuts migrate to Fn only")
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        check(decoded.liveDictateHotkey == ModifierCombo(fn:true) && !decoded.openHotKey.isAssigned, "Fn-only settings round trip")
        print("\(passed) regression checks passed")
    }
}
