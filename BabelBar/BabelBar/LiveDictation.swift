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

    // Ring buffer of the last `replayCap` seconds of audio, replayed into every
    // NEW request. Without it, a request that dies during warm-up or at the
    // server's 1-minute boundary takes its buffered audio with it — the user's
    // opening or mid-sentence words simply vanished. (The controller strips the
    // re-transcribed echo from the new request's transcript.)
    private var replay: [AVAudioPCMBuffer] = []
    private var replaySeconds: Double = 0
    private let replayCap: Double = 6.0

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
        lock.lock()
        let req = request
        stashForReplay(buffer)
        lock.unlock()
        req?.append(buffer)
    }

    /// Deep copy so the audio engine can recycle the tap buffer. Lock held.
    private func stashForReplay(_ buffer: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for c in 0 ..< Int(buffer.format.channelCount) {
                memcpy(dst[c], src[c], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
            for c in 0 ..< Int(buffer.format.channelCount) {
                memcpy(dst[c], src[c], Int(buffer.frameLength) * MemoryLayout<Int16>.size)
            }
        }
        replay.append(copy)
        replaySeconds += Double(buffer.frameLength) / buffer.format.sampleRate
        while replaySeconds > replayCap, let first = replay.first {
            replay.removeFirst()
            replaySeconds -= Double(first.frameLength) / first.format.sampleRate
        }
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

    /// Replace the current request on the controller's initiative — kept for
    /// future use (the mapping no longer needs it: revisions can't desync the
    /// span anymore).
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
        // A fresh request starts with no audio: re-feed it the recent ring so
        // speech from before the restart is recognized too.
        for buffer in replay { req.append(buffer) }
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
    //   settledTokens  — raw tokens of COMPLETED recognition requests (append-only).
    //   frozenCount    — offset into (settledTokens + current utterance): everything
    //                    before it is frozen. The volatile span is simply everything
    //                    AFTER it — however the recognizer re-cases or re-punctuates
    //                    earlier words, the span only changes by its own content, so
    //                    the printed text can never be mass-erased by a revision.
    //                    (Revisions of already-frozen words are ignored — frozen is
    //                    frozen, TZ §16.)
    private var settledTokens: [String] = []
    private var lastUtteranceTokens: [String] = []
    private var frozenCount = 0
    /// True after a request restart: the new request re-hears the replayed tail
    /// of the session, so its transcript begins with an echo of already-settled
    /// words that must be stripped, not printed again.
    private var skipReplayEcho = false
    /// Frozen, corrected text — exactly what the field shows before the volatile
    /// tail (the typer renders `committedText + " " + volatile` as one string).
    private var committedText = ""
    private var volatileCorrected = ""         // corrected text currently shown as volatile

    private var freezeTimer: DispatchWorkItem?
    /// How long a speech pause freezes the volatile tail (TZ §6: pause → edit →
    /// continue must be safe; hand edits are never overwritten).
    private let freezeDelay: TimeInterval = 1.4

    // Trailing-word stability. Apple Speech revises its NEWEST word constantly
    // ("мир" → "мир," → another word entirely), and printing every revision made
    // the last word visibly appear/disappear in a loop. The trailing word is
    // therefore held back until one of: a newer word follows it, it stays
    // unchanged for `wordSettleDelay`, or the span freezes. In continuous
    // speech this costs about one word of latency; a pause releases it in
    /// ~0.45 s; freeze always releases everything.
    private var lastVolatileChangeAt = Date.distantPast
    private let wordSettleDelay: TimeInterval = 0.45
    private var settleTimer: DispatchWorkItem?

    /// Last time a recognition result arrived. The watchdog uses it: speech at
    /// the mic but no results for seconds means the request is stalled (a
    /// warm-up download, a request that died without an error callback).
    private var lastPartialAt = Date.distantPast
    private var watchdogTimer: DispatchWorkItem?

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
        // Forcing on-device whenever the locale *supports* it stalled the whole
        // first session: the model downloads on first use and the request stays
        // silent until it's ready — the user saw nothing until they stopped.
        // By default the engine choice is left to Apple (on-device once warm,
        // server otherwise — instant partials matter more); the settings toggle
        // pins it to on-device for privacy-minded users.
        let forceOnDevice = settings?.liveOnDeviceOnly == true

        let streamer = AppleSpeechStreamer(
            recognizer: recognizer,
            contextual: DictionaryContext.contextualStrings(personal: PersonalDictionaryStore.shared.entries),
            requiresOnDevice: forceOnDevice)
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
        frozenCount = 0
        skipReplayEcho = false
        committedText = ""
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
        lastPartialAt = Date()
        armWatchdog()
        phase = .listening
    }

    /// While the user is speaking but no results arrive for a few seconds,
    /// restart the request — the replay ring re-feeds the new one, so nothing
    /// already said is lost. This is what keeps "text while speaking" true even
    /// when a request stalls silently.
    private func armWatchdog() {
        watchdogTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .listening else { return }
            if MicLevel.shared.level > 0.04,
               Date().timeIntervalSince(self.lastPartialAt) > 4 {
                self.lastPartialAt = Date()
                self.streamer?.restartNow()
            }
            self.armWatchdog()
        }
        watchdogTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// New recognition result. The volatile span is everything the recognizer
    /// has said since the frozen boundary; it is corrected through the
    /// dictionaries and rendered with the trailing word held back.
    private func ingest(utterance: String, isFinal: Bool) {
        guard phase == .listening || phase == .finishing else { return }
        lastPartialAt = Date()
        let utteranceTok = Self.tokens(utterance)
        lastUtteranceTokens = utteranceTok

        // Span = utterance tokens after the frozen boundary. NB: deliberately NOT
        // "tokens the previous partial didn't contain" — the recognizer routinely
        // re-cases and re-punctuates earlier words ("как" → "Как,"), and diffing
        // against a normalized prefix made those revisions look like "nothing
        // new", wiping the whole span. A whole-span rebuild makes them plain
        // small string edits instead.
        let startInUtterance = max(0, frozenCount - settledTokens.count)
        var spanTokens = Array(utteranceTok.dropFirst(startInUtterance))
        // After a restart the new request re-hears the replayed tail of the
        // session: skip the tokens that merely re-transcribe already-settled
        // words, so the echo isn't printed twice. Case-insensitive, longest
        // common prefix against the settled tail — it stops by itself as soon
        // as genuinely new speech begins.
        if skipReplayEcho, !settledTokens.isEmpty, !spanTokens.isEmpty {
            let tail = settledTokens.suffix(60)
            var echo = 0
            while echo < tail.count, echo < spanTokens.count,
                  tail[tail.index(tail.startIndex, offsetBy: echo)].lowercased()
                    == spanTokens[echo].lowercased() {
                echo += 1
            }
            if echo > 0 { spanTokens.removeFirst(echo) }
            // The match chain broke before the settled tail ran out: speech has
            // moved past the echo — stop skipping on the following partials.
            if echo < tail.count { skipReplayEcho = false }
        }
        var corrected = TranscriptCorrector.correct(spanTokens.joined(separator: " "), rules: rules)
        // Spoken punctuation / new lines work in live dictation too ("точка",
        // "с новой строки") — span-safe, no re-casing, no trimming.
        if settings?.voiceCommandsEnabled != false {
            corrected = VoiceCommands.applyInline(to: corrected)
        }
        // Apple Speech (addsPunctuation) often capitalizes a sentence's first word
        // only after the partial was already printed — chasing that case change
        // would erase and retype the whole volatile span at every sentence start.
        // Keep the on-screen casing of the unchanged prefix instead.
        let previousFull = volatileCorrected
        volatileCorrected = Self.stabilizedPrefix(old: previousFull, new: corrected)
        if volatileCorrected != previousFull {
            lastVolatileChangeAt = Date()   // the trailing word is (again) unstable
        }
        if phase == .listening { scheduleFreeze() }
        renderVolatile()
    }

    /// Render the volatile span with the trailing word held back while it is
    /// still churning, and (re)schedule the release pass.
    private func renderVolatile() {
        let display = displayVolatile()
        typer.render(target: Self.join(committedText, display), frozen: committedText.count)
        scheduleSettleReleaseIfNeeded()
    }

    /// The full volatile target minus the trailing word, while that word is
    /// younger than `wordSettleDelay`. Keeps the trailing space so the held
    /// word simply appends when released; a lone unstable word is held entirely.
    private func displayVolatile() -> String {
        let full = volatileCorrected
        guard !full.isEmpty,
              Date().timeIntervalSince(lastVolatileChangeAt) < wordSettleDelay else { return full }
        guard let cut = full.lastIndex(of: " ") else { return "" }   // single word: hold it all
        return String(full[full.startIndex ... cut])
    }

    private func scheduleSettleReleaseIfNeeded() {
        settleTimer?.cancel()
        settleTimer = nil
        guard displayVolatile() != volatileCorrected else { return }
        let delay = max(0.05, wordSettleDelay - Date().timeIntervalSince(lastVolatileChangeAt))
        let work = DispatchWorkItem { [weak self] in self?.renderVolatile() }
        settleTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
    /// begins: settle its final transcript into history and freeze the volatile
    /// tail. The fresh request is fed the recent audio (replay ring), so its
    /// transcript will start with an echo — `skipReplayEcho` strips it.
    private func handleRestart() {
        freezeCurrentVolatile()
        settledTokens += lastUtteranceTokens
        lastUtteranceTokens = []
        skipReplayEcho = true
    }

    private func scheduleFreeze() {
        freezeTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.freezeCurrentVolatile() }
        freezeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + freezeDelay, execute: work)
    }

    /// Freeze the volatile tail: it becomes ordinary text from the user's point
    /// of view — BabelBar will never revise it again. Held-back words are
    /// released (typed) here: the typer's single-string diff sees them as a
    /// plain append of the target.
    private func freezeCurrentVolatile() {
        freezeTimer?.cancel(); freezeTimer = nil
        settleTimer?.cancel(); settleTimer = nil
        frozenCount = settledTokens.count + lastUtteranceTokens.count
        skipReplayEcho = false
        let span = volatileCorrected
        volatileCorrected = ""
        lastVolatileChangeAt = Date.distantPast
        guard !span.isEmpty else { return }
        committedText = Self.join(committedText, span)
        if settings?.frequencyLearningEnabled == true {
            let personalTerms = PersonalDictionaryStore.shared.entries.filter(\.enabled).map(\.written)
            FrequencyTracker.recordHits(in: span, personalTerms: personalTerms)   // TZ §12
        }
        typer.render(target: committedText, frozen: committedText.count)
    }

    private func handleAppSwitch() {
        guard phase == .listening || phase == .finishing else { return }
        typer.freezeAll()            // stop revising the old field immediately
        freezeCurrentVolatile()
        sessionApp = ""              // the end-of-session AX read would hit the wrong field
    }

    private func conclude() {
        guard phase == .finishing else { return }
        phase = .idle
        freezeTimer?.cancel(); freezeTimer = nil
        freezeCurrentVolatile()
        teardown()

        // Learning: snapshot the field we typed into — but only if the user
        // stayed in the same app for the whole session (TZ §11, §14).
        let typed = committedText
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
        watchdogTimer?.cancel(); watchdogTimer = nil
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

    // MARK: - Token helpers

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Join two printed fragments with a space — unless the left one ends with
    /// a line break the user asked for ("с новой строки").
    private static func join(_ a: String, _ b: String) -> String {
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty ? b : a }
        return a.hasSuffix("\n") ? a + b : a + " " + b
    }

    private static func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}
