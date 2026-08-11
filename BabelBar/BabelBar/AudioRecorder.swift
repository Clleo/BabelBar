import AVFoundation

/// Captures the microphone into a 16 kHz mono Float buffer — the format Whisper wants.
/// Unlike streaming recognition, we record the whole utterance and transcribe it on stop,
/// so the end of the phrase is never cut off. Drives `MicLevel` for the recording waveform.
final class AudioRecorder {
    /// Built fresh for every recording — see the comment in `start()`.
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    private var startedAt: Date?
    /// Seconds of audio the last clip contains, divided by the seconds the recording actually ran.
    /// A healthy capture sits at ~1.0.
    private(set) var lastCaptureRatio: Double = 1
    private(set) var lastWallDuration: TimeInterval = 0

    /// Begin capturing. Throws if the audio engine can't start.
    func start() throws {
        // A second start (e.g. cursor dictation while the in-app mic is already recording)
        // must not install a second tap on the same bus — that raises an NSException.
        if isRecording { stop() }
        lock.lock(); samples.removeAll(); lock.unlock()
        MicLevel.shared.reset()

        // A NEW engine per recording. `inputNode` binds to a private aggregate device
        // (`CADefaultDeviceAggregate-<pid>`) the first time it is materialized and holds on to
        // that binding, so an engine kept for the life of the app outlives every route change —
        // headphones, an output switch, a Continuity mic appearing. Rebuilding the graph costs
        // milliseconds and always binds to the devices that are current *now*.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        startedAt = Date()
        isRecording = true
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        MicLevel.shared.push(Self.micLevel(of: buffer))   // live waveform
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard err == nil, out.frameLength > 0, let ch = out.floatChannelData else { return }
        let n = Int(out.frameLength)
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
        lock.unlock()
    }

    /// Stop capturing and return the recorded 16 kHz mono samples.
    @discardableResult
    func stop() -> [Float] {
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil          // the next recording builds its own, bound to the current devices
        converter = nil
        isRecording = false
        MicLevel.shared.reset()
        lock.lock(); let s = samples; samples.removeAll(); lock.unlock()

        lastWallDuration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        lastCaptureRatio = lastWallDuration > 0
            ? Double(s.count) / targetFormat.sampleRate / lastWallDuration
            : 1
        startedAt = nil
        return s
    }

    func cancel() { stop() }

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
