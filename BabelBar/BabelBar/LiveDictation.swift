import Foundation
import Speech
import AVFoundation
import AppKit

// =============================================================================
//  Real-time smart dictation (v3.0, TZ "Real-Time Smart Dictation").
//
//  Pipeline:  Microphone → SFSpeechRecognizer (streaming partial results)
//             → dictionary correction → LiveTyper (direct live insert into the
//             focused app's text field) → finalized text.
//
//  The user sees the spoken text appear in the field they are typing in, while
//  they speak — no preview window, no floating bar (TZ §2–§4). The recognizer
//  is behind a protocol so a SpeechAnalyzer engine can be added later without
//  touching the controller (this Xcode's macOS 15 SDK has no SpeechAnalyzer).
// =============================================================================

// MARK: - Streaming recognizer

/// Continuous speech-to-text with partial results. One instance = one dictation
/// session. `utterance` in the callbacks is the transcript of the *current*
/// recognition request only; the controller accumulates across request
/// restarts (`onRestart`).
protocol StreamingRecognizer {
    func start()
    func append(buffer: AVAudioPCMBuffer)
    /// No more audio is coming; a final result will still be delivered.
    func finish()
    func cancel()
}

/// Apple Speech streaming engine (macOS 13+). Server-based recognition stops
/// after about a minute, and some requests die on their own; while the session
/// is still running this streamer transparently continues with a fresh request
/// — the text already printed in the target field is unaffected, so long
/// dictations (TZ §13: long text) never truncate.
final class AppleSpeechStreamer: StreamingRecognizer {
    /// Transcript of the current request so far, and whether it is final.
    var onPartial: ((String, Bool) -> Void)?
    /// The request ended and a new one begins: the utterance counter resets.
    var onRestart: (() -> Void)?

    private let recognizer: SFSpeechRecognizer
    private let contextual: [String]
    private let requiresOnDevice: Bool
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Session-level intent: true from start() until finish()/cancel(). While
    /// true, a dead request gets replaced; false means the session is over and
    /// the final result may arrive in peace.
    private var wantsAudio = false
    private var lastRestartAt = Date.distantPast
    /// Bumped on every new recognition request. Late callbacks of a request that
    /// was already replaced are dropped — they would corrupt the new utterance.
    private var generation = 0

    init(recognizer: SFSpeechRecognizer, contextual: [String], requiresOnDevice: Bool) {
        self.recognizer = recognizer
        self.contextual = contextual
        self.requiresOnDevice = requiresOnDevice
    }

    func start() {
        wantsAudio = true
        beginRequest()
    }

    /// Called on the audio thread — must stay cheap.
    func append(buffer: AVAudioPCMBuffer) {
        lock.lock(); let req = request; lock.unlock()
        req?.append(buffer)
    }

    func finish() {
        wantsAudio = false
        lock.lock(); let req = request; lock.unlock()
        req?.endAudio()
    }

    func cancel() {
        wantsAudio = false
        lock.lock()
        let t = task
        task = nil
        request = nil
        lock.unlock()
        t?.cancel()
    }

    /// Replace the current request on the controller's initiative (the controller
    /// hit a mapping conflict it resolves by starting a fresh utterance).
    func restartNow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsAudio else { return }
            self.lastRestartAt = Date()
            self.onRestart?()
            self.beginRequest()
        }
    }

    private func beginRequest() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.contextualStrings = contextual
        // Prefer on-device when the locale supports it: private, offline, and —
        // importantly — not bound by the server's ~1-minute request limit.
        req.requiresOnDeviceRecognition = requiresOnDevice
        lock.lock()
        generation += 1
        let gen = generation
        request = req
        lock.unlock()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            // A request that was already replaced may still deliver its final
            // result — that text belongs to history the controller already froze.
            self.lock.lock()
            let current = self.generation
            self.lock.unlock()
            guard gen == current else { return }
            if let result {
                self.onPartial?(result.bestTranscription.formattedString, result.isFinal)
            }
            if error != nil || result?.isFinal == true, self.wantsAudio {
                // Recognition callbacks arrive on a Speech-internal queue.
                DispatchQueue.main.async { self.restart() }
            }
        }
    }

    /// Replace a dead request. Throttled; a throttled-out retry reschedules
    /// itself so a briefly failing recognizer can't stall the session silently.
    private func restart() {
        guard wantsAudio else { return }
        guard Date().timeIntervalSince(lastRestartAt) > 0.5 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.restart()
            }
            return
        }
        lastRestartAt = Date()
        onRestart?()
        beginRequest()
    }
}

/// Thread-safe mirror of the live-session state — AppState (deliberately not
/// MainActor) checks it from nonisolated contexts.
private enum LiveRunningFlag {
    private static let lock = NSLock()
    private static var value = false
    static var isOn: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    static func set(_ on: Bool) {
        lock.lock(); value = on; lock.unlock()
    }
}

// MARK: - Live dictation controller

/// Orchestrates one live dictation session: permissions, audio capture,
/// streaming recognition, transcript→field mapping and the freeze policy that
/// keeps user edits untouchable.
///
/// Freeze policy (the heart of TZ §5–§7): raw recognizer tokens are "volatile"
/// while speech continues; the typer may rewrite them via backspaces. When no
/// new partial arrives for `freezeDelay` (a speech pause), everything printed
/// becomes *frozen*: it is treated as ordinary user text from that moment and
/// is never revised again. The user can pause, edit by hand, move the cursor
/// and keep talking — new text is typed wherever the cursor now is.
@MainActor
final class LiveDictationController {
    static let shared = LiveDictationController()
    private init() {}

    enum Phase { case idle, starting, listening, finishing }
    private(set) var phase: Phase = .idle {
        didSet { LiveRunningFlag.set(phase != .idle) }
    }
    var isRunning: Bool { phase != .idle }

    /// Nonisolated mirror of `isRunning` for callers that are deliberately not
    /// MainActor (AppState) — lock-protected, safe from any thread.
    nonisolated static var isRunningNow: Bool { LiveRunningFlag.isOn }

    private var recorder = AudioRecorder()
    private var streamer: AppleSpeechStreamer?
    private let typer = LiveTyper.shared
    private var settings: AppSettings?
    private var rules: [DictEntry] = []
    private var sessionApp = ""

    // Transcript mapping (raw = what the recognizer said, uncorrected).
    //
    //   settledTokens        — raw tokens of COMPLETED recognition requests (append-only;
    //                          the current request's utterance is NOT in here, because its
    //                          transcript is cumulative and still growing).
    //   lastUtteranceTokens  — the current request's latest utterance.
    //   printedTokens        — everything asked of the typer so far; in the normal flow it is
    //                          exactly (settledTokens + lastUtteranceTokens) truncated at the
    //                          newest render.
    //   frozenCount          — printedTokens[0..<frozenCount] are frozen: never revised again.
    private var settledTokens: [String] = []
    private var lastUtteranceTokens: [String] = []
    private var printedTokens: [String] = []
    private var frozenCount = 0
    private var correctedCommitted = ""        // corrected text of the frozen part
    private var volatileCorrected = ""         // corrected text currently shown as volatile

    private var freezeTimer: DispatchWorkItem?
    /// How long a speech pause freezes the volatile tail (TZ §6: pause → edit →
    /// continue must be safe; hand edits are never overwritten).
    private let freezeDelay: TimeInterval = 1.4
    private var appObserver: Any?

    // MARK: - Session lifecycle

    func start(settings: AppSettings, onError: @escaping (LKey) -> Void) {
        guard phase == .idle else { return }
        phase = .starting
        self.settings = settings
        self.rules = PersonalDictionaryStore.shared.activeRules(developerEnabled: settings.developerDictionaryEnabled)

        requestMic { [weak self] ok in
            guard let self, self.phase == .starting else { return }
            guard ok else { self.fail(.errMicSpeech, onError); return }
            self.requestSpeech { ok2 in
                guard self.phase == .starting else { return }
                guard ok2 else { self.fail(.errSpeechDenied, onError); return }
                self.beginSession(onError: onError)
            }
        }
    }

    func stop() {
        switch phase {
        case .listening:
            phase = .finishing
            freezeTimer?.cancel(); freezeTimer = nil
            streamer?.finish()   // the final result still arrives via onPartial
            // Bound the wait for the final result, then conclude whatever we have.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.conclude()
            }
        case .starting:
            // Stopped while permission prompts were still up (a quick tap-toggle):
            // abort — the permission callbacks guard on `.starting` and back off.
            phase = .idle
            freezeTimer?.cancel(); freezeTimer = nil
            teardown()
        default:
            break
        }
    }

    // MARK: - Session internals

    private func beginSession(onError: @escaping (LKey) -> Void) {
        // Locale chain: the user's choice, then ru, then en — whatever the
        // system can actually recognize here.
        let chosen = settings?.liveDictationLanguage.locale ?? Locale.current
        var recognizer: SFSpeechRecognizer?
        for candidate in [chosen, Locale(identifier: "ru_RU"), Locale(identifier: "en_US")] {
            if let r = SFSpeechRecognizer(locale: candidate), r.isAvailable {
                recognizer = r
                break
            }
        }
        guard let recognizer else { fail(.errSpeechUnavailable, onError); return }
        let onDevice = recognizer.supportsOnDeviceRecognition
        if settings?.liveOnDeviceOnly == true, !onDevice {
            fail(.errSpeechOnDevice, onError)
            return
        }

        let streamer = AppleSpeechStreamer(
            recognizer: recognizer,
            contextual: DictionaryContext.contextualStrings(personal: PersonalDictionaryStore.shared.entries),
            requiresOnDevice: onDevice)
        streamer.onPartial = { [weak self] utterance, isFinal in
            DispatchQueue.main.async { self?.ingest(utterance: utterance, isFinal: isFinal) }
        }
        streamer.onRestart = { [weak self] in
            DispatchQueue.main.async { self?.handleRestart() }
        }
        self.streamer = streamer

        CorrectionObserver.checkPreviousSessionCorrection()   // learn from last session's edits
        typer.reset()
        settledTokens = []
        lastUtteranceTokens = []
        printedTokens = []
        frozenCount = 0
        correctedCommitted = ""
        volatileCorrected = ""
        sessionApp = Self.frontmostBundleID()

        recorder.onBuffer = { [weak streamer] buffer in streamer?.append(buffer: buffer) }
        recorder.accumulateSamples = false   // streaming: don't buffer minutes of audio in RAM
        if settings?.duckAudio == true { SystemAudio.duck() }
        do {
            try recorder.start()
        } catch {
            recorder.onBuffer = nil
            recorder.accumulateSamples = true
            SystemAudio.restore()
            fail(.errDictation, onError)
            return
        }
        if settings?.voiceSoundEnabled == true {
            SystemSounds.play(settings?.voiceSoundName ?? "Pop",
                              volume: Float(settings?.voiceSoundVolume ?? 0.8))
        }
        MicLevel.shared.showDot = settings?.showRecordingDot ?? true
        RecordingOverlay.shared.show()

        // If the user switches apps mid-session, the field we were revising is
        // gone: freeze the volatile tail so we never backspace into a different
        // app's field again (TZ §16).
        appObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleAppSwitch()
        }

        streamer.start()
        phase = .listening
    }

    /// New recognition result. Maps the cumulative transcript onto what is
    /// already printed, corrects the volatile span through the dictionaries and
    /// hands the target state to the typer.
    private func ingest(utterance: String, isFinal: Bool) {
        guard phase == .listening || phase == .finishing else { return }
        let utteranceTok = Self.tokens(utterance)
        lastUtteranceTokens = utteranceTok
        let full = settledTokens + utteranceTok
        let p = Self.commonPrefixNorm(printedTokens, full)

        if p < frozenCount {
            // Rare: the recognizer revised already-frozen words. We never delete
            // frozen text (TZ §16) and we never duplicate it either — so the
            // revision is dropped: everything printed is declared final, the
            // mapping realigns to the recognizer's own history, and recognition
            // continues with a fresh request so future speech arrives cleanly.
            freezeCurrentVolatile()
            settledTokens += lastUtteranceTokens
            lastUtteranceTokens = []
            printedTokens = settledTokens
            frozenCount = printedTokens.count
            streamer?.restartNow()
            return
        }
        if p < printedTokens.count {
            // The revision touched only the volatile territory: shrink the
            // printed mapping — the typer's own diff backspaces the replaced tail.
            printedTokens.removeSubrange(p...)
        }
        let novel = Array(full.dropFirst(p))
        printedTokens.append(contentsOf: novel)
        let corrected = TranscriptCorrector.correct(novel.joined(separator: " "), rules: rules)
        // Apple Speech (addsPunctuation) often capitalizes a sentence's first word
        // only after the partial was already printed — chasing that case change
        // would erase and retype the whole volatile span at every sentence start.
        // Keep the on-screen casing of the unchanged prefix instead.
        volatileCorrected = Self.stabilizedPrefix(old: volatileCorrected, new: corrected)
        typer.render(committed: correctedCommitted, volatile: volatileCorrected)
        if phase == .listening { scheduleFreeze() }
    }

    /// Longest case-insensitive common prefix of `old` and `new`, taken from `old`
    /// (what's already on screen), with the remainder from `new`. Case-only
    /// revisions of already-printed characters therefore cost zero keystrokes.
    static func stabilizedPrefix(old: String, new: String) -> String {
        guard !old.isEmpty, !new.isEmpty else { return new }
        var oi = old.startIndex
        var ni = new.startIndex
        while oi < old.endIndex, ni < new.endIndex {
            if old[oi].lowercased() != new[ni].lowercased() { break }
            old.formIndex(after: &oi)
            new.formIndex(after: &ni)
        }
        let kept = old[old.startIndex ..< oi]
        if kept == new[new.startIndex ..< ni] { return new }
        return String(kept) + new[ni...]
    }

    /// The current request died (server ~1-min limit or an error) and a fresh one
    /// begins: settle its final transcript into history and freeze the volatile tail.
    private func handleRestart() {
        freezeCurrentVolatile()
        settledTokens += lastUtteranceTokens
        lastUtteranceTokens = []
    }

    private func scheduleFreeze() {
        freezeTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.freezeCurrentVolatile() }
        freezeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + freezeDelay, execute: work)
    }

    /// Freeze the volatile tail: it becomes ordinary text from the user's point
    /// of view — BabelBar will never revise it again.
    private func freezeCurrentVolatile() {
        freezeTimer?.cancel(); freezeTimer = nil
        frozenCount = printedTokens.count
        let span = volatileCorrected
        volatileCorrected = ""
        guard !span.isEmpty else { return }
        correctedCommitted += correctedCommitted.isEmpty ? span : " " + span
        if settings?.frequencyLearningEnabled == true {
            let personalTerms = PersonalDictionaryStore.shared.entries.filter(\.enabled).map(\.written)
            FrequencyTracker.recordHits(in: span, personalTerms: personalTerms)   // TZ §12
        }
        typer.render(committed: correctedCommitted, volatile: "")
    }

    private func handleAppSwitch() {
        guard phase == .listening || phase == .finishing else { return }
        typer.freezeVolatile()          // stop revising the old field immediately
        freezeCurrentVolatile()
        sessionApp = ""                 // the end-of-session AX read would hit the wrong field
    }

    private func conclude() {
        guard phase == .finishing else { return }
        phase = .idle
        freezeTimer?.cancel(); freezeTimer = nil
        freezeCurrentVolatile()
        teardown()

        // Learning: snapshot the field we typed into — but only if the user
        // stayed in the same app for the whole session (TZ §11, §14).
        let typed = correctedCommitted
        if let settings, settings.learnFromCorrections, !typed.isEmpty,
           !sessionApp.isEmpty, sessionApp == Self.frontmostBundleID() {
            CorrectionObserver.noteSessionEnded(typed: typed)
        } else {
            CorrectionObserver.forget()
        }
        settings = nil
    }

    private func fail(_ key: LKey, _ onError: @escaping (LKey) -> Void) {
        phase = .idle
        freezeTimer?.cancel(); freezeTimer = nil
        teardown()
        onError(key)
    }

    private func teardown() {
        if let appObserver {
            NotificationCenter.default.removeObserver(appObserver)
            self.appObserver = nil
        }
        streamer?.cancel()
        streamer = nil
        recorder.onBuffer = nil
        recorder.accumulateSamples = true
        recorder.stop()
        SystemAudio.restore()
        RecordingOverlay.shared.hide()
    }

    // MARK: - Permissions

    private func requestMic(_ cb: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: cb(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { cb(ok) }   // keep the chain on the main actor
            }
        default: cb(false)
        }
    }

    private func requestSpeech(_ cb: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { cb(status == .authorized) }
        }
    }

    // MARK: - Token mapping helpers

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Comparable form of a raw token (same normalization as VoiceCommands).
    private static func core(_ token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…—-«»\"'()"))
    }

    private static func commonPrefixNorm(_ a: [String], _ b: [String]) -> Int {
        var n = 0
        while n < a.count, n < b.count, core(a[n]) == core(b[n]) { n += 1 }
        return n
    }

    private static func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}
