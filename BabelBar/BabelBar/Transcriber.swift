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
    case silentInput
    case brokenCapture(ratio: Double)

    var errorDescription: String? {
        switch self {
        case .missingKey:    return "Transcription API key is missing."
        case .http(let c):   return "Transcription failed (HTTP \(c))."
        case .httpMessage(let c, let m): return "Transcription failed (HTTP \(c)): \(m)"
        case .badResponse:   return "Transcription returned no text."
        case .modelNotReady: return "Speech model is not downloaded yet."
        case .silentInput:   return "The microphone captured only silence."
        case .brokenCapture(let r):
            return String(format: "The microphone delivered %.1f× more audio than the recording "
                          + "lasted, so the speech in it is unusable. Switch the input device in "
                          + "System Settings › Sound, or restart the Mac.", r)
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
    private var loadTask: Task<WhisperKit, Error>?
    private var loadGeneration = 0

    init(variant: String) { self.variant = variant }

    func preload() async throws { try await ensureLoaded() }

    func unload() async {
        loadGeneration &+= 1
        let pending = loadTask, loaded = pipe
        loadTask = nil
        pipe = nil
        pending?.cancel()
        let loading = try? await pending?.value
        await loaded?.unloadModels()
        if let loading, loading !== loaded { await loading.unloadModels() }
    }

    private func ensureLoaded() async throws {
        guard pipe == nil else { return }
        let generation = loadGeneration
        let pending: Task<WhisperKit, Error>
        if let loadTask { pending = loadTask }
        else {
            guard let folder = WhisperModelManager.findModelFolder(variant: variant) else {
                throw TranscriberError.modelNotReady
            }
            let variant = self.variant
            pending = Task {
                let began = ProcessInfo.processInfo.systemUptime
                // A local folder bypasses HuggingFace's download/snapshot lookup.
                // CoreML specializes cached models during load; prewarm=true would
                // load, unload and load the same weights a second time on every launch.
                let loaded = try await WhisperKit(WhisperKitConfig(model: variant,
                    downloadBase: WhisperPaths.modelsDir, modelFolder: folder.path,
                    verbose: false, prewarm: false, load: true, download: false))
                NSLog("BabelBar model: %@ loaded locally in %.0f ms", variant,
                      (ProcessInfo.processInfo.systemUptime - began) * 1000)
                return loaded
            }
            loadTask = pending
        }
        do {
            let loaded = try await pending.value
            guard generation == loadGeneration else { throw CancellationError() }
            pipe = loaded
            loadTask = nil
            try? WhisperPaths.removeDownloadMetadata(variant: variant)
        } catch {
            if generation == loadGeneration { loadTask = nil }
            throw error
        }
    }

    func transcribe(samples: [Float], language: Lang?) async throws -> String {
        try await ensureLoaded()
        guard let pipe else { throw TranscriberError.modelNotReady }
        // `language: nil` alone does NOT mean auto-detect in WhisperKit: with the default
        // `usePrefillPrompt: true`, `detectLanguage` defaults to false and the decoder prefills
        // `<|en|>` (Constants.defaultLanguageCode). A forced English token on Russian speech makes
        // Whisper *translate* instead of transcribe — the "I dictate in Russian, English text is
        // inserted" bug. Ask for real language detection whenever we have no explicit hint.
        let options = DecodingOptions(task: .transcribe,
                                      language: language?.whisperCode,
                                      detectLanguage: language == nil)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short live windows need bounded decoding. Timestamp generation and
    /// temperature fallbacks add delay and can turn uncertain trailing audio
    /// into filler punctuation; the full-clip path above retains its settings.
    func transcribeLive(samples: [Float], language: Lang?) async throws -> String {
        try await ensureLoaded()
        guard let pipe else { throw TranscriberError.modelNotReady }
        let options = DecodingOptions(task: .transcribe,
                                      language: language?.whisperCode,
                                      temperatureFallbackCount: 0,
                                      sampleLength: 160,
                                      detectLanguage: language == nil,
                                      withoutTimestamps: true)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap(\.segments)
        let lowConfidenceSilence = !segments.isEmpty && segments.allSatisfy {
            $0.noSpeechProb > 0.85 && $0.avgLogprob < -0.7
        }
        if WhisperTranscriptFilter.isFiller(text) || lowConfidenceSilence {
            NSLog("BabelBar live-whisperkit: discarded a silence hallucination")
            return ""
        }
        return text
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

    /// True while a batch capture or its transcription is running — the live
    /// dictation controller checks this so two engines never fight over the mic.
    var isBusy: Bool { recorder.isRecording || isTranscribing }

    /// Reports model warm-up state (true = loading/initializing, false = ready). Invoked on main.
    var onPreparing: (@MainActor (Bool) -> Void)?

    /// Optional LLM cleanup of the transcript, wired by AppState (it owns the API accounts and
    /// the token counter). Must return the input unchanged when it can't do better — a dictation
    /// is never dropped because the cleanup failed.
    var aiCleanup: ((String, AppSettings) async -> String)?

    /// Microphone permission (Whisper needs only the mic, not Speech Recognition).
    func requestMic(_ cb: @escaping (Bool) -> Void) {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { cb(true); return }
        AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { cb(ok) } }
    }

    private var didDuck = false

    func prepareCapture() { recorder.prepare() }
    func releasePreparedCapture() { recorder.releasePrepared() }

    func start(duckAudio: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        recorder.onBuffer = nil; recorder.onSamples = nil; recorder.accumulateSamples = true
        recorder.start { [weak self] result in
            if case .success = result, duckAudio {
                SystemAudio.duck(); self?.didDuck = true
            }
            completion(result)
        }
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
            do { try await t.preload() }
            catch { NSLog("BabelBar model: preload failed: %@", error.localizedDescription) }
            await MainActor.run { self.onPreparing?(false) }
        }
    }

    /// Release the cached CoreML pipeline before its files are removed from disk.
    func unloadLocal(variant: String) async {
        guard localVariant == variant, let transcriber = local else { return }
        local = nil
        localVariant = nil
        await transcriber.unload()
    }

    /// Stop recording and transcribe the whole clip. `language` is a Whisper hint (nil = auto).
    func finish(settings: AppSettings, language: Lang?,
                completion: @escaping (Result<String, Error>) -> Void) {
        guard recorder.isRecording else { completion(.success("")); return }
        isTranscribing = true
        recorder.stop { [weak self] samples in
            self?.transcribeCaptured(samples, settings: settings, language: language, completion: completion)
        }
    }

    private func transcribeCaptured(_ samples: [Float], settings: AppSettings, language: Lang?,
                                   completion: @escaping (Result<String, Error>) -> Void) {
        if didDuck { SystemAudio.restore(); didDuck = false }   // bring audio back as soon as recording ends
        guard !samples.isEmpty else { isTranscribing = false; completion(.success("")); return }
        // Never hand Whisper a clip it cannot get words out of — it fills the gap with
        // training-set filler and the user gets "Thanks for watching" pasted at the cursor.
        // Say what actually happened instead.
        guard !recorder.captureLooksBroken else {
            isTranscribing = false
            completion(.failure(TranscriberError.brokenCapture(ratio: recorder.lastCaptureRatio)))
            return
        }
        guard !AudioRecorder.isSilent(samples) else {
            isTranscribing = false; completion(.failure(TranscriberError.silentInput)); return
        }
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
                case .remote:
                    do {
                        text = try await remote.transcribe(samples: samples, language: language)
                    } catch {
                        // Weak/no connection (or a bad key): fall back to the local model,
                        // but only when it's already on disk — never auto-download here.
                        guard WhisperModelManager.isVariantOnDisk(settings.whisperModel.variant) else { throw error }
                        text = try await localT.transcribe(samples: samples, language: language)
                    }
                case .local:
                    // Never let `ensureLoaded()` start a lazy multi-hundred-MB download here: the
                    // overlay would sit on its loader for minutes and the app would look frozen.
                    // Downloads belong to the settings UI (WhisperModelManager).
                    guard WhisperModelManager.isVariantOnDisk(settings.whisperModel.variant) else {
                        throw TranscriberError.modelNotReady
                    }
                    text = try await localT.transcribe(samples: samples, language: language)
                }
                let final = await self.postProcess(text, settings: settings)
                await MainActor.run { self.isTranscribing = false; completion(.success(final)) }
            } catch {
                await MainActor.run { self.isTranscribing = false; completion(.failure(error)) }
            }
        }
    }

    /// Shared post-recognition stage for **every** dictation path (mic button, Fn, Shift+Fn),
    /// which is why it lives here and not in the callers: spoken punctuation has to be resolved
    /// before the Shift+Fn transcript reaches the translator, or "запятая" gets translated as a word.
    private func postProcess(_ text: String, settings: AppSettings) async -> String {
        guard !text.isEmpty, !WhisperTranscriptFilter.isFiller(text) else { return "" }
        var out = text
        // Voice commands must never eat the whole transcript: "точка" spoken on its own resolves
        // to a mark with nothing to attach to, and the result would be an empty insertion.
        if settings.voiceCommandsEnabled {
            let resolved = VoiceCommands.apply(to: out)
            if !resolved.isEmpty { out = resolved }
        }
        if settings.dictationCleanupEnabled, let aiCleanup, !out.isEmpty {
            out = await aiCleanup(out, settings)
        }
        return out
    }

    private func localTranscriber(variant: String) -> LocalWhisperTranscriber {
        if let local, localVariant == variant { return local }
        let t = LocalWhisperTranscriber(variant: variant)
        local = t; localVariant = variant
        return t
    }

    /// Reuse the already prewarmed CoreML pipeline for continuous dictation.
    func localTranscriberForLive(variant: String) -> LocalWhisperTranscriber {
        localTranscriber(variant: variant)
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

    /// WhisperKit used this shared location before BabelBar moved its models into Application
    /// Support. We recognize only BabelBar's three WhisperKit model folders there for cleanup.
    static let legacyModelsDir: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("huggingface", isDirectory: true)
    }()

    static func removeDownloadMetadata(variant: String) throws {
        let root = modelsDir.standardizedFileURL
        let repository = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let tokenizerVariant = variant.hasPrefix("large-v3") ? "large-v3" : variant
        let targets = [
            repository.appendingPathComponent(".cache/huggingface/download/openai_whisper-\(variant)", isDirectory: true),
            root.appendingPathComponent("models/openai/whisper-\(tokenizerVariant)/.cache", isDirectory: true)
        ]
        let fm = FileManager.default
        for target in targets where fm.fileExists(atPath: target.path) {
            guard target.standardizedFileURL.path.hasPrefix(root.path + "/") else { continue }
            try fm.removeItem(at: target)
        }
        pruneEmptyDirectories(startingAt: repository.appendingPathComponent(".cache/huggingface/download"), root: root)
        pruneEmptyDirectories(startingAt: root.appendingPathComponent("models/openai/whisper-\(tokenizerVariant)"), root: root)
    }

    private static func pruneEmptyDirectories(startingAt directory: URL, root: URL) {
        let fm = FileManager.default
        var current = directory.standardizedFileURL
        while current.path.hasPrefix(root.path + "/"),
              (try? fm.contentsOfDirectory(atPath: current.path))?.isEmpty == true {
            try? fm.removeItem(at: current)
            current.deleteLastPathComponent()
        }
    }
}

enum WhisperModelStorageKind: String, Identifiable {
    case app, legacy
    var id: String { rawValue }
}

struct StoredWhisperModel: Identifiable {
    let model: WhisperModel
    let kind: WhisperModelStorageKind
    var id: String { "\(model.rawValue)-\(kind.rawValue)" }
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
    @Published private(set) var storageError: String?
    @Published private(set) var storageRevision = 0

    /// Called before deleting model files so AppState can unload its CoreML pipeline.
    var onModelWillDelete: ((String) async -> Void)?

    /// Called on the main thread when a model finishes downloading (AppState uses it to prewarm).
    var onModelReady: (() -> Void)?

    private var task: Task<Void, Never>?
    private var selectedModel: WhisperModel?
    private var selectionRevision = 0
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

    /// Find a fully-downloaded model folder for this variant on disk. Matches only the real
    /// CoreML directory (encoder present, not `.cache/` staging) so tokenizer-only and
    /// partial folders are never returned. Nonisolated so non-MainActor callers can use it.
    nonisolated static func findModelFolder(variant: String) -> URL? {
        let fm = FileManager.default
        if let saved = UserDefaults.standard.dictionary(forKey: "babelbar.whisperModelFolders")?[variant] as? String {
            let folder = URL(fileURLWithPath: saved)
            if isValidModelFolder(folder, variant: variant) { return folder }
        }
        let standard = WhisperPaths.modelsDir
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(variant)")
        if isValidModelFolder(standard, variant: variant) { return standard }
        guard let en = fm.enumerator(at: WhisperPaths.modelsDir,
                                     includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in en {
            if isValidModelFolder(url, variant: variant) { return url }
            // Never walk thousands of compiled weights or tokenizer/cache files
            // while looking for a sibling model directory.
            if url.pathExtension == "mlmodelc" || url.lastPathComponent.hasPrefix("openai_whisper-") {
                en.skipDescendants()
            }
        }
        return nil
    }

    /// Nonisolated disk check so non-MainActor callers (AppState) can gate prewarming
    /// without auto-triggering a download.
    nonisolated static func isVariantOnDisk(_ variant: String) -> Bool {
        findModelFolder(variant: variant) != nil
    }

    private init() {
        folders = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        reconcile()
    }

    // MARK: queries

    func isDownloaded(_ m: WhisperModel) -> Bool { folderURL(m) != nil }

    /// Installed full models, independent of which recognition engine is active.
    var storedModels: [StoredWhisperModel] {
        WhisperModel.allCases.flatMap { model in
            var entries: [StoredWhisperModel] = []
            if isDownloaded(model) { entries.append(StoredWhisperModel(model: model, kind: .app)) }
            if legacyTargets(for: model).contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                entries.append(StoredWhisperModel(model: model, kind: .legacy))
            }
            return entries
        }
    }

    /// Selecting another local model frees the previously installed model immediately.
    /// An in-progress download is left alone until its completion/cancellation path cleans it.
    func select(_ model: WhisperModel) {
        selectedModel = model
        selectionRevision &+= 1
        let revision = selectionRevision
        let inProgress = downloading
        storageError = nil
        if inProgress != nil && inProgress != model { cancelDownload() }
        Task { @MainActor in
            guard self.selectionRevision == revision else { return }
            if !self.isDownloaded(model), inProgress != model {
                do { try await self.removeModelFiles(for: model) }
                catch { self.storageError = error.localizedDescription }
            }
            await self.deleteOthers(keeping: model, protecting: inProgress)
            if self.isDownloaded(model) {
                do { try await self.removeLegacyModelFiles(for: model) }
                catch { self.storageError = error.localizedDescription }
                do { try self.removeDownloadMetadata(for: model) }
                catch { self.storageError = error.localizedDescription }
            }
        }
    }

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

    func diskSize(_ stored: StoredWhisperModel) -> String? {
        let urls = stored.kind == .app ? appTargets(for: stored.model) : legacyTargets(for: stored.model)
        let bytes = urls.reduce(Int64(0)) { total, url in
            FileManager.default.fileExists(atPath: url.path) ? total + Self.folderSize(url) : total
        }
        guard bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: download / cancel / delete

    func download(_ m: WhisperModel) {
        guard downloading == nil else { return }
        storageError = nil
        if selectedModel == nil { selectedModel = m }
        downloading = m
        progress = 0
        task = Task {
            do {
                let url = try await WhisperKit.download(variant: m.variant,
                                                        downloadBase: WhisperPaths.modelsDir) { p in
                    Task { @MainActor in if self.downloading == m { self.progress = p.fractionCompleted } }
                }
                if Task.isCancelled { await self.resetDownload(m); return }
                self.folders[m.variant] = url.path
                let keep = self.selectedModel ?? m
                if keep != m {
                    do { try await self.removeModelFiles(for: m) }
                    catch { self.storageError = error.localizedDescription }
                } else {
                    do { try await self.removeLegacyModelFiles(for: m) }
                    catch { self.storageError = error.localizedDescription }
                }
                await self.deleteOthers(keeping: keep) // one model at a time
                if self.isDownloaded(keep) {
                    do { try self.removeDownloadMetadata(for: keep) }
                    catch { self.storageError = error.localizedDescription }
                }
                self.persist()
                self.downloading = nil
                self.progress = 0
                self.task = nil
                self.onModelReady?()                 // prewarm now that files are present
            } catch {
                await self.resetDownload(m)
            }
        }
    }

    func cancelDownload() {
        guard downloading != nil else { return }
        task?.cancel()
    }

    func delete(_ stored: StoredWhisperModel) {
        storageError = nil
        if stored.kind == .app, downloading == stored.model { cancelDownload() }
        Task { @MainActor in
            do {
                if stored.kind == .app { try await self.removeModelFiles(for: stored.model) }
                else { try await self.removeLegacyModelFiles(for: stored.model) }
                if stored.kind == .app { self.folders[stored.model.variant] = nil }
                self.persist()
            } catch {
                self.storageError = error.localizedDescription
            }
        }
    }

    // MARK: helpers

    private func resetDownload(_ m: WhisperModel) async {
        guard downloading == m else { return }
        downloading = nil
        progress = 0
        task = nil
        // Failed/cancelled downloads can leave partial weights and tokenizer/cache files.
        if folderURL(m) == nil {
            do { try await removeModelFiles(for: m) }
            catch { storageError = error.localizedDescription }
        }
        await deleteOthers(keeping: selectedModel ?? m)
    }

    private func deleteOthers(keeping keep: WhisperModel, protecting protected: WhisperModel? = nil) async {
        for other in WhisperModel.allCases where other != keep && other != protected {
            guard selectionRevision == 0 || selectedModel == keep else { return }
            do {
                try await removeModelFiles(for: other)
                try await removeLegacyModelFiles(for: other)
                folders[other.variant] = nil
            } catch {
                storageError = error.localizedDescription
            }
        }
        persist()
    }

    /// Remove the CoreML weights, tokenizer copy, and HuggingFace partial-download metadata for
    /// a single variant. Everything stays scoped to BabelBar's private model directory.
    private func removeModelFiles(for model: WhisperModel) async throws {
        let root = WhisperPaths.modelsDir.standardizedFileURL
        let repository = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        var targets = appTargets(for: model)
        if let recorded = folderURL(model), recorded.standardizedFileURL.path.hasPrefix(root.path + "/") {
            targets.append(recorded.standardizedFileURL)
        }
        let fm = FileManager.default
        guard targets.contains(where: { fm.fileExists(atPath: $0.path) }) else { return }
        await onModelWillDelete?(model.variant)
        for target in targets where fm.fileExists(atPath: target.path) {
            guard target.standardizedFileURL.path.hasPrefix(root.path + "/") else { continue }
            try fm.removeItem(at: target)
        }
        pruneEmptyDirectories(startingAt: repository.appendingPathComponent(".cache/huggingface/download"), root: root)
        pruneEmptyDirectories(startingAt: root.appendingPathComponent("models/openai"), root: root)
        pruneEmptyDirectories(startingAt: repository, root: root)
        storageRevision &+= 1
    }

    private func removeLegacyModelFiles(for model: WhisperModel) async throws {
        let root = WhisperPaths.legacyModelsDir.standardizedFileURL
        let targets = legacyTargets(for: model)
        let fm = FileManager.default
        guard targets.contains(where: { fm.fileExists(atPath: $0.path) }) else { return }
        for target in targets where fm.fileExists(atPath: target.path) {
            guard target.standardizedFileURL.path.hasPrefix(root.path + "/") else { continue }
            try fm.removeItem(at: target)
        }
        let repository = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        pruneEmptyDirectories(startingAt: repository.appendingPathComponent(".cache/huggingface/download"), root: root)
        pruneEmptyDirectories(startingAt: root.appendingPathComponent("models/openai"), root: root)
        pruneEmptyDirectories(startingAt: repository, root: root)
        storageRevision &+= 1
    }

    /// HuggingFace's .metadata files only support resuming/checking downloads. Inference reads
    /// the model weights and tokenizer files directly, so discard these sidecars for the kept model.
    private func removeDownloadMetadata(for model: WhisperModel) throws {
        try WhisperPaths.removeDownloadMetadata(variant: model.variant)
        storageRevision &+= 1
    }

    private func appTargets(for model: WhisperModel) -> [URL] {
        modelTargets(for: model, under: WhisperPaths.modelsDir)
    }

    private func legacyTargets(for model: WhisperModel) -> [URL] {
        let root = WhisperPaths.legacyModelsDir
        var targets = modelTargets(for: model, under: root)
        if model == .largeV3 {
            let repository = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            let oldUnquantizedFolder = repository.appendingPathComponent("openai_whisper-large-v3", isDirectory: true)
            // Remove only this abandoned partial folder. A complete unquantized large model
            // may belong to another WhisperKit app and is deliberately left alone.
            if !FileManager.default.fileExists(atPath: oldUnquantizedFolder.appendingPathComponent("AudioEncoder.mlmodelc").path) {
                targets.append(oldUnquantizedFolder)
                targets.append(repository.appendingPathComponent(".cache/huggingface/download/openai_whisper-large-v3", isDirectory: true))
            }
        }
        return targets
    }

    private func modelTargets(for model: WhisperModel, under root: URL) -> [URL] {
        let repository = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let tokenizerVariant = model == .largeV3 ? "large-v3" : model.variant
        return [
            repository.appendingPathComponent("openai_whisper-\(model.variant)", isDirectory: true),
            repository.appendingPathComponent(".cache/huggingface/download/openai_whisper-\(model.variant)", isDirectory: true),
            root.appendingPathComponent("models/openai/whisper-\(tokenizerVariant)", isDirectory: true)
        ]
    }

    private func pruneEmptyDirectories(startingAt directory: URL, root: URL) {
        let fm = FileManager.default
        var current = directory.standardizedFileURL
        while current.path.hasPrefix(root.path + "/"),
              (try? fm.contentsOfDirectory(atPath: current.path))?.isEmpty == true {
            try? fm.removeItem(at: current)
            current.deleteLastPathComponent()
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

    private func scan(for variant: String) -> URL? {
        Self.findModelFolder(variant: variant)
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
