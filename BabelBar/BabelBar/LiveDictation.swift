import Foundation
import Speech
import AVFoundation
import AppKit

struct LiveSpeechWord {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// Pure transcript bookkeeping, independent of the active editor. Timestamps
/// identify audio already committed across overlapping recognition requests.
/// A text alignment fallback handles partials without usable segment timing.
struct LiveTranscript {
    private(set) var committed = ""
    private(set) var volatile = ""
    private var through: TimeInterval?
    private var latestEnd: TimeInterval?
    private var history: [String] = []
    private var frozenPrefix: [String] = []
    private var lastWords: [String] = []

    mutating func update(_ text: String, timed: [LiveSpeechWord], correct: (String) -> String) {
        let canonical = Self.words(correct(text))
        let content = Self.withoutReplay(canonical, history: history)
        lastWords = content
        let validTiming = !timed.isEmpty && timed.allSatisfy { $0.end > $0.start && $0.start >= 0 }
        latestEnd = validTiming ? timed.last?.end : nil
        if validTiming, let through {
            let fresh = timed.filter { ($0.start + $0.end) / 2 > through + 0.01 }
            volatile = correct(fresh.map(\.text).joined(separator: " "))
        } else {
            let offset = Self.prefixBoundary(frozenPrefix, in: content)
            volatile = content.dropFirst(offset).joined(separator: " ")
        }
    }

    @discardableResult
    mutating func freeze() -> String {
        let result = volatile
        committed = Self.join(committed, volatile)
        volatile = ""
        frozenPrefix = lastWords
        // If partial timing is unavailable, keep using text alignment until a
        // later committed result establishes a reliable audio boundary.
        if let latestEnd { through = max(through ?? 0, latestEnd) }
        else { through = nil }
        return result
    }

    mutating func restarted() {
        history = Array((history + lastWords).suffix(250))
        frozenPrefix = []; lastWords = []
    }

    var target: String { Self.join(committed, volatile) }
    static func join(_ a: String, _ b: String) -> String {
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty ? b : a }
        return a.hasSuffix("\n") ? a + b : a + " " + b
    }
    static func words(_ s: String) -> [String] { s.components(separatedBy: " ").filter { !$0.isEmpty } }
    static func key(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е").filter { $0.isLetter || $0.isNumber }
    }

    /// Recompute on EVERY partial of the new request. A partial matching only
    /// the middle of the replay is held until the rest of that overlap arrives.
    static func withoutReplay(_ words: [String], history: [String]) -> [String] {
        guard !history.isEmpty, !words.isEmpty else { return words }
        let incoming = words.map(key)
        let old = history.map(key)
        var best = 0
        for start in old.indices {
            let suffix = Array(old[start...])
            let n = min(suffix.count, incoming.count)
            if Array(suffix.prefix(n)) == Array(incoming.prefix(n)) { best = max(best, n) }
        }
        return Array(words.dropFirst(best))
    }

    /// Align the frozen text with the new partial instead of counting old words.
    /// Canonical dictionary forms make "некст джей эс" and "Next.js" equivalent.
    /// Character-prefix matching also handles tokenization changes such as
    /// "по этому" → "поэтому". Bounded edit alignment handles revised wording.
    static func prefixBoundary(_ prefix: [String], in words: [String]) -> Int {
        guard !prefix.isEmpty else { return 0 }
        let wanted = prefix.map(key).joined()
        var joined = ""
        for (i, word) in words.enumerated() {
            joined += key(word)
            if joined == wanted { return i + 1 }
            if joined.count > wanted.count { break }
        }
        let a = prefix.map(key), b = words.map(key)
        var exact = 0
        while exact < a.count, exact < b.count, a[exact] == b[exact] { exact += 1 }
        if exact == a.count || exact == b.count { return exact }
        // Only align the differing tail. An unbounded matrix would penalize long dictation.
        let left = Array(a.dropFirst(exact).prefix(128))
        let right = Array(b.dropFirst(exact).prefix(left.count + 16))
        guard a.count - exact <= 128 else { return words.count } // ambiguous: preserve frozen text
        var row = Array(0...right.count)
        for (i, token) in left.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: right.count)
            for j in right.indices {
                next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (token == right[j] ? 0 : 1))
            }
            row = next
        }
        var best = 0
        for index in 1...max(1, right.count) where index <= right.count {
            let cost = row[index], previousCost = row[best]
            let distance = abs(index - left.count), previousDistance = abs(best - left.count)
            if cost < previousCost || (cost == previousCost && distance < previousDistance) { best = index }
        }
        return exact + best
    }
}

/// All lifecycle and callbacks are serialized on main. The audio lock covers
/// replay, request replacement and append order; obsolete callbacks are checked
/// again AFTER hopping to main. Replaced tasks and retry timers are cancelled.
final class AppleSpeechStreamer {
    var onPartial: ((String, [LiveSpeechWord], Bool) -> Void)?
    var onRestart: (() -> Void)?
    private let recognizer: SFSpeechRecognizer
    private let contextual: [String]
    private let requiresOnDevice: Bool
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var wantsAudio = false
    private var generation = 0
    private var replay: [AVAudioPCMBuffer] = []
    private var replaySeconds = 0.0
    private var audioSeconds = 0.0
    private var retry: DispatchWorkItem?
    private var lastRestart = Date.distantPast

    init(recognizer: SFSpeechRecognizer, contextual: [String], requiresOnDevice: Bool) {
        self.recognizer = recognizer; self.contextual = contextual; self.requiresOnDevice = requiresOnDevice
    }
    func start() { wantsAudio = true; beginRequest() }
    func append(buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in source.indices {
            guard let src = source[i].mData, let dst = destination[i].mData else { return }
            memcpy(dst, src, Int(source[i].mDataByteSize))
        }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        audioSeconds += duration; replaySeconds += duration; replay.append(copy)
        while replaySeconds > 6, let first = replay.first {
            replaySeconds -= Double(first.frameLength) / first.format.sampleRate
            replay.removeFirst()
        }
        request?.append(buffer)
    }
    func cancel() {
        wantsAudio = false; generation += 1; retry?.cancel(); retry = nil
        lock.lock(); let old = request; request = nil; lock.unlock()
        old?.endAudio(); task?.cancel(); task = nil
    }
    func restartNow() {
        guard wantsAudio, retry == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsAudio else { return }
            self.retry = nil; self.lastRestart = Date()
            self.onRestart?(); self.beginRequest()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.6 - Date().timeIntervalSince(lastRestart)), execute: work)
    }
    private func beginRequest() {
        generation += 1
        let gen = generation
        task?.cancel(); task = nil
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true; next.addsPunctuation = true
        next.contextualStrings = contextual; next.requiresOnDeviceRecognition = requiresOnDevice
        lock.lock()
        request?.endAudio()
        let offset = max(0, audioSeconds - replaySeconds)
        for buffer in replay { next.append(buffer) }
        request = next
        lock.unlock()
        task = recognizer.recognitionTask(with: next) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.wantsAudio, self.generation == gen else { return }
                if let result {
                    let transcription = result.bestTranscription
                    let formatted = transcription.formattedString as NSString
                    let segments = transcription.segments
                    let words = segments.enumerated().map { i, segment in
                        let end = i + 1 < segments.count ? segments[i + 1].substringRange.location : formatted.length
                        let text = formatted.substring(with: NSRange(location: segment.substringRange.location,
                                                                     length: max(0, end - segment.substringRange.location)))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return LiveSpeechWord(text: text, start: offset + segment.timestamp,
                                              end: offset + segment.timestamp + segment.duration)
                    }
                    self.onPartial?(transcription.formattedString, words, result.isFinal)
                }
                if error != nil || result?.isFinal == true { self.restartNow() }
            }
        }
    }
}

private enum LiveRunningFlag {
    private static let lock = NSLock()
    private static var value = false
    static var isOn: Bool { lock.lock(); defer { lock.unlock() }; return value }
    static func set(_ on: Bool) { lock.lock(); value = on; lock.unlock() }
}

@MainActor
final class LiveDictationController {
    static let shared = LiveDictationController()
    private init() {}
    enum Phase { case idle, starting, listening, finishing }
    private(set) var phase: Phase = .idle { didSet { LiveRunningFlag.set(phase != .idle) } }
    nonisolated static var isRunningNow: Bool { LiveRunningFlag.isOn }
    var isRunning: Bool { phase != .idle }
    private var recorder = AudioRecorder()
    private var streamer: AppleSpeechStreamer?
    private let typer = LiveTyper.shared
    private let inputGuard = LiveInputGuard()
    private var settings: AppSettings?
    private var rules: [DictEntry] = []
    private var transcript = LiveTranscript()
    private var target: AXLiveTextTarget?
    private var freezeTimer: DispatchWorkItem?
    private var watchdog: Timer?
    private var appObserver: Any?
    private var lastPartial = Date()
    private var session = UUID()
    private var finishingTask: Task<Void, Never>?
    private var reportError: ((LKey) -> Void)?

    func start(settings: AppSettings, onError: @escaping (LKey) -> Void) {
        // The hotkey state machine just began a new session. A press that finds a
        // session already listening means "stop"; resync the machine so the next
        // press starts cleanly instead of running one step out of phase.
        if phase == .listening || phase == .starting {
            stop()
            VoiceHotkeys.shared.cancelActiveSession()
            return
        }
        if phase == .finishing { abort(resetHotkeys: false) }
        guard phase == .idle else { return }
        phase = .starting; session = UUID()
        let id = session
        self.settings = settings; reportError = onError
        rules = PersonalDictionaryStore.shared.activeRules(developerEnabled: settings.developerDictionaryEnabled)
        requestMic { [weak self] ok in
            guard let self, self.session == id, self.phase == .starting else { return }
            guard ok else { self.abort(error: .errMicSpeech); return }
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    guard self.session == id, self.phase == .starting else { return }
                    guard status == .authorized else { self.abort(error: .errSpeechDenied); return }
                    self.acquireTarget(session: id)
                }
            }
        }
    }

    func stop() {
        guard phase == .listening else {
            if phase == .starting { abort() }
            return
        }
        // Stop receiving audio/results immediately. Only the already-known tail
        // is flushed, with the same field/caret checks; manual input cancels it.
        phase = .finishing
        streamer?.cancel(); streamer = nil
        recorder.stop()
        freeze()
        let id = session
        finishingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.typer.flush()
            guard !Task.isCancelled, self.session == id, self.phase == .finishing else { return }
            if self.settings?.learnFromCorrections == true, let target = self.target, self.typer.isCurrent() {
                CorrectionObserver.noteSessionEnded(typed: self.typer.screen, target: target)
            } else { CorrectionObserver.forget() }
            self.teardown(); self.phase = .idle
        }
    }

    /// Electron and Chromium editors publish their accessibility tree only after a
    /// client asks for it, and the tree needs a moment to appear. Ask once, then
    /// poll briefly instead of failing on the first empty answer.
    private func acquireTarget(session id: UUID, attempt: Int = 0) {
        guard session == id, phase == .starting else { return }
        if let target = AXLiveTextTarget(), typer.begin(target: target) { beginSession(target: target); return }
        guard attempt < 10, AXIsProcessTrusted() else { abort(error: .errLiveField); return }
        if attempt == 0, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            AXLiveTextTarget.requestAccessibilityTree(pid: pid)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.acquireTarget(session: id, attempt: attempt + 1)
        }
    }

    private func beginSession(target: AXLiveTextTarget) {
        guard let settings else { abort(); return }
        self.target = target
        if settings.learnFromCorrections { CorrectionObserver.checkPreviousSessionCorrection(target: target) }
        else { CorrectionObserver.forget() }
        guard let recognizer = SFSpeechRecognizer(locale: settings.liveDictationLanguage.locale), recognizer.isAvailable else {
            abort(error: .errSpeechUnavailable); return
        }
        // Local recognition whenever the system has the model: no network round trip,
        // partials arrive faster. The server is only a fallback when the setting allows it.
        let onDevice = recognizer.supportsOnDeviceRecognition
        if settings.liveOnDeviceOnly, !onDevice { abort(error: .errSpeechOnDevice); return }
        let streamer = AppleSpeechStreamer(recognizer: recognizer,
            contextual: DictionaryContext.contextualStrings(personal: PersonalDictionaryStore.shared.entries,
                         developerEnabled: settings.developerDictionaryEnabled, frequencyEnabled: settings.frequencyLearningEnabled),
            requiresOnDevice: onDevice)
        let id = session
        streamer.onPartial = { [weak self] text, timed, final in
            guard let self, self.session == id, self.phase == .listening else { return }
            self.ingest(text, timed: timed, final: final)
        }
        streamer.onRestart = { [weak self] in
            guard let self, self.session == id, self.phase == .listening else { return }
            self.freeze(); self.transcript.restarted()
        }
        self.streamer = streamer; transcript = LiveTranscript()
        typer.onInvalidated = { [weak self] in self?.abort() }
        inputGuard.start { [weak self] in self?.abort() }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.abort() }
        }
        recorder.onBuffer = { [weak streamer] in streamer?.append(buffer: $0) }
        recorder.accumulateSamples = false
        if settings.duckAudio { SystemAudio.duck() }
        streamer.start()
        do { try recorder.start() } catch { abort(error: .errDictation); return }
        phase = .listening; lastPartial = Date()
        MicLevel.shared.showDot = settings.showRecordingDot
        RecordingOverlay.shared.show()
        if settings.voiceSoundEnabled { SystemSounds.play(settings.voiceSoundName, volume: Float(settings.voiceSoundVolume)) }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .listening || self.phase == .finishing else { return }
                // During our own acknowledged replacement, selection temporarily
                // differs; LiveTyper performs the ownership check itself.
                if self.phase == .listening, MicLevel.shared.level > 0.04,
                   Date().timeIntervalSince(self.lastPartial) > 4 {
                    self.lastPartial = Date(); self.streamer?.restartNow()
                }
            }
        }
    }

    private func ingest(_ text: String, timed: [LiveSpeechWord], final: Bool) {
        lastPartial = Date()
        let rules = self.rules, commands = settings?.voiceCommandsEnabled == true
        transcript.update(text, timed: timed) {
            let result = TranscriptCorrector.correct($0, rules: rules)
            return commands ? VoiceCommands.applyInline(to: result) : result
        }
        freezeTimer?.cancel()
        if final { freeze(); return }
        typer.render(target: transcript.target, frozen: transcript.committed.count)
        let id = session
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session == id, self.phase == .listening else { return }
            self.freeze()
        }
        freezeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func freeze() {
        freezeTimer?.cancel(); freezeTimer = nil
        let span = transcript.freeze()
        typer.render(target: transcript.committed, frozen: transcript.committed.count)
        if settings?.frequencyLearningEnabled == true, !span.isEmpty {
            let personal = PersonalDictionaryStore.shared.entries.filter(\.enabled).map(\.written)
            let id = session, committed = transcript.committed
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.typer.flush()
                guard self.session == id, self.typer.screen.hasPrefix(committed) else { return }
                FrequencyTracker.recordHits(in: span, personalTerms: personal)
            }
        }
    }

    private func abort(error: LKey? = nil, resetHotkeys: Bool = true) {
        guard phase != .idle else { return }
        let callback = reportError
        session = UUID(); finishingTask?.cancel(); finishingTask = nil
        teardown(); phase = .idle
        CorrectionObserver.forget()
        if resetHotkeys { VoiceHotkeys.shared.cancelActiveSession() }
        if let error { callback?(error) }
    }

    private func teardown() {
        freezeTimer?.cancel(); freezeTimer = nil
        watchdog?.invalidate(); watchdog = nil
        inputGuard.stop()
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        streamer?.cancel(); streamer = nil
        recorder.stop(); recorder.onBuffer = nil; recorder.accumulateSamples = true
        typer.cancel(); typer.onInvalidated = nil; target = nil
        SystemAudio.restore(); RecordingOverlay.shared.hide()
        settings = nil; reportError = nil
    }

    private func requestMic(_ callback: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: callback(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { callback(ok) } }
        default: callback(false)
        }
    }
}
