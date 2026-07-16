import Foundation
import AVFoundation
import Combine
import WhisperKit

enum TranscriberError: LocalizedError {
    case missingKey
    case http(Int)
    case httpMessage(Int, String)
    case badResponse
    case modelNotReady

    var errorDescription: String? {
        switch self {
        case .missingKey:    return "Transcription API key is missing."
        case .http(let c):   return "Transcription failed (HTTP \(c))."
        case .httpMessage(let c, let m): return "Transcription failed (HTTP \(c)): \(m)"
        case .badResponse:   return "Transcription returned no text."
        case .modelNotReady: return "Speech model is not downloaded yet."
        }
    }
}

/// Turns recorded 16 kHz mono samples into text. Two implementations: local (WhisperKit)
/// and remote (cloud Whisper API). Both are "record → transcribe whole clip", so neither
/// loses the end of a phrase.
protocol Transcriber {
    func transcribe(samples: [Float], language: Lang?) async throws -> String
}

// MARK: - Remote (cloud Whisper API, OpenAI-compatible /audio/transcriptions)

/// Uploads the recorded clip to a cloud Whisper endpoint (default: Groq whisper-large-v3).
/// A hard timeout guarantees it never hangs on a weak connection (then the caller falls back).
struct RemoteWhisperTranscriber: Transcriber {
    let baseURL: String
    let model: String
    let apiKey: String
    var timeout: TimeInterval = 12

    func transcribe(samples: [Float], language: Lang?) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriberError.missingKey }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/audio/transcriptions") else { throw TranscriberError.badResponse }

        let wav = WAVEncoder.encode(samples: samples)
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = multipart(boundary: boundary, wav: wav, model: model, language: language?.whisperCode)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            // Surface the provider's own error message (OpenAI/Groq-style {"error":{"message":...}})
            // instead of a bare status code, so a bad model/URL/key is actionable from the UI.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                    throw TranscriberError.httpMessage(code, msg)
                }
                if let msg = json["message"] as? String {
                    throw TranscriberError.httpMessage(code, msg)
                }
            }
            throw TranscriberError.http(code)
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranscriberError.badResponse
    }

    private func multipart(boundary: String, wav: Data, model: String, language: String?) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        if let language { field("language", language) }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

// MARK: - Local (WhisperKit, on-device)

/// Runs Whisper locally via WhisperKit (CoreML). The model is loaded lazily on first use
/// (downloading it if necessary). Use `WhisperModelManager` to control/observe downloads.
actor LocalWhisperTranscriber: Transcriber {
    private let variant: String
    private var pipe: WhisperKit?

    init(variant: String) { self.variant = variant }

    func preload() async throws { try await ensureLoaded() }

    private func ensureLoaded() async throws {
        if pipe == nil {
            // Use our own models directory so downloads (explicit or lazy) share one location
            // that the settings UI can detect / size / delete. `prewarm` compiles/warms the
            // CoreML models for the Neural Engine up-front so the first transcription is fast.
            pipe = try await WhisperKit(WhisperKitConfig(model: variant,
                                                         downloadBase: WhisperPaths.modelsDir,
                                                         prewarm: true,
                                                         load: true))
        }
    }

    func transcribe(samples: [Float], language: Lang?) async throws -> String {
        try await ensureLoaded()
        guard let pipe else { throw TranscriberError.modelNotReady }
        let options = DecodingOptions(task: .transcribe, language: language?.whisperCode)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Dictation orchestrator (record → transcribe → optional cleanup)

/// Coordinates a full dictation: capture audio, then transcribe it with the engine chosen in
/// settings (local WhisperKit or remote cloud Whisper). Used from AppState (main thread);
/// completion is delivered on the main actor.
final class DictationEngine {
    private let recorder = AudioRecorder()
    private var local: LocalWhisperTranscriber?
    private var localVariant: String?
    private(set) var isTranscribing = false

    /// Reports model warm-up state (true = loading/initializing, false = ready). Invoked on main.
    var onPreparing: (@MainActor (Bool) -> Void)?

    /// Microphone permission (Whisper needs only the mic, not Speech Recognition).
    func requestMic(_ cb: @escaping (Bool) -> Void) {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { cb(true); return }
        AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { cb(ok) } }
    }

    private var didDuck = false

    func start(duckAudio: Bool = false) throws {
        if duckAudio { SystemAudio.duck(); didDuck = true }
        do { try recorder.start() }
        catch { if didDuck { SystemAudio.restore(); didDuck = false }; throw error }
    }

    func cancel() {
        recorder.cancel()
        if didDuck { SystemAudio.restore(); didDuck = false }
    }

    /// Warm the local model in the background so the first dictation isn't stuck loading it.
    /// Idempotent: a cached transcriber for the same variant won't reload. The actor serializes
    /// load, so a dictation that starts mid-preload simply awaits the same load.
    func preloadLocal(variant: String) {
        let t = localTranscriber(variant: variant)
        Task { @MainActor in self.onPreparing?(true) }
        Task.detached(priority: .utility) {
            try? await t.preload()
            await MainActor.run { self.onPreparing?(false) }
        }
    }

    /// Stop recording and transcribe the whole clip. `language` is a Whisper hint (nil = auto).
    func finish(settings: AppSettings, language: Lang?,
                completion: @escaping (Result<String, Error>) -> Void) {
        let samples = recorder.stop()
        if didDuck { SystemAudio.restore(); didDuck = false }   // bring audio back as soon as recording ends
        guard !samples.isEmpty else { completion(.success("")); return }
        isTranscribing = true

        let engine = settings.speechEngine
        let remote = RemoteWhisperTranscriber(baseURL: settings.transcriptionBaseURL,
                                              model: settings.transcriptionModel,
                                              apiKey: settings.transcriptionAPIKey)
        let localT = localTranscriber(variant: settings.whisperModel.variant)

        Task {
            do {
                let text: String
                switch engine {
                case .remote: text = try await remote.transcribe(samples: samples, language: language)
                case .local:  text = try await localT.transcribe(samples: samples, language: language)
                }
                await MainActor.run { self.isTranscribing = false; completion(.success(text)) }
            } catch {
                await MainActor.run { self.isTranscribing = false; completion(.failure(error)) }
            }
        }
    }

    private func localTranscriber(variant: String) -> LocalWhisperTranscriber {
        if let local, localVariant == variant { return local }
        let t = LocalWhisperTranscriber(variant: variant)
        local = t; localVariant = variant
        return t
    }
}

// MARK: - Local model storage

/// Single on-device location for all WhisperKit models so we fully control
/// detection, size reporting, and deletion. Nonisolated so the transcriber actor can read it.
enum WhisperPaths {
    static let modelsDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("BabelBar/WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

// MARK: - Local model download manager (download / cancel / delete / size for the settings UI)

/// Downloads and manages WhisperKit CoreML models on disk. Keeps exactly one model at a time:
/// finishing a new download removes the others. Observed by the settings UI.
@MainActor
final class WhisperModelManager: ObservableObject {
    static let shared = WhisperModelManager()

    @Published private(set) var downloading: WhisperModel?
    @Published private(set) var progress: Double = 0
    /// True while the local model is loading/warming up (after download or on launch).
    @Published var preparing = false
    /// variant → on-disk folder path of a fully downloaded model.
    @Published private(set) var folders: [String: String]

    /// Called on the main thread when a model finishes downloading (AppState uses it to prewarm).
    var onModelReady: (() -> Void)?

    private var task: Task<Void, Never>?
    private let key = "babelbar.whisperModelFolders"

    /// A folder counts as a fully-downloaded model only if it is the CoreML variant directory
    /// (`openai_whisper-<variant>`) that actually holds the compiled encoder — and is NOT inside
    /// HuggingFace's `.cache/` download-staging tree. The tokenizer-only `openai/whisper-<variant>`
    /// folder and the 2 KB `.cache/.../openai_whisper-<variant>` pointer folder both fail this,
    /// so they can never be mistaken for a real download.
    nonisolated static func isValidModelFolder(_ url: URL, variant: String) -> Bool {
        guard !url.path.contains("/.cache/"),
              url.lastPathComponent == "openai_whisper-\(variant)" else { return false }
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    /// Nonisolated disk check so non-MainActor callers (AppState) can gate prewarming
    /// without auto-triggering a download.
    nonisolated static func isVariantOnDisk(_ variant: String) -> Bool {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: WhisperPaths.modelsDir,
                                     includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        for case let url as URL in en where isValidModelFolder(url, variant: variant) {
            return true
        }
        return false
    }

    private init() {
        folders = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        reconcile()
    }

    // MARK: queries

    func isDownloaded(_ m: WhisperModel) -> Bool { folderURL(m) != nil }

    /// Resolved on-disk folder for a model (recorded path, or discovered by scanning).
    func folderURL(_ m: WhisperModel) -> URL? {
        // A recorded path counts only if it still points at a real model folder. Older builds
        // sometimes persisted the 2 KB `.cache/.../openai_whisper-<variant>` staging folder, which
        // made the UI report "Downloaded · 2 KB" while the actual weights sat unused nearby.
        // Reject such stale/invalid paths and re-scan so we heal automatically.
        if let p = folders[m.variant] {
            let url = URL(fileURLWithPath: p)
            if Self.isValidModelFolder(url, variant: m.variant) { return url }
            folders[m.variant] = nil; persist()
        }
        if let found = scan(for: m.variant) {
            folders[m.variant] = found.path; persist()
            return found
        }
        return nil
    }

    /// Human-readable size on disk (e.g. "612 MB"), or nil if not present.
    func diskSize(_ m: WhisperModel) -> String? {
        guard let url = folderURL(m) else { return nil }
        let bytes = Self.folderSize(url)
        guard bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: download / cancel / delete

    func download(_ m: WhisperModel) {
        guard downloading == nil else { return }
        downloading = m
        progress = 0
        task = Task {
            do {
                let url = try await WhisperKit.download(variant: m.variant,
                                                        downloadBase: WhisperPaths.modelsDir) { p in
                    Task { @MainActor in if self.downloading == m { self.progress = p.fractionCompleted } }
                }
                if Task.isCancelled { self.resetDownload(m); return }
                self.folders[m.variant] = url.path
                self.deleteOthers(keeping: m)        // one model at a time
                self.persist()
                self.downloading = nil
                self.progress = 0
                self.task = nil
                self.onModelReady?()                 // prewarm now that files are present
            } catch {
                self.resetDownload(m)
            }
        }
    }

    func cancelDownload() {
        guard let m = downloading else { return }
        task?.cancel()
        task = nil
        resetDownload(m)
    }

    func delete(_ m: WhisperModel) {
        if let url = folderURL(m) { try? FileManager.default.removeItem(at: url) }
        folders[m.variant] = nil
        persist()
    }

    // MARK: helpers

    private func resetDownload(_ m: WhisperModel) {
        downloading = nil
        progress = 0
        task = nil
        // Best-effort cleanup of a partial folder we never recorded.
        if folders[m.variant] == nil, let partial = scan(for: m.variant) {
            try? FileManager.default.removeItem(at: partial)
        }
    }

    private func deleteOthers(keeping keep: WhisperModel) {
        for other in WhisperModel.allCases where other != keep {
            if let url = folderURL(other) { try? FileManager.default.removeItem(at: url) }
            folders[other.variant] = nil
        }
    }

    private func reconcile() {
        var changed = false
        for (variant, path) in folders where !FileManager.default.fileExists(atPath: path) {
            folders[variant] = nil; changed = true
        }
        if changed { persist() }
    }

    private func persist() { UserDefaults.standard.set(folders, forKey: key) }

    /// Find a fully-downloaded model folder for this variant. Matches only the real CoreML
    /// directory (encoder present, not `.cache/` staging) so tokenizer-only and partial folders
    /// are never returned.
    private func scan(for variant: String) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: WhisperPaths.modelsDir,
                                     includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in en where Self.isValidModelFolder(url, variant: variant) {
            return url
        }
        return nil
    }

    static func folderSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
