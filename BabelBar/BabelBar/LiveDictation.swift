import Foundation
import Speech
import AVFoundation
import AppKit

/// One Apple Speech request per utterance. All request state and audio appends run
/// on `queue`; the audio tap only copies its buffer and enqueues it. UI callbacks
/// are delivered on main in the same order as recognition events.
final class AppleSpeechStreamer {
    /// The current segment's live (not yet final) guess. May be called repeatedly
    /// with a revised text for the same segment; never called after that segment's
    /// `onSegmentFinal`.
    var onPartial: ((String) -> Void)?
    /// A segment has finalized (silence, forced cutoff, or a recognizer error) and
    /// its text is now permanent. May be called with an empty string.
    var onSegmentFinal: ((String) -> Void)?
    /// Recognition failed repeatedly or incoming audio could not be buffered.
    var onFailure: (() -> Void)?

    private let queue = DispatchQueue(label: "com.babelbar.speech-stream", qos: .userInitiated)
    private let recognizer: SFSpeechRecognizer
    private let contextual: [String]
    private let requiresOnDevice: Bool
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var wantsAudio = false
    private var stopping = false
    private var awaitingFinal = false
    private var onFlushed: (() -> Void)?
    private var generation = 0
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var pendingSeconds: TimeInterval = 0
    private var lastPartialText = ""
    private var recentErrors: [Date] = []

    // Voice activity detection, driven by every incoming buffer.
    private var voiceSeenInSegment = false
    private var silentSeconds: TimeInterval = 0
    private var segmentSeconds: TimeInterval = 0
    private static let silenceRMS: Float = 0.004
    private static let silenceHang: TimeInterval = 0.8
    private static let maxSegmentDuration: TimeInterval = 45
    private static let localFinalizeTimeout: TimeInterval = 2.5
    private static let remoteFinalizeTimeout: TimeInterval = 5
    private static let maxPendingSeconds: TimeInterval = 8

    init(recognizer: SFSpeechRecognizer, contextual: [String], requiresOnDevice: Bool) {
        self.recognizer = recognizer; self.contextual = contextual; self.requiresOnDevice = requiresOnDevice
    }

    func start() {
        queue.async {
            self.wantsAudio = true
            self.beginRequest()
        }
    }

    func append(buffer: AVAudioPCMBuffer) {
        // AVAudioEngine reuses tap buffers. Retain an independent copy before the
        // callback returns; no mutable streamer state is touched on the audio thread.
        guard let copy = Self.copy(buffer) else { return }
        queue.async { self.appendQueued(copy) }
    }

    private func appendQueued(_ buffer: AVAudioPCMBuffer) {
        guard wantsAudio else { return }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        if awaitingFinal {
            // Audio arriving during finalization belongs to the next request.
            pendingBuffers.append(buffer)
            pendingSeconds += duration
            if pendingSeconds > Self.maxPendingSeconds {
                fail("pending audio exceeded \(Self.maxPendingSeconds) seconds")
            }
            return
        }
        request?.append(buffer)
        segmentSeconds += duration
        if Self.rms(of: buffer) > Self.silenceRMS {
            voiceSeenInSegment = true; silentSeconds = 0
        } else {
            silentSeconds += duration
        }
        if voiceSeenInSegment, silentSeconds >= Self.silenceHang { endSegment() }
        else if segmentSeconds >= Self.maxSegmentDuration { endSegment() }
    }

    func cancel() {
        queue.async { self.cancelQueued() }
    }

    private func cancelQueued() {
        let audioAlreadyEnded = awaitingFinal
        wantsAudio = false; stopping = false; awaitingFinal = false; onFlushed = nil
        generation += 1
        if !audioAlreadyEnded { request?.endAudio() }
        request = nil
        task?.cancel(); task = nil
        pendingBuffers = []; pendingSeconds = 0; lastPartialText = ""
        recentErrors = []
    }

    /// Ends the in-flight segment, waits for it to finalize (falling back to its
    /// last known partial if the recognizer doesn't), reports it once more via
    /// `onSegmentFinal`, then calls `completion`. Does not open a new segment.
    func flush(_ completion: @escaping () -> Void) {
        queue.async {
            guard self.wantsAudio, !self.stopping else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            self.stopping = true; self.onFlushed = completion
            // Frames queued while the previous request was finalizing are part of
            // this stop, so feed them to one last request before closing it.
            if self.awaitingFinal { return }
            self.endSegment()
        }
    }

    /// A stuck recognizer is closed before another task opens. Its latest partial
    /// is committed once, so restarting does not silently discard known words.
    func forceRestart() {
        queue.async {
            guard self.wantsAudio, !self.stopping, !self.awaitingFinal else { return }
            NSLog("BabelBar live-dictation: restarting stalled recognizer")
            self.finishSegment(self.lastPartialText)
        }
    }

    private func endSegment() {
        guard wantsAudio, !awaitingFinal else { return }
        awaitingFinal = true; voiceSeenInSegment = false; silentSeconds = 0; segmentSeconds = 0
        request?.endAudio()
        let gen = generation
        let timeout = requiresOnDevice ? Self.localFinalizeTimeout : Self.remoteFinalizeTimeout
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.awaitingFinal, self.generation == gen else { return }
            NSLog("BabelBar live-dictation: final result timed out; using latest partial")
            self.finishSegment(self.lastPartialText)
        }
    }

    private func finishSegment(_ text: String) {
        guard wantsAudio else { return }
        let audioAlreadyEnded = awaitingFinal
        awaitingFinal = false
        lastPartialText = ""
        // Invalidate callbacks before canceling the previous task. Even a normal
        // isFinal can arrive without our silence detector first calling endAudio.
        generation += 1
        if !audioAlreadyEnded { request?.endAudio() }
        request = nil
        task?.cancel(); task = nil
        DispatchQueue.main.async { [weak self] in self?.onSegmentFinal?(text) }
        if stopping {
            if !pendingBuffers.isEmpty {
                beginRequest()
                endSegment()
                return
            }
            wantsAudio = false
            let done = onFlushed; onFlushed = nil
            if let done { DispatchQueue.main.async(execute: done) }
            return
        }
        beginRequest()
    }

    private func beginRequest() {
        generation += 1
        let gen = generation
        voiceSeenInSegment = false; silentSeconds = 0; segmentSeconds = 0
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true; next.addsPunctuation = true
        next.contextualStrings = contextual; next.requiresOnDeviceRecognition = requiresOnDevice
        let queued = pendingBuffers; pendingBuffers = []; pendingSeconds = 0
        for buffer in queued { next.append(buffer) }
        request = next
        task = recognizer.recognitionTask(with: next) { [weak self] result, error in
            self?.queue.async { [weak self] in
                guard let self, self.wantsAudio, self.generation == gen else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty { self.recentErrors.removeAll() }
                    if result.isFinal {
                        self.finishSegment(text)
                    } else {
                        self.lastPartialText = text
                        if !text.isEmpty { self.voiceSeenInSegment = true }
                        DispatchQueue.main.async { [weak self] in self?.onPartial?(text) }
                    }
                    return
                }
                guard let error else { return }
                let nsError = error as NSError
                NSLog("BabelBar live-dictation: recognizer error %@/%ld", nsError.domain, nsError.code)
                // Apple's 1110 means that this request contained no recognizable
                // speech. A quiet segment is normal during a long dictation and
                // must not count toward the failure threshold for the session.
                if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                    self.finishSegment(self.lastPartialText)
                    return
                }
                let now = Date()
                self.recentErrors.removeAll { now.timeIntervalSince($0) > 30 }
                self.recentErrors.append(now)
                if self.recentErrors.count >= 3, !self.stopping {
                    self.fail("recognizer failed three times within 30 seconds")
                } else {
                    self.finishSegment(self.lastPartialText)
                }
            }
        }
    }

    private func fail(_ reason: String) {
        NSLog("BabelBar live-dictation: %@", reason)
        cancelQueued()
        DispatchQueue.main.async { [weak self] in self?.onFailure?() }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in source.indices {
            guard let src = source[i].mData, let dst = destination[i].mData else { return nil }
            memcpy(dst, src, Int(source[i].mDataByteSize))
        }
        return copy
    }

    /// Plain RMS (not the perceptual curve `AudioRecorder.micLevel` uses for the
    /// waveform) — a linear threshold is what a silence gate wants.
    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        let samples = channels[0]
        var sum: Float = 0
        for i in 0..<n { let s = samples[i]; sum += s * s }
        return (sum / Float(n)).squareRoot()
    }
}

/// WhisperKit live mode. Audio is captured once by `AudioRecorder`, converted to
/// Whisper's 16 kHz mono format, and decoded locally in short utterance segments.
/// While a segment is still open, newer snapshots revise the interim text; silence
/// or the user's stop finalizes it once. Decoding is serialized to avoid overlapping
/// CoreML work and losing the tail of a sentence.
/// Mutable state is confined to `queue`; `transcriber` is an actor. Async decode
/// completions hop back to that queue before reading or changing any fields.
final class WhisperKitLiveStreamer: @unchecked Sendable {
    var onPartial: ((String) -> Void)?
    var onSegmentFinal: ((String) -> Void)?
    var onFailure: (() -> Void)?

    private let queue = DispatchQueue(label: "com.babelbar.whisper-live", qos: .userInitiated)
    private let transcriber: LocalWhisperTranscriber
    private let language: Lang?
    private var wantsAudio = false
    private var loaded = false
    private var loading = false
    private var stopping = false
    private var finalizing = false
    private var decoding = false
    private var generation = 0
    private var current: [Float] = []
    private var pending: [[Float]] = []
    private var pendingSamples = 0
    private var lastDecodedCount = 0
    private var lastVoicedCount = 0
    private var voiceSeen = false
    private var candidateVoicedSamples = 0
    private var silentSamples = 0
    private var onFlushed: (() -> Void)?
    private var latestText = ""
    private var recentFailures: [Date] = []

    private let sampleRate = 16_000
    private let voiceRMS: Float = 0.004
    private let minVoiceDuration = 0.16
    private let partialInterval = 1.2
    private let silenceHang = 0.7
    private let shortPause = 0.22
    private let softSegmentDuration = 4.0
    private let maxSegmentDuration = 7.0
    private let maxPendingDuration = 120.0

    init(transcriber: LocalWhisperTranscriber, language: Lang?) {
        self.transcriber = transcriber
        self.language = language
    }

    func start() {
        queue.async {
            self.wantsAudio = true
            guard !self.loading, !self.loaded else { self.pump(); return }
            self.loading = true
            Task {
                do {
                    try await self.transcriber.preload()
                    self.queue.async {
                        guard self.wantsAudio else { return }
                        self.loading = false; self.loaded = true
                        NSLog("BabelBar live-whisperkit: model ready")
                        self.pump()
                    }
                } catch {
                    self.queue.async {
                        guard self.wantsAudio else { return }
                        self.loading = false
                        self.fail("WhisperKit model could not be loaded: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func append(samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.async { self.ingest(samples) }
    }

    private func ingest(_ samples: [Float]) {
        guard wantsAudio else { return }
        if finalizing {
            pending.append(samples); pendingSamples += samples.count
            if Double(pendingSamples) / Double(sampleRate) > maxPendingDuration {
                fail("WhisperKit could not keep up with incoming audio")
            }
            return
        }

        let rms = Self.rms(samples)
        if !voiceSeen {
            // Require more than one loud microphone buffer before treating a
            // click or background transient as speech. Preserve its onset.
            current.append(contentsOf: samples)
            let preRoll = Int(0.45 * Double(sampleRate))
            if current.count > preRoll { current.removeFirst(current.count - preRoll) }
            if rms > voiceRMS { candidateVoicedSamples += samples.count }
            else { candidateVoicedSamples = max(0, candidateVoicedSamples - samples.count / 2) }
            guard candidateVoicedSamples >= Int(minVoiceDuration * Double(sampleRate)) else { return }
            voiceSeen = true
            lastVoicedCount = current.count
            silentSamples = 0
        } else {
            current.append(contentsOf: samples)
            if rms > voiceRMS { silentSamples = 0; lastVoicedCount = current.count }
            else { silentSamples += samples.count }
        }

        let duration = Double(current.count) / Double(sampleRate)
        let pause = Double(silentSamples) / Double(sampleRate)
        if voiceSeen, pause >= silenceHang || (duration >= softSegmentDuration && pause >= shortPause) {
            finalizing = true
        } else if duration >= maxSegmentDuration {
            finalizing = true
        }
        pump()
    }

    func flush(_ completion: @escaping () -> Void) {
        queue.async {
            guard self.wantsAudio else { DispatchQueue.main.async(execute: completion); return }
            self.stopping = true; self.onFlushed = completion
            self.finalizing = true
            self.pump()
        }
    }

    func forceRestart() {
        queue.async {
            guard self.wantsAudio, !self.stopping, !self.current.isEmpty else { return }
            NSLog("BabelBar live-whisperkit: finalizing stalled segment")
            self.finalizing = true
            self.pump()
        }
    }

    func cancel() {
        queue.async {
            self.generation += 1
            self.wantsAudio = false; self.stopping = false; self.finalizing = false
            self.current.removeAll(); self.pending.removeAll(); self.pendingSamples = 0
            self.latestText = ""; self.onFlushed = nil
        }
    }

    private func pump() {
        guard wantsAudio, loaded, !loading, !decoding else { return }
        guard !current.isEmpty else {
            if stopping { finishFlush() }
            else { beginNextPending() }
            return
        }
        let isFinal = finalizing || stopping
        if isFinal, (!voiceSeen || AudioRecorder.isSilent(current)) {
            emitFinal("")
            return
        }
        if !isFinal, !voiceSeen { return }
        // The last partial already covered every voiced sample. A trailing pause
        // cannot add words; avoid a second full decode just to finalize it.
        if isFinal, lastDecodedCount > 0, lastDecodedCount >= lastVoicedCount {
            emitFinal(latestText)
            return
        }
        if !isFinal, current.count - lastDecodedCount < Int(partialInterval * Double(sampleRate)) { return }
        decode(Array(current), final: isFinal)
    }

    private func decode(_ samples: [Float], final: Bool) {
        decoding = true
        let id = generation
        lastDecodedCount = current.count
        let started = Date()
        Task {
            do {
                let text = try await transcriber.transcribeLive(samples: samples, language: language)
                queue.async {
                    guard self.wantsAudio, self.generation == id else { return }
                    NSLog("BabelBar live-whisperkit: decode %.2fs for %.2fs audio (%@, %ld chars)",
                          Date().timeIntervalSince(started), Double(samples.count) / Double(self.sampleRate),
                          final ? "final" : "partial", text.count)
                    self.decoding = false
                    self.latestText = text
                    self.recentFailures.removeAll()
                    if final {
                        self.emitFinal(text)
                    } else {
                        DispatchQueue.main.async { [weak self] in self?.onPartial?(text) }
                        self.pump()
                    }
                }
            } catch {
                queue.async {
                    guard self.wantsAudio, self.generation == id else { return }
                    self.decoding = false
                    NSLog("BabelBar live-whisperkit: decode error: %@", error.localizedDescription)
                    let now = Date()
                    self.recentFailures.removeAll { now.timeIntervalSince($0) > 30 }
                    self.recentFailures.append(now)
                    if final, !self.latestText.isEmpty {
                        self.emitFinal(self.latestText)
                    } else if self.recentFailures.count >= 3 {
                        self.fail("WhisperKit failed three times within 30 seconds")
                    } else {
                        self.pump()
                    }
                }
            }
        }
    }

    private func emitFinal(_ text: String) {
        NSLog("BabelBar live-whisperkit: segment finalized (%ld characters)", text.count)
        generation += 1
        decoding = false; finalizing = false
        current.removeAll(keepingCapacity: true); lastDecodedCount = 0; lastVoicedCount = 0
        voiceSeen = false; candidateVoicedSamples = 0; silentSamples = 0; latestText = ""
        DispatchQueue.main.async { [weak self] in self?.onSegmentFinal?(text) }
        beginNextPending()
        if current.isEmpty, pending.isEmpty, stopping { finishFlush() }
        else { pump() }
    }

    private func beginNextPending() {
        guard !pending.isEmpty else { return }
        let chunks = pending; pending.removeAll(keepingCapacity: true); pendingSamples = 0
        current.removeAll(keepingCapacity: true); lastDecodedCount = 0; lastVoicedCount = 0; finalizing = false
        voiceSeen = false; candidateVoicedSamples = 0; silentSamples = 0; latestText = ""
        for chunk in chunks { ingest(chunk) }
    }

    private func finishFlush() {
        guard stopping else { return }
        wantsAudio = false; stopping = false; finalizing = false
        let done = onFlushed; onFlushed = nil
        if let done { DispatchQueue.main.async(execute: done) }
    }

    private func fail(_ reason: String) {
        NSLog("BabelBar live-whisperkit: %@", reason)
        generation += 1; wantsAudio = false; decoding = false; loading = false
        current.removeAll(); pending.removeAll(); pendingSamples = 0
        let callback = onFailure
        DispatchQueue.main.async { callback?() }
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}

/// How a finalized segment joins onto what's already committed — no space is
/// inserted around a line break a voice command just produced.
enum LiveJoin {
    static func join(_ a: String, _ b: String) -> String {
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty ? b : a }
        if a.last?.isWhitespace == true || b.first?.isWhitespace == true { return a + b }
        return a + " " + b
    }

    /// Add one space after punctuation inside a recognized fragment and, for a
    /// finalized fragment, also at its end. Keep decimal numbers and common
    /// domains/file extensions intact. Existing whitespace is never doubled.
    static func spaceAfterPunctuation(_ text: String, atEnd: Bool = false) -> String {
        let characters = Array(text)
        let marks: Set<Character> = [".", ",", ";", ":", "!", "?", "…", "—", "–"]
        let noSpaceBefore: Set<Character> = [".", ",", ";", ":", "!", "?", "…", ")", "]", "}", "»", "\""]
        let compactSuffixes: Set<String> = ["com", "net", "org", "ru", "io", "app", "dev", "js", "ts", "py", "swift"]
        var output = ""
        for index in characters.indices {
            let mark = characters[index]
            output.append(mark)
            guard marks.contains(mark) else { continue }
            let nextIndex = index + 1
            guard nextIndex < characters.count else {
                if atEnd { output.append(" ") }
                continue
            }
            let next = characters[nextIndex]
            guard !next.isWhitespace, !noSpaceBefore.contains(next), next.isLetter || next.isNumber else { continue }
            if (mark == "." || mark == ","), index > 0,
               characters[index - 1].isNumber, next.isNumber { continue }
            if mark == ".", next.isLetter {
                let suffix = String(characters[nextIndex...].prefix(while: { $0.isLetter })).lowercased()
                if compactSuffixes.contains(suffix) { continue }
            }
            output.append(" ")
        }
        return output
    }
}

/// Whisper's stock answers to silence and microphone noise. Match only a whole
/// short transcript so a real sentence containing these words is not removed.
enum WhisperTranscriptFilter {
    private static let fillerPhrases: Set<String> = [
        "thanks for watching", "thank you for watching", "please subscribe",
        "subscribe to my channel", "продолжение следует",
        "субтитры сделал dimatorzok", "субтитры создавал dimatorzok",
        "редактор субтитров а.синецкая корректор а.егорова", "спасибо за просмотр",
    ]

    static func isFiller(_ text: String) -> Bool {
        let stripped = text.lowercased().trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?…")))
        let key = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return key.isEmpty || fillerPhrases.contains(key)
    }
}

/// WhisperKit can revise its latest hypothesis. Paste complete words from each
/// hypothesis immediately, keeping the last word provisional.
/// This gives other applications append-only updates without needing their AX
/// text value or deleting text around the caret.
struct WhisperLiveCommitter {
    private(set) var committed = ""
    private var emitted = ""

    mutating func partial(_ text: String) -> String {
        guard let boundary = text.lastIndex(where: { $0.isWhitespace }) else { return "" }
        let stable = String(text[...boundary])
        guard stable.hasPrefix(emitted), stable.count > emitted.count else { return "" }
        let delta = emitted.isEmpty
            ? String(LiveJoin.join(committed, stable).dropFirst(committed.count))
            : String(stable.dropFirst(emitted.count))
        emitted = stable
        return delta
    }

    /// Returns the remaining paste fragment and the segment actually written.
    /// If the model changes an already pasted word, keep the visible word and
    /// append only words that follow it; silently rewriting another app's text
    /// would require dependable AX access, which many editors do not provide.
    mutating func finalize(_ final: String) -> (delta: String, segment: String) {
        let segment: String
        if emitted.isEmpty || final.hasPrefix(emitted) {
            segment = final.isEmpty ? emitted : final
        } else {
            let emittedWords = emitted.split(whereSeparator: \.isWhitespace).count
            let finalWords = final.split(whereSeparator: \.isWhitespace)
            if finalWords.count > emittedWords {
                let tail = finalWords.dropFirst(emittedWords).joined(separator: " ")
                segment = emitted + (emitted.last?.isWhitespace == true ? "" : " ") + tail
            } else if final.count > emitted.count, finalWords.count <= 1 {
                segment = emitted + String(final.dropFirst(emitted.count))
            } else {
                segment = emitted
            }
        }
        let delta = emitted.isEmpty
            ? String(LiveJoin.join(committed, segment).dropFirst(committed.count))
            : String(segment.dropFirst(emitted.count))
        committed = LiveJoin.join(committed, segment)
        emitted = ""
        return (delta, segment)
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
    private var whisperStreamer: WhisperKitLiveStreamer?
    private let typer = LiveTyper.shared
    private let inputGuard = LiveInputGuard()
    private var settings: AppSettings?
    private var localTranscriber: LocalWhisperTranscriber?
    private var rules: [DictEntry] = []
    /// Everything already written to the field — permanent, never revised.
    private var committedText = ""
    /// The current segment's live guess — freely rewritten until it finalizes.
    private var interimText = ""
    private var whisperCommitter = WhisperLiveCommitter()
    private var livePaste: LivePasteSession?
    private var target: AXLiveTextTarget?
    private var destinationPID: pid_t?
    private var watchdog: Timer?
    private var appObserver: Any?
    private var lastActivity = Date()
    private var startRequestedAt: TimeInterval?
    private var microphoneStartedAt: TimeInterval?
    private var loggedFirstPartial = false
    private var targetAcquisitionInFlight = false
    private var session = UUID()
    private var finishingTask: Task<Void, Never>?
    private var reportError: ((LKey) -> Void)?

    func prepareMicrophone() { recorder.prepare() }
    func releasePreparedMicrophone() { recorder.releasePrepared() }

    func start(settings: AppSettings, localTranscriber: LocalWhisperTranscriber? = nil,
               onError: @escaping (LKey) -> Void) {
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
        startRequestedAt = ProcessInfo.processInfo.systemUptime
        targetAcquisitionInFlight = false
        phase = .starting; session = UUID()
        let id = session
        self.settings = settings; self.localTranscriber = localTranscriber; reportError = onError
        rules = PersonalDictionaryStore.shared.activeRules(developerEnabled: settings.developerDictionaryEnabled)
        if settings.dictationMode == .liveWhisperKit {
            guard WhisperModelManager.isVariantOnDisk(settings.whisperModel.variant) else {
                abort(error: .errWhisperModelMissing); return
            }
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                abort(error: .errVoiceFocus); return
            }
        }
        requestMic { [weak self] ok in
            guard let self, self.session == id, self.phase == .starting else { return }
            guard ok else { self.abort(error: .errMicSpeech); return }
            if settings.dictationMode == .liveWhisperKit {
                self.beginSession(target: nil)
                return
            }
            if SFSpeechRecognizer.authorizationStatus() == .authorized {
                self.startAppleSpeechWithDeferredTarget(session: id)
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    guard self.session == id, self.phase == .starting else { return }
                    guard status == .authorized else { self.abort(error: .errSpeechDenied); return }
                    self.startAppleSpeechWithDeferredTarget(session: id)
                }
            }
        }
    }

    /// Start capture before asking the frontmost app for its accessibility tree.
    /// Chromium/Electron can take several 80 ms polling rounds to expose the focused
    /// field; that work must not delay the microphone or the recording indicator.
    private func startAppleSpeechWithDeferredTarget(session id: UUID) {
        guard session == id, phase == .starting else { return }
        beginSession(target: nil)
    }

    func stop() {
        guard phase == .listening else {
            if phase == .starting { abort() }
            return
        }
        // Stop capturing new audio immediately; the segment already in flight is
        // still finalized from what it has, with the same field/caret checks.
        phase = .finishing
        if settings?.dictationMode == .liveWhisperKit { RecordingOverlay.shared.setProcessing(true) }
        let id = session
        let flushed: () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.session == id, self.phase == .finishing else { return }
                self.finishStopping(id: id)
            }
        }
        recorder.stop { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session == id, self.phase == .finishing else { return }
                if self.settings?.dictationMode == .liveWhisperKit { self.whisperStreamer?.flush(flushed) }
                else { self.streamer?.flush(flushed) }
            }
        }
    }

    /// Electron and Chromium editors publish their accessibility tree only after a
    /// client asks for it, and the tree needs a moment to appear. Ask once, then
    /// poll briefly instead of failing on the first empty answer.
    private func acquireTarget(session id: UUID, attempt: Int = 0) {
        guard session == id, phase == .starting || phase == .listening, !targetAcquisitionInFlight,
              let pid = destinationPID else { return }
        targetAcquisitionInFlight = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let probe = AXLiveTextTarget.probe(expectedPID: pid)
            if probe == nil, attempt == 0 {
                AXLiveTextTarget.requestAccessibilityTree(pid: pid)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.session == id else { return }
                self.targetAcquisitionInFlight = false
                guard self.phase == .starting || self.phase == .listening else { return }
                let target = probe.map(AXLiveTextTarget.init(probe:))
                if let target {
                    self.attachTarget(target, session: id)
                    return
                }
                guard attempt < 10, AXIsProcessTrusted() else {
                    NSLog("BabelBar live-dictation: acquireTarget gave up after %d attempts (%@ %@)", attempt,
                          NSWorkspace.shared.frontmostApplication?.localizedName ?? "?",
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")
                    self.abort(error: .errLiveField); return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.acquireTarget(session: id, attempt: attempt + 1)
                }
            }
        }
    }

    /// Bind live text insertion once accessibility is ready. Audio and recognition
    /// have already started, so any partial received while the target was loading is
    /// rendered as soon as the verified field is attached.
    private func attachTarget(_ target: AXLiveTextTarget, session id: UUID) {
        guard session == id, phase == .starting || phase == .listening, let settings else { return }
        guard destinationPID == target.pid else {
            abort(error: .errVoiceFocus)
            return
        }
        guard typer.begin(target: target) else {
            abort(error: .errLiveField)
            return
        }
        self.target = target
        if let startRequestedAt {
            NSLog("BabelBar live-dictation: text field ready after %.0f ms",
                  (ProcessInfo.processInfo.systemUptime - startRequestedAt) * 1000)
        }
        if settings.learnFromCorrections {
            CorrectionObserver.checkPreviousSessionCorrection(target: target)
        } else {
            CorrectionObserver.forget()
        }
        render()
    }

    private func beginSession(target: AXLiveTextTarget?) {
        guard let settings else { abort(); return }
        if settings.dictationMode == .liveWhisperKit,
           !WhisperModelManager.isVariantOnDisk(settings.whisperModel.variant) {
            abort(error: .errWhisperModelMissing); return
        }
        self.target = target
        destinationPID = target?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let target {
            if settings.learnFromCorrections { CorrectionObserver.checkPreviousSessionCorrection(target: target) }
            else { CorrectionObserver.forget() }
        } else if settings.dictationMode == .liveWhisperKit {
            CorrectionObserver.forget()
        }
        let id = session
        let partial: (String) -> Void = { [weak self] text in
            guard let self, self.session == id, self.phase == .listening else { return }
            self.lastActivity = Date()
            if !self.loggedFirstPartial, let startedAt = self.microphoneStartedAt {
                self.loggedFirstPartial = true
                NSLog("BabelBar live-dictation: first partial after %.0f ms",
                      (ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
            }
            self.interimText = self.correctedText(text, followsText: !self.committedText.isEmpty)
            if settings.dictationMode == .liveWhisperKit {
                self.livePaste?.append(self.whisperCommitter.partial(self.interimText))
            } else { self.render() }
        }
        let finalized: (String) -> Void = { [weak self] text in
            guard let self, self.session == id, self.phase == .listening || self.phase == .finishing else { return }
            self.lastActivity = Date()
            let corrected = self.correctedText(text, followsText: !self.committedText.isEmpty, final: true)
            if settings.dictationMode == .liveWhisperKit {
                let result = self.whisperCommitter.finalize(corrected)
                self.livePaste?.append(result.delta)
                self.commit(result.segment)
            } else { self.commit(corrected) }
        }
        let failure: () -> Void = { [weak self] in
            guard let self, self.session == id else { return }
            self.abort(error: .errDictation)
        }
        committedText = ""; interimText = ""; whisperCommitter = WhisperLiveCommitter()
        if target != nil || settings.dictationMode == .live {
            typer.onInvalidated = { [weak self] in self?.abort(error: .errLiveInsert) }
            inputGuard.start { [weak self] in
                NSLog("BabelBar live-dictation: physical key or click interrupted dictation")
                self?.abort()
            }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                guard let self, app?.processIdentifier != self.destinationPID else { return }
                NSLog("BabelBar live-dictation: app changed (%@ %@)",
                      app?.localizedName ?? "?", app?.bundleIdentifier ?? "?")
                self.abort()
            }
        }
        if settings.dictationMode == .liveWhisperKit {
            let language: Lang? = settings.liveDictationLanguage == .auto ? nil
                : settings.liveDictationLanguage == .ru ? .ru : .en
            guard let transcriber = localTranscriber else { abort(error: .errDictation); return }
            guard let destinationPID else { abort(error: .errVoiceFocus); return }
            let paste = LivePasteSession(destinationPID: destinationPID)
            paste.onInvalidated = { [weak self] in self?.abort(error: .errLiveInsert) }
            livePaste = paste
            let live = WhisperKitLiveStreamer(transcriber: transcriber, language: language)
            live.onPartial = partial; live.onSegmentFinal = finalized; live.onFailure = failure
            whisperStreamer = live
            recorder.onSamples = { [weak live] in live?.append(samples: $0) }
            // WhisperKit needs the complete recording buffer for each hypothesis.
            recorder.accumulateSamples = false
            live.start()
        } else {
            guard let recognizer = SFSpeechRecognizer(locale: settings.liveDictationLanguage.locale), recognizer.isAvailable else {
                abort(error: .errSpeechUnavailable); return
            }
            let onDevice = recognizer.supportsOnDeviceRecognition
            if settings.liveOnDeviceOnly, !onDevice { abort(error: .errSpeechOnDevice); return }
            let live = AppleSpeechStreamer(recognizer: recognizer,
                contextual: DictionaryContext.contextualStrings(personal: PersonalDictionaryStore.shared.entries,
                             developerEnabled: settings.developerDictionaryEnabled, frequencyEnabled: settings.frequencyLearningEnabled),
                requiresOnDevice: onDevice)
            live.onPartial = partial; live.onSegmentFinal = finalized; live.onFailure = failure
            streamer = live
            recorder.onBuffer = { [weak live] in live?.append(buffer: $0) }
            recorder.accumulateSamples = false
            live.start()
        }
        recorder.start { [weak self] result in
            Task { @MainActor in
                guard let self, self.session == id, self.phase == .starting else { return }
                switch result {
                case .success: self.microphoneDidStart(session: id)
                case .failure: self.abort(error: .errDictation)
                }
            }
        }
        if settings.dictationMode == .live { acquireTarget(session: id) }
    }

    private func microphoneDidStart(session id: UUID) {
        guard session == id, phase == .starting, let settings else { return }
        phase = .listening; lastActivity = Date()
        if let startRequestedAt {
            NSLog("BabelBar live-dictation: microphone started after %.0f ms",
                  (ProcessInfo.processInfo.systemUptime - startRequestedAt) * 1000)
        }
        microphoneStartedAt = ProcessInfo.processInfo.systemUptime
        loggedFirstPartial = false
        if settings.dictationMode == .liveWhisperKit {
            NSLog("BabelBar live-whisperkit: microphone started for pid %d", destinationPID ?? 0)
        }
        MicLevel.shared.showDot = settings.showRecordingDot
        RecordingOverlay.shared.show()
        // CoreAudio property calls are synchronous and can stall while the output
        // device is waking. Start capture and show the recording state first.
        if settings.duckAudio { SystemAudio.duck() }
        if settings.voiceSoundEnabled { SystemSounds.play(settings.voiceSoundName, volume: Float(settings.voiceSoundVolume)) }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .listening else { return }
                // Mic is active (someone is speaking) but neither a partial nor a
                // finalized segment has arrived in a long time: the recognizer is
                // stuck. Drop the in-flight segment and start clean rather than
                // hang the session forever.
                if self.settings?.dictationMode != .liveWhisperKit,
                   MicLevel.shared.level > 0.04, Date().timeIntervalSince(self.lastActivity) > 6 {
                    self.lastActivity = Date()
                    self.streamer?.forceRestart()
                }
            }
        }
    }

    private func correctedText(_ raw: String, followsText: Bool, final: Bool = false) -> String {
        // WhisperKit sometimes uses repeated dots to mark an unfinished
        // hypothesis. Treat them as one period; an explicitly spoken
        // "многоточие" is applied afterwards by VoiceCommands and survives.
        let cleaned = settings?.dictationMode == .liveWhisperKit
            ? raw.replacingOccurrences(of: #"\.{2,}|…"#, with: ".", options: .regularExpression)
            : raw
        let result = TranscriptCorrector.correct(cleaned, rules: rules)
        let spoken = settings?.voiceCommandsEnabled == true
            ? VoiceCommands.applyInline(to: result, followsText: followsText) : result
        return LiveJoin.spaceAfterPunctuation(spoken, atEnd: final)
    }

    private func render() {
        guard target != nil else { return }
        typer.render(target: LiveJoin.join(committedText, interimText), frozen: committedText.count)
    }

    /// A segment finalized: fold it into the permanent text. Never touched again.
    private func commit(_ final: String) {
        interimText = ""
        guard !final.isEmpty else { return }
        committedText = LiveJoin.join(committedText, final)
        if target != nil { typer.render(target: committedText, frozen: committedText.count) }
        if target != nil, settings?.frequencyLearningEnabled == true {
            let personal = PersonalDictionaryStore.shared.entries.filter(\.enabled).map(\.written)
            let id = session, committed = committedText
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.typer.flush()
                guard self.session == id, self.typer.screen.hasPrefix(committed) else { return }
                FrequencyTracker.recordHits(in: final, personalTerms: personal)
            }
        }
    }

    private func finishStopping(id: UUID) {
        finishingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.target != nil { await self.typer.flush() }
            guard !Task.isCancelled, self.session == id, self.phase == .finishing else { return }
            if self.settings?.dictationMode == .liveWhisperKit {
                await self.livePaste?.flush()
                guard !Task.isCancelled, self.session == id, self.phase == .finishing else { return }
                let text = self.committedText
                let duration = self.recorder.lastWallDuration
                let callback = self.reportError
                self.teardown(); self.phase = .idle
                if text.isEmpty, duration >= 0.8 { callback?(.errSilence) }
                return
            }
            if self.settings?.learnFromCorrections == true, let target = self.target, self.typer.isCurrent() {
                CorrectionObserver.noteSessionEnded(typed: self.typer.screen, target: target)
            } else { CorrectionObserver.forget() }
            self.teardown(); self.phase = .idle
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
        watchdog?.invalidate(); watchdog = nil
        targetAcquisitionInFlight = false
        inputGuard.stop()
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        streamer?.cancel(); streamer = nil
        whisperStreamer?.cancel(); whisperStreamer = nil
        livePaste?.cancel(); livePaste = nil
        recorder.cancel(); recorder.onBuffer = nil; recorder.onSamples = nil; recorder.accumulateSamples = true
        typer.cancel(); typer.onInvalidated = nil; target = nil
        destinationPID = nil; localTranscriber = nil
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
