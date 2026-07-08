import AVFoundation

/// Captures the microphone into a 16 kHz mono Float buffer — the format Whisper wants.
/// Unlike streaming recognition, we record the whole utterance and transcribe it on stop,
/// so the end of the phrase is never cut off. Drives `MicLevel` for the recording waveform.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Begin capturing. Throws if the audio engine can't start.
    func start() throws {
        // A second start (e.g. cursor dictation while the in-app mic is already recording)
        // must not install a second tap on the same bus — that raises an NSException.
        if isRecording { stop() }
        lock.lock(); samples.removeAll(); lock.unlock()
        MicLevel.shared.reset()

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
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
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isRecording = false
        MicLevel.shared.reset()
        lock.lock(); let s = samples; samples.removeAll(); lock.unlock()
        return s
    }

    func cancel() { stop() }

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
