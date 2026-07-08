import SwiftUI
import Combine
import AppKit
import NaturalLanguage

enum Lang: String, CaseIterable, Identifiable {
    case en = "EN"
    case ru = "RU"
    case de = "DE"
    case es = "ES"
    case fr = "FR"
    case it = "IT"
    case pt = "PT"
    case auto = "Auto Detect"
    var id: String { rawValue }

    /// Concrete translation languages (everything except Auto Detect).
    static var concreteCases: [Lang] { allCases.filter { $0 != .auto } }

    /// Short code shown in the compact Source/Target pickers ("RU", "EN", …).
    var code: String { self == .auto ? "AUTO" : rawValue }

    /// English name used in the LLM translation prompt.
    var englishName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Russian"
        case .de: return "German"
        case .es: return "Spanish"
        case .fr: return "French"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .auto: return "the detected source language"
        }
    }

    /// ISO code used by Whisper (nil for Auto → let Whisper detect).
    var whisperCode: String? {
        switch self {
        case .en: return "en"
        case .ru: return "ru"
        case .de: return "de"
        case .es: return "es"
        case .fr: return "fr"
        case .it: return "it"
        case .pt: return "pt"
        case .auto: return nil
        }
    }

    /// Speech-recognition locale id (used for dictation).
    var localeId: String {
        switch self {
        case .en: return "en-US"
        case .ru: return "ru-RU"
        case .de: return "de-DE"
        case .es: return "es-ES"
        case .fr: return "fr-FR"
        case .it: return "it-IT"
        case .pt: return "pt-PT"
        case .auto: return "en-US"
        }
    }

    /// Map a NaturalLanguage code to one of our supported languages.
    static func from(_ nl: NLLanguage) -> Lang? {
        switch nl {
        case .english: return .en
        case .russian: return .ru
        case .german: return .de
        case .spanish: return .es
        case .french: return .fr
        case .italian: return .it
        case .portuguese: return .pt
        default: return nil
        }
    }
}

enum AppScreen {
    case translator
    case settings
}

/// Three functional states of the API indicator.
enum APIStatus: Equatable {
    case offline    // no API key configured
    case exhausted  // token limit reached
    case online     // ready

    var color: Color {
        switch self {
        case .offline:   return Color.gray.opacity(0.7)          // gray (works in light & dark)
        case .exhausted: return Color(red: 0.92, green: 0.30, blue: 0.30) // red
        case .online:    return Color(red: 0.30, green: 0.85, blue: 0.46) // green
        }
    }

    var label: String {
        switch self {
        case .offline:   return "API Offline"
        case .exhausted: return "No Tokens"
        case .online:    return "API Online"
        }
    }
}

final class AppState: ObservableObject {

    // Navigation
    @Published var screen: AppScreen = .translator

    // Translation text
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var sourceLang: Lang = .ru
    @Published var targetLang: Lang = .en
    @Published var isTranslating: Bool = false
    @Published var isDictating: Bool = false
    @Published var errorMessage: String?

    /// The app that was frontmost when the selection was copied (e.g. a messenger).
    /// Used by "Insert translation" to paste the result back where it came from.
    private var sourceApp: NSRunningApplication?

    /// All configured API accounts (primary first, then secondary).
    var accounts: [ProviderConfig] {
        [
            ProviderConfig(slot: 0, provider: settings.provider, baseURL: settings.baseURL,
                           model: settings.model, apiKey: settings.apiKey),
            ProviderConfig(slot: 1, provider: settings.provider2, baseURL: settings.baseURL2,
                           model: settings.model2, apiKey: settings.apiKey2)
        ]
    }

    /// Provider currently active (the one that last worked / will be tried first).
    var activeProvider: APIProvider {
        settings.activeSlot == 1 ? settings.provider2 : settings.provider
    }

    /// Short label for the bottom indicator, e.g. "OpenAI" / "DeepSeek".
    var activeProviderName: String { activeProvider.rawValue }

    /// Computed API indicator state: gray (no key anywhere) → red (no tokens) → green (ok).
    var apiStatus: APIStatus {
        if !accounts.contains(where: { $0.hasKey }) { return .offline }
        if settings.tokensLimit > 0 && settings.tokensUsed >= settings.tokensLimit { return .exhausted }
        return .online
    }

    // Window state
    @Published var isPinned: Bool = false { didSet { onPinChanged?(isPinned) } }
    @Published var isDetached: Bool = false

    // Settings (mirrors SettingsStore, loaded on init)
    @Published var settings = SettingsStore.load()

    // Theming module (ThemeKit).
    let theme = AppTheme()

    // Trial / license
    @Published var licenseKey: String = Keychain.get(Keychain.license)
    private let trialStartKey = "babelbar.trialStart"
    private let trialDays = 7

    private var trialStartDate: Date {
        if let d = UserDefaults.standard.object(forKey: trialStartKey) as? Date { return d }
        let now = Date(); UserDefaults.standard.set(now, forKey: trialStartKey); return now
    }
    var trialDaysLeft: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        return max(0, trialDays - elapsed)
    }
    var isLicensed: Bool { !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var trialActive: Bool { trialDaysLeft > 0 }

    func activateLicense(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        licenseKey = k
        Keychain.set(k, for: Keychain.license)
    }

    // Callbacks wired by AppDelegate
    var onRequestShow: (() -> Void)?
    var onRequestToggle: (() -> Void)?
    var onRequestClose: (() -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCloseSettings: (() -> Void)?
    /// Show/hide the menu-bar status item (wired by AppDelegate).
    var onMenuBarVisibilityChanged: ((Bool) -> Void)?

    private let translator = TranslationService()

    init() {
        sourceLang = settings.sourceLang
        targetLang = settings.targetLang
        _ = trialStartDate   // stamp the trial start on first launch
        // Prewarm the local model in the background (on launch and after each download),
        // so the first dictation isn't stuck compiling/loading the CoreML model.
        dictationEngine.onPreparing = { ready in WhisperModelManager.shared.preparing = ready }
        Task { @MainActor [weak self] in
            WhisperModelManager.shared.onModelReady = { [weak self] in self?.preloadLocalModel() }
            self?.preloadLocalModel()
        }
    }

    /// Warm the local Whisper model ahead of time (only if local engine + model already on disk).
    func preloadLocalModel() {
        guard settings.speechEngine == .local else { return }
        let variant = settings.whisperModel.variant
        guard WhisperModelManager.isVariantOnDisk(variant) else { return }
        dictationEngine.preloadLocal(variant: variant)
    }

    // MARK: - Localization

    /// Localized UI string in the currently selected interface language.
    /// Reads `settings.interfaceLang`; since `settings` is @Published, switching the
    /// interface language re-renders every view live (no restart).
    func t(_ key: LKey) -> String { Loc.t(key, settings.interfaceLang) }

    /// Localized label for the API status indicator.
    func apiStatusLabel() -> String {
        switch apiStatus {
        case .offline:   return t(.apiOffline)
        case .exhausted: return t(.apiNoTokens)
        case .online:    return t(.apiOnline)
        }
    }

    // MARK: - Direction

    func swapDirection() {
        // Swap the two concrete sides; never produce X⇄X. Auto collapses to RU/EN.
        let newSource = concrete(targetLang)
        let newTarget = concrete(sourceLang)
        sourceLang = newSource
        targetLang = newTarget
        swap(&inputText, &outputText)
    }

    /// Maps .auto to a concrete RU/EN value (defaults to EN).
    private func concrete(_ lang: Lang) -> Lang { lang == .auto ? .en : lang }

    // MARK: - Translation

    /// Translate the top field into the bottom (default) or — when `reverse` is true — the
    /// edited bottom field back into the top, on the opposite language. Direction is auto-detected.
    func translate(reverse: Bool = false) {
        guard !isTranslating else { return }
        let source = reverse ? outputText : inputText
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Resolve direction from the configured language pair + detection of the actual text:
        //  • type anything → it becomes the Target language;
        //  • type in the Target language → translate it back to the Source/native side.
        let (src, tgt) = resolveDirection(for: text)
        sourceLang = src       // keep the indicator in sync with what we actually translate
        targetLang = tgt

        isTranslating = true
        errorMessage = nil
        // Clear the destination field so a stale previous result doesn't linger
        // under the loading spinner while the new translation is in flight.
        if reverse { inputText = "" } else { outputText = "" }
        let accounts = self.accounts
        let startIndex = settings.activeSlot
        let instructions = settings.aiInstructions
        Task {
            do {
                let result = try await translator.translate(
                    text: text, from: src, to: tgt, instructions: instructions,
                    accounts: accounts, startIndex: startIndex
                )
                await MainActor.run {
                    if reverse { self.inputText = result.text } else { self.outputText = result.text }
                    // Stick to whichever account actually served the request (failover).
                    if self.settings.activeSlot != result.usedSlot {
                        self.settings.activeSlot = result.usedSlot
                    }
                    if result.totalTokens > 0 {
                        self.settings.tokensUsed += result.totalTokens
                    }
                    SettingsStore.save(self.settings)
                    self.isTranslating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isTranslating = false
                }
            }
        }
    }

    /// Pick (from, to) for the given text, honoring the user's Source/Target preferences.
    /// Detection drives `from` (robust across languages); when the text is already in the
    /// Target language, we translate it back to the Source/native side instead.
    func resolveDirection(for text: String) -> (Lang, Lang) {
        let target = concrete(settings.targetLang)
        let native = (settings.sourceLang == .auto) ? .en : concrete(settings.sourceLang)
        let detected = detectLanguage(text) ?? native

        var from: Lang
        var to: Lang
        if detected == target {
            from = target
            to = (native == target) ? .en : native
        } else {
            from = detected
            to = target
        }
        if from == to { to = (from == .en) ? .ru : .en }   // never X⇄X
        return (from, to)
    }

    /// Detect the dominant language via NaturalLanguage, mapped to a supported `Lang`.
    /// Falls back to a Cyrillic-vs-Latin heuristic for very short/ambiguous input.
    func detectLanguage(_ text: String) -> Lang? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let nl = recognizer.dominantLanguage, let mapped = Lang.from(nl) {
            return mapped
        }
        let cyrillic = text.unicodeScalars.filter { $0.value >= 0x0400 && $0.value <= 0x04FF }.count
        let latin = text.unicodeScalars.filter { ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) }.count
        if cyrillic == 0 && latin == 0 { return nil }
        return cyrillic > latin ? .ru : .en
    }

    func clear() {
        inputText = ""
        outputText = ""
        errorMessage = nil
    }

    // MARK: - Voice dictation (record → Whisper → insert)

    private let dictationEngine = DictationEngine()

    /// Whisper language hint: the configured Source language, or nil (auto-detect) when Source = Auto.
    private func dictationLanguage() -> Lang? {
        settings.sourceLang == .auto ? nil : concrete(settings.sourceLang)
    }

    private func playTriggerSound() {
        if settings.voiceSoundEnabled {
            SystemSounds.play(settings.voiceSoundName, volume: Float(settings.voiceSoundVolume))
        }
    }

    /// In-app mic button (translator field): record → transcribe → fill field (+ translate).
    func toggleDictation() {
        if isDictating { stopDictation(); return }
        dictationEngine.requestMic { [weak self] granted in
            guard let self else { return }
            guard granted else { self.errorMessage = self.t(.errMicSpeech); return }
            self.errorMessage = nil
            self.inputText = ""
            do {
                try self.dictationEngine.start(duckAudio: self.settings.duckAudio)
                self.isDictating = true
                self.playTriggerSound()
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func stopDictation(translate runTranslate: Bool = true) {
        guard isDictating else { return }
        isDictating = false
        dictationEngine.finish(settings: settings, language: dictationLanguage()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                self.inputText = text
                if runTranslate, !text.isEmpty { self.translate() }
            case .failure(let e):
                self.errorMessage = e.localizedDescription
            }
        }
    }

    // MARK: - Global voice shortcuts (dictate at cursor / voice→translate)

    func startCursorDictation() {
        dictationEngine.requestMic { [weak self] ok in
            guard let self else { return }
            guard ok else { self.errorMessage = self.t(.errMicSpeech); return }
            do {
                try self.dictationEngine.start(duckAudio: self.settings.duckAudio)
                self.playTriggerSound()
                MicLevel.shared.showDot = self.settings.showRecordingDot
                RecordingOverlay.shared.show()
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func stopCursorDictation() {
        // Overlay stays up through transcription (showing a loader), then we insert at the cursor.
        RecordingOverlay.shared.setProcessing(true)
        dictationEngine.finish(settings: settings, language: dictationLanguage()) { [weak self] result in
            guard let self else { return }
            RecordingOverlay.shared.hide()
            switch result {
            case .success(let text) where !text.isEmpty:
                TextInserter.insert(text, method: self.settings.insertMethod)
            case .failure(let e):
                self.errorMessage = e.localizedDescription
            default:
                break
            }
        }
    }

    // MARK: - Global voice→translate→insert (Shift+Fn)

    /// Start dictation for the "speak → translate → type at cursor" shortcut.
    /// Identical capture to `startCursorDictation`; only the stop handler differs (it translates).
    func startCursorTranslateDictation() {
        dictationEngine.requestMic { [weak self] ok in
            guard let self else { return }
            guard ok else { self.errorMessage = self.t(.errMicSpeech); return }
            do {
                try self.dictationEngine.start(duckAudio: self.settings.duckAudio)
                self.playTriggerSound()
                MicLevel.shared.showDot = self.settings.showRecordingDot
                RecordingOverlay.shared.show()
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    /// Stop recording, transcribe, translate to the configured language in the background,
    /// then type the translation at the cursor. The overlay stays up (loader) until the
    /// translation lands so the user sees it's still working.
    func stopCursorTranslateDictation() {
        RecordingOverlay.shared.setProcessing(true)
        dictationEngine.finish(settings: settings, language: dictationLanguage()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text) where !text.isEmpty:
                self.translateForCursor(text)        // keeps the overlay up until the result is typed
            case .failure(let e):
                RecordingOverlay.shared.hide()
                self.errorMessage = e.localizedDescription
            default:
                RecordingOverlay.shared.hide()
            }
        }
    }

    /// Translate dictated text (direction resolved like the main field) and type it at the cursor.
    private func translateForCursor(_ text: String) {
        let (src, tgt) = resolveDirection(for: text)
        let accounts = self.accounts
        let startIndex = settings.activeSlot
        let instructions = settings.aiInstructions
        Task {
            do {
                let result = try await translator.translate(
                    text: text, from: src, to: tgt, instructions: instructions,
                    accounts: accounts, startIndex: startIndex
                )
                await MainActor.run {
                    RecordingOverlay.shared.hide()
                    if self.settings.activeSlot != result.usedSlot { self.settings.activeSlot = result.usedSlot }
                    if result.totalTokens > 0 { self.settings.tokensUsed += result.totalTokens }
                    SettingsStore.save(self.settings)
                    TextInserter.insert(result.text, method: self.settings.insertMethod)
                }
            } catch {
                await MainActor.run {
                    RecordingOverlay.shared.hide()
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Hotkey-driven actions

    func handleTranslateSelection() {
        // Remember where the text came from (still frontmost at this point) so the
        // "Insert translation" button can paste the result back into it.
        sourceApp = NSWorkspace.shared.frontmostApplication
        // The user just pressed ⌘C twice — their selection is already on the pasteboard.
        // Read it directly; no need to inject a synthetic ⌘C (which requires Accessibility
        // and can silently fail).
        let text = ClipboardHelper.read().trimmingCharacters(in: .whitespacesAndNewlines)
        onRequestShow?()
        guard !text.isEmpty else { return }
        inputText = text
        translate()   // direction is auto-detected inside translate()
    }

    /// True when we know which app to paste the translation back into.
    var canInsertTranslation: Bool {
        sourceApp != nil && !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Copies the translation, brings the source app forward and pastes (⌘V) — replacing
    /// the originally-selected text with its translation. Requires Accessibility permission.
    func insertTranslation() {
        let translation = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { return }
        ClipboardHelper.copy(translation)

        // Hide our UI so focus returns to the source app.
        onRequestClose?()
        sourceApp?.activate(options: [.activateIgnoringOtherApps])

        // Give the activation a moment to land before posting the paste.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            ClipboardHelper.paste()
        }
    }

    /// OCR languages, prioritized by the configured pair, then the rest of the supported set.
    private func ocrLanguages() -> [String] {
        var ordered: [String] = []
        if settings.sourceLang != .auto { ordered.append(concrete(settings.sourceLang).localeId) }
        let tgt = concrete(settings.targetLang).localeId
        if !ordered.contains(tgt) { ordered.append(tgt) }
        for l in Lang.concreteCases where !ordered.contains(l.localeId) { ordered.append(l.localeId) }
        return ordered
    }

    func handleScreenshotTranslate() {
        Task {
            guard let text = await ScreenCapture.captureAndRecognize(languages: ocrLanguages()) else { return }
            await MainActor.run {
                self.onRequestShow?()
                self.inputText = text
                self.translate()
            }
        }
    }

    func saveSettings() {
        // Source/Target are edited directly on `settings` via the Language Preferences pickers.
        SettingsStore.save(settings)
        // Reflect the configured pair in the live indicator (a translation refines it later).
        sourceLang = settings.sourceLang
        targetLang = concrete(settings.targetLang)
        // Keep the voice hotkey detector's cached bindings in sync with edited combos.
        VoiceHotkeys.shared.refreshBindings()
        // Warm the local model if the user just switched to local / changed the model.
        preloadLocalModel()
    }

    /// Reset every setting (and the theme) back to factory defaults, then persist and re-apply.
    func resetToDefaults() {
        settings = AppSettings()
        SettingsStore.save(settings)
        theme.config = ThemeConfig()                 // didSet persists + reapplies the theme
        theme.installFor(appearance: settings.appearance)
        sourceLang = settings.sourceLang
        targetLang = concrete(settings.targetLang)
        HotKeyManager.shared.reload()
        VoiceHotkeys.shared.refreshBindings()
        MicLevel.shared.showDot = settings.showRecordingDot
        errorMessage = nil
    }

    // MARK: - GitHub (star card + updates)

    /// The GitHub repository backing the star card and the update check.
    static let repoOwner = "Clleo"
    static let repoName  = "BabelBar"
    static var repoURL: URL { URL(string: "https://github.com/\(repoOwner)/\(repoName)")! }

    /// The app's marketing version (CFBundleShortVersionString), e.g. "1.0.2".
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Live star count for the repo (nil until loaded).
    @Published var githubStars: Int? = nil
    /// Avatar URLs of a few stargazers, shown in the card.
    @Published var stargazerAvatars: [URL] = []

    /// Result of the latest update check.
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }
    @Published var updateState: UpdateState = .idle

    /// Fetch the repo's star count and a handful of stargazer avatars for the card.
    func loadGitHubInfo() {
        let api = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)"
        if let url = URL(string: api) {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let stars = json["stargazers_count"] as? Int else { return }
                DispatchQueue.main.async { self?.githubStars = stars }
            }.resume()
        }
        if let url = URL(string: api + "/stargazers?per_page=5") {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                guard let data,
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
                let urls = arr.compactMap { ($0["avatar_url"] as? String).flatMap(URL.init) }
                DispatchQueue.main.async { self?.stargazerAvatars = urls }
            }.resume()
        }
    }

    /// Query the latest GitHub release and compare it with the running version.
    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking
        let api = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: api) else { updateState = .failed; return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settings.lastUpdateCheck = Date()
                // Persist directly — saveSettings() would also reset the live language
                // indicator, reload hotkey bindings and re-preload the Whisper model.
                SettingsStore.save(self.settings)
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let htmlStr = json["html_url"] as? String,
                      let htmlURL = URL(string: htmlStr) else {
                    self.updateState = .failed
                    return
                }
                let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                if Self.isVersion(latest, newerThan: self.appVersion) {
                    self.updateState = .available(version: latest, url: htmlURL)
                } else {
                    self.updateState = .upToDate
                }
            }
        }.resume()
    }

    /// Numeric dot-separated version comparison ("1.2" vs "1.10"), missing fields treated as 0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
