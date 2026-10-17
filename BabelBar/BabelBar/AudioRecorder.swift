import AVFoundation
import CoreAudio

/// Captures the microphone into a 16 kHz mono Float buffer — the format Whisper wants.
/// Unlike streaming recognition, we record the whole utterance and transcribe it on stop,
/// so the end of the phrase is never cut off. Drives `MicLevel` for the recording waveform.
final class AudioRecorder {
    // Hardware graph operations run in order on this queue. Neither creating an
    // aggregate device nor waiting for the microphone can block the main run loop.
    private let captureQueue = DispatchQueue(label: "com.babelbar.audio-capture", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var route: AudioRoute?
    private var graphInvalid = false
    private var capture: Capture?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    // Facade state and consumer configuration are accessed on the main thread.
    // Each audio tap receives its own immutable configuration in `Capture`.
    private var operation = 0
    private(set) var isRecording = false
    /// Seconds of audio the last clip contains, divided by the seconds the recording actually ran.
    /// A healthy capture sits at ~1.0.
    private(set) var lastCaptureRatio: Double = 1
    private(set) var lastWallDuration: TimeInterval = 0

    /// Live consumer of the input buffers (streaming recognition, v3.0). Called
    /// on the audio thread — must stay cheap.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Converted Whisper-ready samples for streaming consumers. Called on the audio thread;
    /// consumers must copy/enqueue quickly and do model work asynchronously.
    var onSamples: (([Float]) -> Void)?
    /// When a live consumer handles audio itself, don't accumulate samples: a
    /// streaming session can run for many minutes and the batch path isn't used.
    var accumulateSamples = true

    /// Prepare the graph without starting microphone capture. Permission prompts
    /// belong to the user action; background preparation never requests access.
    func prepare() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        captureQueue.async { [weak self] in
            guard let self, self.capture == nil else { return }
            do { _ = try self.preparedEngine() }
            catch { NSLog("BabelBar audio: preparation failed: %@", error.localizedDescription) }
        }
    }

    func releasePrepared() {
        captureQueue.async { [weak self] in
            guard let self, self.capture == nil else { return }
            self.discardGraph()
        }
    }

    /// Begin capturing asynchronously. Starting counts as busy immediately, so
    /// another shortcut cannot open a second recording while hardware is waking.
    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        operation &+= 1
        let request = operation
        isRecording = true
        let onBuffer = self.onBuffer, onSamples = self.onSamples
        let accumulate = accumulateSamples
        MicLevel.shared.reset()
        captureQueue.async {
            let result = Result {
                _ = self.stopCapture()
                let start = ProcessInfo.processInfo.systemUptime
                let engine = try self.preparedEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                let capture = Capture(format: format, targetFormat: self.targetFormat,
                                      accumulate: accumulate, onBuffer: onBuffer, onSamples: onSamples)
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    capture.append(buffer)
                }
                engine.prepare()
                do { try engine.start() }
                catch {
                    engine.stop()
                    input.removeTap(onBus: 0)
                    self.discardGraph()
                    throw error
                }
                capture.startedAt = ProcessInfo.processInfo.systemUptime
                self.capture = capture
                NSLog("BabelBar audio: microphone started in %.0f ms", (capture.startedAt - start) * 1000)
            }
            DispatchQueue.main.async {
                guard self.operation == request else {
                    completion(.failure(CancellationError()))
                    return
                }
                if case .failure = result { self.isRecording = false }
                completion(result)
            }
        }
    }

    /// Stop in the same queue as start, then deliver the completed clip on main.
    /// A stop issued during startup invalidates its eventual success callback.
    func stop(completion: @escaping ([Float]) -> Void = { _ in }) {
        operation &+= 1
        let request = operation
        isRecording = false
        captureQueue.async {
            let finished = self.stopCapture()
            DispatchQueue.main.async {
                if self.operation == request {
                    if let finished {
                        self.lastWallDuration = finished.duration
                        self.lastCaptureRatio = finished.ratio
                    }
                    MicLevel.shared.reset()
                }
                completion(finished?.samples ?? [])
            }
        }
    }

    func cancel() { stop() }

    private func preparedEngine() throws -> AVAudioEngine {
        let currentRoute = AudioRoute.current()
        if let engine, !graphInvalid, route == currentRoute { return engine }
        discardGraph()
        let began = ProcessInfo.processInfo.systemUptime
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "BabelBar.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone has no input format"])
        }
        engine.prepare()
        self.engine = engine
        route = currentRoute
        graphInvalid = false
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            guard let self else { return }
            self.captureQueue.async {
                guard self.engine === engine else { return }
                self.graphInvalid = true
                if self.capture == nil { self.discardGraph() }
            }
        }
        NSLog("BabelBar audio: graph prepared in %.0f ms", (ProcessInfo.processInfo.systemUptime - began) * 1000)
        return engine
    }

    private func stopCapture() -> (samples: [Float], duration: TimeInterval, ratio: Double)? {
        guard let capture else { return nil }
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        self.capture = nil
        let samples = capture.takeSamples()
        let duration = max(0, ProcessInfo.processInfo.systemUptime - capture.startedAt)
        let ratio = duration > 0 ? Double(samples.count) / targetFormat.sampleRate / duration : 1
        // A reused graph is valid only for the same input/output devices and format.
        // Rebuild after a route/configuration change, including a Continuity mic.
        if graphInvalid || route != AudioRoute.current() { discardGraph() }
        return (samples, duration, ratio)
    }

    private func discardGraph() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine = nil
        route = nil
        graphInvalid = false
    }

    private struct AudioRoute: Equatable {
        let input: AudioDeviceID
        let output: AudioDeviceID
        static func current() -> AudioRoute {
            func device(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
                var address = AudioObjectPropertyAddress(mSelector: selector,
                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: AudioDeviceID = 0
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value)
                return value
            }
            return AudioRoute(input: device(kAudioHardwarePropertyDefaultInputDevice),
                              output: device(kAudioHardwarePropertyDefaultOutputDevice))
        }
    }

    /// The tap owns this capture's converter and callbacks. Nothing reaches back
    /// into mutable UI configuration, even if another session is already queued.
    private final class Capture {
        let targetFormat: AVAudioFormat
        let converter: AVAudioConverter?
        let accumulate: Bool
        let onBuffer: ((AVAudioPCMBuffer) -> Void)?
        let onSamples: (([Float]) -> Void)?
        var startedAt: TimeInterval = 0
        private var samples: [Float] = []
        private let lock = NSLock()

        init(format: AVAudioFormat, targetFormat: AVAudioFormat, accumulate: Bool,
             onBuffer: ((AVAudioPCMBuffer) -> Void)?, onSamples: (([Float]) -> Void)?) {
            self.targetFormat = targetFormat
            self.accumulate = accumulate
            self.onBuffer = onBuffer
            self.onSamples = onSamples
            // Apple Speech accepts native buffers: skip resampling/allocation entirely.
            converter = accumulate || onSamples != nil ? AVAudioConverter(from: format, to: targetFormat) : nil
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            MicLevel.shared.push(AudioRecorder.micLevel(of: buffer))
            onBuffer?(buffer)
            guard let converter else { return }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, out.frameLength > 0, let channel = out.floatChannelData else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
            if accumulate {
                lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
            }
            onSamples?(chunk)
        }

        func takeSamples() -> [Float] {
            lock.lock(); defer { lock.unlock() }
            let result = samples; samples = []
            return result
        }
    }

    /// True when the clip's own length disagrees with how long the recording actually ran, which
    /// means the input device is not delivering audio on a real timeline. Seen in the wild on a
    /// built-in microphone that handed out every block about five times over, timestamps to
    /// match: 2 s of speech arrived as 9.5 s of audio. Every capture API on that machine saw it
    /// and restarting `coreaudiod` did not clear it. Such a clip is speech stretched past
    /// recognition — Whisper finds no words in it and answers with subtitle credits
    /// ("Undertexter av …") or "Thank you.", which then lands at the cursor as if it were the
    /// dictation. Better to name the fault than to insert its invention.
    ///
    /// The window is deliberately wide: a healthy capture sits at 1.0 and normal jitter or a
    /// dropped buffer never approaches these edges. Very short taps are exempt — start-up latency
    /// dominates them and the ratio means nothing.
    var captureLooksBroken: Bool {
        lastWallDuration >= 0.6 && (lastCaptureRatio > 1.5 || lastCaptureRatio < 0.5)
    }

    /// True when the clip carries no speech at all. Sending digital silence to Whisper is worse
    /// than sending nothing: it answers with training-set filler ("Thanks for watching",
    /// "Продолжение следует…", a lone "."), which then gets inserted as if it were dictation.
    /// The threshold sits far below quiet speech (RMS ≈ 0.01…0.05) and above the noise floor of
    /// a muted or dead input (≈ 1e-5), so only a truly silent clip trips it.
    static func isSilent(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return true }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot() < 0.0015
    }

    /// Perceptual 0…1 input level from a PCM buffer (RMS with gain) — drives the recording
    /// waveform. Runs on the audio thread, so keep it cheap.
    static func micLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        let samples = channels[0]
        var sum: Float = 0
        for i in 0..<n { let s = samples[i]; sum += s * s }
        let rms = (sum / Float(n)).squareRoot()
        // Speech RMS is small (~0…0.2); boost + shape so normal talking reaches the top.
        return min(1, powf(rms * 24, 0.6))
    }
}

/// Minimal 16-bit PCM WAV encoder for uploading recorded audio to a cloud Whisper API.
enum WAVEncoder {
    static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let channels = 1, bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * 2

        var d = Data()
        d.reserveCapacity(44 + dataSize)   // header + samples, avoids repeated reallocs on long clips
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func tag(_ s: String) { d.append(contentsOf: s.utf8) }

        tag("RIFF"); u32(UInt32(36 + dataSize)); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bitsPerSample))
        tag("data"); u32(UInt32(dataSize))
        for f in samples {
            let clamped = max(-1, min(1, f))
            u16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return d
    }
}
