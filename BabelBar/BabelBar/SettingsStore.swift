import Foundation

enum APIProvider: String, CaseIterable, Identifiable, Codable {
    case openai = "OpenAI"
    case deepseek = "DeepSeek"
    case zai = "z.ai"
    case anthropic = "Claude"
    case groq = "Groq"
    case custom = "Custom"
    var id: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .openai:    return "https://api.openai.com/v1"
        case .deepseek:  return "https://api.deepseek.com/v1"
        case .zai:       return "https://api.z.ai/api/paas/v4"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .groq:      return "https://api.groq.com/openai/v1"
        case .custom:    return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:    return "gpt-4o-mini"
        case .deepseek:  return "deepseek-chat"
        case .zai:       return "glm-4.6"
        case .anthropic: return "claude-sonnet-4-6"
        case .groq:      return "llama-3.3-70b-versatile"
        case .custom:    return "gpt-4o-mini"
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
    var id: String { rawValue }
}

/// Which speech-to-text engine powers dictation.
enum SpeechEngine: String, CaseIterable, Identifiable, Codable {
    case local   // WhisperKit, on-device (downloads a model)
    case remote  // cloud Whisper API (OpenAI-compatible /audio/transcriptions)
    var id: String { rawValue }
}

/// WhisperKit local model variants offered to the user (name + approx download size).
enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case base, small, largeV3 = "large-v3"
    var id: String { rawValue }
    /// Exact WhisperKit model name (the HF repo folder, minus the "openai_whisper-" prefix).
    /// Plain "large-v3" is the uncompressed ~3 GB model — we use the compressed 626 MB build.
    var variant: String {
        switch self {
        case .base:    return "base"
        case .small:   return "small"
        case .largeV3: return "large-v3-v20240930_626MB"
        }
    }
    var approxMB: Int { switch self { case .base: 145; case .small: 480; case .largeV3: 626 } }
    var label: String { rawValue }
}

/// How recognized text is inserted into the frontmost app.
enum InsertMethod: String, CaseIterable, Identifiable, Codable {
    case paste   // clipboard + ⌘V with save/restore (robust)
    case type    // synthesize per-character keystrokes (no clipboard touch)
    var id: String { rawValue }
}

struct AppSettings: Codable {
    var appearance: Appearance = .dark
    var interfaceLang: UILanguage = .en
    var sourceLang: Lang = .ru
    var targetLang: Lang = .en
    // Primary API account.
    var provider: APIProvider = .openai
    var baseURL: String = APIProvider.openai.defaultBaseURL
    var model: String = APIProvider.openai.defaultModel
    var apiKey: String = ""

    // Secondary API account (automatic fallback when the primary fails / runs out of balance).
    var provider2: APIProvider = .deepseek
    var baseURL2: String = APIProvider.deepseek.defaultBaseURL
    var model2: String = APIProvider.deepseek.defaultModel
    var apiKey2: String = ""

    /// Which account is currently active (0 = primary, 1 = secondary). Sticks to the one
    /// that last worked.
    var activeSlot: Int = 0

    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true

    // Updates
    var autoCheckUpdates: Bool = true
    var lastUpdateCheck: Date? = nil

    var aiInstructions: String = "Write your translations using professional vocabulary and tone.\nAvoid slang unless explicitly present in source text."
    var tokensUsed: Int = 0
    var tokensLimit: Int = 500_000

    // Configurable hotkeys.
    var openHotKey = KeyCombo(keyCode: 49, command: false, shift: false, option: true)       // ⌥ Space
    var selectionHotKey = KeyCombo(keyCode: 8, command: true)                                 // ⌘ C (double-tap)
    var screenshotHotKey = KeyCombo(keyCode: 19, command: true, shift: true)                  // ⇧ ⌘ 2

    // Voice shortcuts (modifier-only, e.g. Fn / Shift+Fn).
    var dictateHotkey = ModifierCombo(fn: true)                 // dictate at cursor
    var translateDictateHotkey = ModifierCombo(fn: true, shift: true)  // dictate → translate → insert at cursor
    var voiceInputEnabled = true    // master switch for the whole voice-input feature
    var voiceSoundEnabled = true
    var voiceSoundName = "Pop"
    var voiceSoundVolume: Double = 0.8
    var showRecordingDot = true     // red dot next to the recording waveform (loader unaffected)
    var duckAudio = true            // lower system output volume while dictating (mic clarity)

    // Speech-to-text engine selection.
    var speechEngine: SpeechEngine = .local
    var whisperModel: WhisperModel = .base
    var insertMethod: InsertMethod = .paste
    var whisperCleanup = false          // run an LLM "auto-edit" pass over the raw transcript
    // Remote (cloud) Whisper transcription account (separate from the text-translation API).
    var transcriptionBaseURL = "https://api.groq.com/openai/v1"
    var transcriptionModel = "whisper-large-v3"
    var transcriptionAPIKey = ""

    // NOTE: the secret fields (apiKey, apiKey2, transcriptionAPIKey) are intentionally NOT in
    // CodingKeys — they are stored in the Keychain by SettingsStore, never in the UserDefaults JSON.
    enum CodingKeys: String, CodingKey {
        case appearance, interfaceLang, sourceLang, targetLang, provider, baseURL, model, aiInstructions, tokensUsed, tokensLimit
        case provider2, baseURL2, model2, activeSlot, launchAtLogin
        case showMenuBarIcon, autoCheckUpdates, lastUpdateCheck
        case openHotKey, selectionHotKey, screenshotHotKey
        case dictateHotkey, translateDictateHotkey, voiceInputEnabled, voiceSoundEnabled, voiceSoundName, voiceSoundVolume, showRecordingDot, duckAudio
        case speechEngine, whisperModel, insertMethod, whisperCleanup
        case transcriptionBaseURL, transcriptionModel
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? c.decode(Appearance.self, forKey: .appearance)) ?? .dark
        interfaceLang = (try? c.decode(UILanguage.self, forKey: .interfaceLang)) ?? .en
        sourceLang = (try? c.decode(Lang.self, forKey: .sourceLang)) ?? .ru
        targetLang = (try? c.decode(Lang.self, forKey: .targetLang)) ?? .en
        provider = (try? c.decode(APIProvider.self, forKey: .provider)) ?? .openai
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? APIProvider.openai.defaultBaseURL
        model = (try? c.decode(String.self, forKey: .model)) ?? APIProvider.openai.defaultModel
        aiInstructions = (try? c.decode(String.self, forKey: .aiInstructions)) ?? AppSettings().aiInstructions
        tokensUsed = (try? c.decode(Int.self, forKey: .tokensUsed)) ?? 0
        tokensLimit = (try? c.decode(Int.self, forKey: .tokensLimit)) ?? 500_000
        // apiKey / apiKey2 / transcriptionAPIKey are loaded from the Keychain in SettingsStore.load().
        provider2 = (try? c.decode(APIProvider.self, forKey: .provider2)) ?? .deepseek
        baseURL2 = (try? c.decode(String.self, forKey: .baseURL2)) ?? APIProvider.deepseek.defaultBaseURL
        model2 = (try? c.decode(String.self, forKey: .model2)) ?? APIProvider.deepseek.defaultModel
        activeSlot = (try? c.decode(Int.self, forKey: .activeSlot)) ?? 0
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        showMenuBarIcon = (try? c.decode(Bool.self, forKey: .showMenuBarIcon)) ?? true
        autoCheckUpdates = (try? c.decode(Bool.self, forKey: .autoCheckUpdates)) ?? true
        lastUpdateCheck = try? c.decode(Date.self, forKey: .lastUpdateCheck)
        openHotKey = (try? c.decode(KeyCombo.self, forKey: .openHotKey)) ?? AppSettings().openHotKey
        selectionHotKey = (try? c.decode(KeyCombo.self, forKey: .selectionHotKey)) ?? AppSettings().selectionHotKey
        screenshotHotKey = (try? c.decode(KeyCombo.self, forKey: .screenshotHotKey)) ?? AppSettings().screenshotHotKey
        dictateHotkey = (try? c.decode(ModifierCombo.self, forKey: .dictateHotkey)) ?? AppSettings().dictateHotkey
        translateDictateHotkey = (try? c.decode(ModifierCombo.self, forKey: .translateDictateHotkey)) ?? AppSettings().translateDictateHotkey
        voiceSoundEnabled = (try? c.decode(Bool.self, forKey: .voiceSoundEnabled)) ?? true
        voiceSoundName = (try? c.decode(String.self, forKey: .voiceSoundName)) ?? "Pop"
        voiceInputEnabled = (try? c.decode(Bool.self, forKey: .voiceInputEnabled)) ?? true
        voiceSoundVolume = (try? c.decode(Double.self, forKey: .voiceSoundVolume)) ?? 0.8
        showRecordingDot = (try? c.decode(Bool.self, forKey: .showRecordingDot)) ?? true
        duckAudio = (try? c.decode(Bool.self, forKey: .duckAudio)) ?? true
        speechEngine = (try? c.decode(SpeechEngine.self, forKey: .speechEngine)) ?? .local
        whisperModel = (try? c.decode(WhisperModel.self, forKey: .whisperModel)) ?? .base
        insertMethod = (try? c.decode(InsertMethod.self, forKey: .insertMethod)) ?? .paste
        whisperCleanup = (try? c.decode(Bool.self, forKey: .whisperCleanup)) ?? false
        transcriptionBaseURL = (try? c.decode(String.self, forKey: .transcriptionBaseURL)) ?? "https://api.groq.com/openai/v1"
        transcriptionModel = (try? c.decode(String.self, forKey: .transcriptionModel)) ?? "whisper-large-v3"
    }
}

// Lang Codable conformance
extension Lang: Codable {}

enum SettingsStore {
    private static let key = "babelbar.settings"
    private static let demoBaselineKey = "babelbar.demoBaselineRemoved"
    private static let demoBaseline = 124_500

    static func load() -> AppSettings {
        let hadSaved = UserDefaults.standard.data(forKey: key) != nil
        var s: AppSettings
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            s = decoded
        } else {
            UserDefaults.standard.set(true, forKey: demoBaselineKey)
            s = AppSettings()
        }
        // Secrets live in the Keychain, not the UserDefaults JSON.
        s.apiKey = Keychain.get(Keychain.apiKey)
        s.apiKey2 = Keychain.get(Keychain.apiKey2)
        s.transcriptionAPIKey = Keychain.get(Keychain.transcriptionAPIKey)
        // One-time cleanup: earlier builds seeded tokensUsed with a fake 124 500 demo value.
        if hadSaved, !UserDefaults.standard.bool(forKey: demoBaselineKey) {
            if s.tokensUsed >= demoBaseline { s.tokensUsed -= demoBaseline }
            UserDefaults.standard.set(true, forKey: demoBaselineKey)
            save(s)
        }
        return s
    }

    static func save(_ settings: AppSettings) {
        // Secrets → Keychain; everything else → UserDefaults JSON (keys excluded via CodingKeys).
        Keychain.set(settings.apiKey, for: Keychain.apiKey)
        Keychain.set(settings.apiKey2, for: Keychain.apiKey2)
        Keychain.set(settings.transcriptionAPIKey, for: Keychain.transcriptionAPIKey)
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
