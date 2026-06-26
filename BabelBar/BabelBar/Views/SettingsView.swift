import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showSecondaryProvider = false
    @State private var permRefresh = 0   // bump to re-read permission states
    @State private var keyField = ""
    @ObservedObject private var models = WhisperModelManager.shared

    // AI Instructions text area — user-resizable by dragging its bottom-right corner.
    @State private var aiHeight: CGFloat = 64
    @State private var aiDragStart: CGFloat? = nil

    @State private var showResetConfirm = false
    @State private var resetHover = false

    private let labelFont = Font.system(size: 12)
    private let fieldWidth: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header — content scrolls beneath it.
            header
                .padding(.bottom, 6)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 15) {
                    githubCard
                    licenseSettings
                    appSettings
                    updatesSettings
                    permissionsSettings
                    voiceSettings
                    apiSettings
                    themeSettings
                }
                .padding(.vertical, 2)   // tiny inset so the rounded clip doesn't crop cards
            }
            .scrollIndicators(.never)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))   // rounded scroll viewport

            // Fixed footer — the Save button stays visible regardless of scroll position.
            saveButton
                .padding(.top, 14)
        }
        .onAppear {
            if !state.settings.apiKey2.trimmingCharacters(in: .whitespaces).isEmpty {
                showSecondaryProvider = true
            }
            // Reflect the real login-item state (user may have changed it in System Settings).
            state.settings.launchAtLogin = LoginItem.isEnabled
            // Load the GitHub star card data, and silently check for updates if enabled.
            state.loadGitHubInfo()
            if state.settings.autoCheckUpdates && state.updateState == .idle {
                state.checkForUpdates()
            }
        }
    }

    // MARK: - GITHUB STAR CARD

    private var githubCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accentBlue)
                Button {
                    NSWorkspace.shared.open(AppState.repoURL)
                } label: {
                    Text("\(AppState.repoOwner)/\(AppState.repoName)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.accentBlue)
                }
                .buttonStyle(.plain)

                Spacer()

                // Star count badge — "★ 2 006 stars", like the FreeFlow mockup
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 11))
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.20))
                    Text(state.githubStars.map { formatted($0) } ?? "—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(state.t(.starsWord))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassPanel(corner: 10)

                // Star button → opens the repo page
                GlassButton(title: state.t(.githubStar), systemIcon: "star") {
                    NSWorkspace.shared.open(AppState.repoURL)
                }
            }

            if !state.stargazerAvatars.isEmpty {
                Divider().background(Theme.panelStroke)
                HStack(spacing: 8) {
                    HStack(spacing: -8) {
                        ForEach(state.stargazerAvatars.prefix(5), id: \.self) { url in
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.08))
                            }
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.panel, lineWidth: 2))
                        }
                    }
                    Text(state.t(.recentlyStarred))
                        .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    // MARK: - UPDATES

    private var updatesSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(state.t(.secUpdates), "arrow.triangle.2.circlepath", rowSpacing: 14)

            row(state.t(.autoCheckUpdates)) {
                CapsuleToggle(isOn: Binding(
                    get: { state.settings.autoCheckUpdates },
                    set: { state.settings.autoCheckUpdates = $0; state.saveSettings() }
                ))
            }

            HStack(spacing: 12) {
                let checking = state.updateState == .checking
                GlassButton(
                    title: checking ? state.t(.checkingUpdates) : state.t(.checkForUpdatesNow),
                    busy: checking
                ) { state.checkForUpdates() }
                .disabled(checking)

                updateStatus

                Spacer()
            }

            Text(lastCheckedText)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    /// Inline result of the last update check, shown next to the button.
    @ViewBuilder
    private var updateStatus: some View {
        switch state.updateState {
        case .upToDate:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                    .foregroundColor(Theme.accentGreen)
                Text(state.t(.updateUpToDate)).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }
        case let .available(version, url):
            HStack(spacing: 8) {
                Text(String(format: state.t(.updateAvailableFmt), version))
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textPrimary)
                GlassButton(title: state.t(.updateDownload), systemIcon: "arrow.down.circle") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .failed:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                    .foregroundColor(.orange)
                Text(state.t(.updateFailed)).font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }
        case .idle, .checking:
            EmptyView()
        }
    }

    /// "Last checked: <date>" — or "Never" when no check has run yet.
    private var lastCheckedText: String {
        let prefix = state.t(.lastChecked)
        guard let date = state.settings.lastUpdateCheck else {
            return "\(prefix): \(state.t(.neverChecked))"
        }
        return "\(prefix): \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - LICENSE

    /// App version shown in the License card header — reads CFBundleShortVersionString,
    /// which is wired to MARKETING_VERSION, so it always matches the current release.
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var licenseSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(state.t(.secLicense), "sparkles", rowSpacing: 16)
                Spacer()
                Text("v\(appVersion)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            if state.isLicensed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.accentGreen)
                    Text(state.t(.activated)).font(labelFont).foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(maskedKey(state.licenseKey))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
            } else if state.trialActive {
                HStack(spacing: 8) {
                    Text(state.t(.freeTrial)).font(labelFont).foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(String(format: state.t(.daysLeftFmt), state.trialDaysLeft))
                        .font(labelFont).foregroundColor(Theme.textSecondary)
                }
                licenseField
            } else {
                Text(state.t(.trialEnded))
                    .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                licenseField
            }
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    private var licenseField: some View {
        HStack(spacing: 8) {
            TextField(state.t(.enterLicenseKey), text: $keyField)
                .textFieldStyle(.plain).fieldStyle(fieldWidth)
                .onSubmit { state.activateLicense(keyField) }
            HoverTextButton(title: state.t(.activate)) { state.activateLicense(keyField) }
        }
    }

    private func maskedKey(_ k: String) -> String {
        guard k.count > 4 else { return String(repeating: "•", count: k.count) }
        return String(repeating: "•", count: max(0, k.count - 4)) + k.suffix(4)
    }

    // MARK: - SPEECH (recognition engine)

    private var engineBinding: Binding<SpeechEngine> {
        Binding(get: { state.settings.speechEngine },
                set: { state.settings.speechEngine = $0; state.saveSettings() })
    }
    private var modelBinding: Binding<WhisperModel> {
        Binding(get: { state.settings.whisperModel },
                set: { state.settings.whisperModel = $0; state.saveSettings() })
    }
    private var insertBinding: Binding<InsertMethod> {
        Binding(get: { state.settings.insertMethod },
                set: { state.settings.insertMethod = $0; state.saveSettings() })
    }

    /// Master ON/OFF for the whole voice feature. Off → hotkeys stop, content collapses.
    private var voiceHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accentBlue)
            Text(state.t(.secVoice))
                .font(.system(size: 11, weight: .bold)).tracking(1.3)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text("ON / OFF")
                .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            CapsuleToggle(isOn: Binding(
                get: { state.settings.voiceInputEnabled },
                set: { state.settings.voiceInputEnabled = $0; state.saveSettings()
                       VoiceHotkeys.shared.refreshBindings() }   // stop/resume global listening
            ))
        }
    }

    private var speechSubsection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(state.t(.secSpeech), "waveform", rowSpacing: 16)

            row(state.t(.recognition), help: state.t(.tipSpeechEngine)) {
                CapsuleSegmented(selection: engineBinding, options: [.local, .remote],
                                 title: { $0 == .local ? state.t(.engineLocal) : state.t(.engineRemote) })
                    .frame(width: 200)
            }

            if state.settings.speechEngine == .local {
                row(state.t(.model), help: state.t(.tipModelDownload)) {
                    CapsulePicker(selection: modelBinding, options: WhisperModel.allCases,
                                  title: { "\($0.label) · \($0.approxMB) MB" }, width: 200)
                }
                modelDownloadRow
            } else {
                row(state.t(.apiKey)) {
                    SecureField("gsk-…", text: $state.settings.transcriptionAPIKey)
                        .textFieldStyle(.plain).fieldStyle(fieldWidth)
                }
                row(state.t(.baseURL)) {
                    TextField("https://api.groq.com/openai/v1", text: $state.settings.transcriptionBaseURL)
                        .textFieldStyle(.plain).fieldStyle(fieldWidth)
                }
                row(state.t(.model)) {
                    TextField("whisper-large-v3", text: $state.settings.transcriptionModel)
                        .textFieldStyle(.plain).fieldStyle(fieldWidth)
                }
                Text(state.t(.remoteNote))
                    .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
            }

            row(state.t(.insertion), help: state.t(.tipInsertMethod)) {
                CapsuleSegmented(selection: insertBinding, options: [.paste, .type],
                                 title: { $0 == .paste ? state.t(.insertPaste) : state.t(.insertType) })
                    .frame(width: 200)
            }
        }
    }

    @ViewBuilder private var modelDownloadRow: some View {
        let m = state.settings.whisperModel
        HStack(spacing: 6) {
            if models.downloading == m {
                ProgressView(value: models.progress).frame(width: 140)
                Text("\(Int(models.progress * 100))%")
                    .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                HoverTextButton(title: state.t(.cancel)) { models.cancelDownload() }
            } else if models.preparing && models.isDownloaded(m) {
                ProgressView().controlSize(.small)
                Text(state.t(.initializing)).font(labelFont).foregroundColor(Theme.textSecondary)
            } else if models.isDownloaded(m) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accentGreen)
                Text("\(state.t(.downloaded)) · \(models.diskSize(m) ?? "\(m.approxMB) MB")")
                    .font(labelFont).foregroundColor(Theme.textSecondary)
                HoverIconButton(systemName: "trash", size: 12) { models.delete(m) }
            } else {
                HoverTextButton(title: "\(state.t(.download)) · \(m.approxMB) MB") { models.download(m) }
            }
            Spacer()
        }
    }

    // MARK: - VOICE

    private var voiceSettings: some View {
        let enabled = state.settings.voiceInputEnabled
        return VStack(alignment: .leading, spacing: 16) {
            voiceHeader
                .padding(.bottom, enabled ? Self.titleToContentGap - 16 : 0)

            if enabled {
                voiceRows
                speechSubsection
            }
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    @ViewBuilder private var voiceRows: some View {
            row(state.t(.dictateToCursor),
                help: state.t(.tipDictate)) {
                ModifierComboRecorder(combo: $state.settings.dictateHotkey, recordingPrompt: state.t(.recordModifiers)) { state.saveSettings() }
            }
            row(state.t(.showRecordingDot), help: state.t(.tipShowRecordingDot)) {
                CapsuleToggle(isOn: Binding(
                    get: { state.settings.showRecordingDot },
                    set: { state.settings.showRecordingDot = $0; state.saveSettings()
                           MicLevel.shared.showDot = $0 }
                ))
            }
            row(state.t(.duckAudio), help: state.t(.tipDuckAudio)) {
                CapsuleToggle(isOn: Binding(
                    get: { state.settings.duckAudio },
                    set: { state.settings.duckAudio = $0; state.saveSettings() }
                ))
            }
            row(state.t(.triggerSound)) {
                HStack(spacing: 10) {
                    // Volume
                    GlowOrbSlider(
                        value: Binding(
                            get: { state.settings.voiceSoundVolume },
                            set: { state.settings.voiceSoundVolume = $0; state.saveSettings() }
                        ),
                        range: 0...1,
                        onEditingChanged: { editing in
                            if !editing { SystemSounds.play(state.settings.voiceSoundName, volume: Float(state.settings.voiceSoundVolume)) }
                        }
                    )
                    .frame(width: 90)
                    .disabled(!state.settings.voiceSoundEnabled)

                    // Sound choice
                    CapsulePicker(selection: Binding(
                        get: { state.settings.voiceSoundName },
                        set: { state.settings.voiceSoundName = $0; state.saveSettings(); SystemSounds.play($0, volume: Float(state.settings.voiceSoundVolume)) }
                    ), options: SystemSounds.names, title: { $0 }, width: 110)
                    .disabled(!state.settings.voiceSoundEnabled)

                    // On / off
                    CapsuleToggle(isOn: Binding(
                        get: { state.settings.voiceSoundEnabled },
                        set: { state.settings.voiceSoundEnabled = $0; state.saveSettings(); if $0 { SystemSounds.play(state.settings.voiceSoundName, volume: Float(state.settings.voiceSoundVolume)) } }
                    ))
                }
            }
    }

    // MARK: - PERMISSIONS

    private var permissionsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(state.t(.secPermissions), "lock.shield.fill", rowSpacing: 16)
            permissionRow(state.t(.permAccessibility), icon: "accessibility", granted: Permissions.accessibility(), kind: .accessibility)
            permissionRow(state.t(.permInput), icon: "keyboard", granted: Permissions.inputMonitoring(), kind: .inputMonitoring)
            permissionRow(state.t(.permScreen), icon: "rectangle.dashed", granted: Permissions.screenRecording(), kind: .screenRecording)
            permissionRow(state.t(.permMic), icon: "mic", granted: Permissions.microphone(), kind: .microphone)
        }
        .padding(20)
        .glassPanel(corner: 16)
        .id(permRefresh)
        .onAppear { permRefresh &+= 1 }
    }

    private func permissionRow(_ title: String, icon: String, granted: Bool, kind: Permissions.Kind) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 20, alignment: .center)
            Text(title).font(labelFont).foregroundColor(Theme.textPrimary)
            Spacer()
            PermissionPill(granted: granted,
                           grantedText: state.t(.granted),
                           actionText: state.t(.openSettings)) { Permissions.openSettings(kind) }
        }
        .frame(minHeight: Self.rowHeight)
    }

    // MARK: - THEME SETTINGS (reusable module)

    private var themeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(state.t(.secTheme), "paintpalette.fill", rowSpacing: 16)
            ThemeEditorView(theme: state.theme, appearance: appearanceBinding)
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    /// Sets the appearance AND re-skins synchronously, so the rebuild that follows reads the
    /// correct palette (otherwise switching dark/light shows the old colors for one frame).
    private func setAppearance(_ a: Appearance) {
        state.settings.appearance = a
        state.theme.installFor(appearance: a)
    }

    private var appearanceBinding: Binding<Appearance> {
        Binding(get: { state.settings.appearance }, set: { setAppearance($0) })
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(state.t(.settingsTitle))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(state.apiStatus.color).frame(width: 6, height: 6)
                Text(state.apiStatusLabel()).font(.system(size: 10)).foregroundColor(Theme.textPrimary)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .glassPanel(corner: 12)

            IconButton(systemName: "xmark") { state.onCloseSettings?() }
        }
        .frame(height: 22)
    }

    // MARK: - APP SETTINGS

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(state.t(.secApp), "gearshape.fill", rowSpacing: 16)

            row(state.t(.launchAtLogin)) {
                CapsuleToggle(isOn: Binding(
                    get: { state.settings.launchAtLogin },
                    set: { state.settings.launchAtLogin = $0; LoginItem.set($0) }
                ))
            }

            row(state.t(.showMenuBarIcon)) {
                CapsuleToggle(isOn: Binding(
                    get: { state.settings.showMenuBarIcon },
                    set: { state.settings.showMenuBarIcon = $0; state.saveSettings(); state.onMenuBarVisibilityChanged?($0) }
                ))
            }

            row(state.t(.openBabelBar),
                help: state.t(.tipOpen)) {
                HotKeyRecorder(combo: $state.settings.openHotKey, recordingPrompt: state.t(.recordKeys), onChange: applyHotKeys)
            }
            row(state.t(.translateAuto),
                help: state.t(.tipTranslateAuto)) {
                HotKeyRecorder(combo: $state.settings.selectionHotKey, doubleTap: true, recordingPrompt: state.t(.recordKeys), onChange: applyHotKeys)
            }
            row(state.t(.translateScreenshot),
                help: state.t(.tipScreenshot)) {
                HotKeyRecorder(combo: $state.settings.screenshotHotKey, recordingPrompt: state.t(.recordKeys), onChange: applyHotKeys)
            }

            row(state.t(.interfaceLanguage)) {
                CapsulePicker(selection: Binding(
                    get: { state.settings.interfaceLang },
                    set: { state.settings.interfaceLang = $0; state.saveSettings() }
                ), options: UILanguage.allCases, title: { $0.endonym }, width: 200)
            }

            row(state.t(.languagePreferences)) {
                HStack(spacing: 10) {
                    langPicker(.source, selection: sourceBinding, options: Lang.allCases)
                    langPicker(.target, selection: targetBinding, options: Lang.concreteCases)
                }
            }
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    // MARK: - API SETTINGS

    private var apiSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(state.t(.secAPI), "network", rowSpacing: 16)

            apiAccount(state.t(.apiPrimary),
                       provider: $state.settings.provider,
                       baseURL: $state.settings.baseURL,
                       model: $state.settings.model,
                       apiKey: $state.settings.apiKey)

            // Secondary provider — disclosure row with the divider line inline, after the label.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showSecondaryProvider.toggle() }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: showSecondaryProvider ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(state.t(.addFallback))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Theme.textSecondary)

                    Rectangle()
                        .fill(Theme.panelStroke)
                        .frame(height: 1)        // fills the rest of the row to the right edge
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSecondaryProvider {
                apiAccount(state.t(.apiSecondary),
                           provider: $state.settings.provider2,
                           baseURL: $state.settings.baseURL2,
                           model: $state.settings.model2,
                           apiKey: $state.settings.apiKey2)
            }

            // Token status
            VStack(alignment: .leading, spacing: 8) {
                // Subheader styled like the "FALLBACK" subtitle, with "Used" at the right.
                HStack {
                    Text(state.t(.tokensUsed).uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text(state.t(.used)).foregroundColor(Theme.textSecondary).font(.system(size: 11))
                }
                .padding(.bottom, 22)   // 22 + VStack spacing 8 = 30px to the graph row

                // Count + progress bar on the SAME row (bar fills the remaining width).
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Text(formatted(state.settings.tokensUsed))
                            .foregroundColor(state.apiStatus.color).font(.system(size: 12, weight: .semibold))
                        Text("/ \(formatted(state.settings.tokensLimit)) \(state.t(.tokensWord))")
                            .foregroundColor(Theme.textSecondary).font(labelFont)
                    }
                    .fixedSize()

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.textPrimary.opacity(0.08))
                            Capsule().fill(Theme.accentGradient)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 14)   // 14 + section spacing 16 = 30px to "AI Instructions"

            // AI Instructions
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(state.t(.aiInstructions)).foregroundColor(Theme.textPrimary).font(labelFont)
                    HelpTip(text: state.t(.tipAIInstructions))
                }
                ZStack(alignment: .bottomTrailing) {
                    PlainTextView(text: $state.settings.aiInstructions, isEditable: true, fontSize: 12,
                                  textColor: Theme.textPrimary)
                        .frame(height: aiHeight)
                        .padding(10)
                        .fieldPanel(corner: 16)

                    ResizeCornerGrip()
                        .padding(6)
                        .background(_DragBlocker())
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    let start = aiDragStart ?? aiHeight
                                    if aiDragStart == nil { aiDragStart = start }
                                    aiHeight = min(max(start + value.translation.height, 64), 400)
                                }
                                .onEnded { _ in aiDragStart = nil }
                        )
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .glassPanel(corner: 16)
    }

    private var saveButton: some View {
        VStack(spacing: 6) {
            // Primary Save button — prominent, full width.
            Button {
                state.saveSettings()
                state.onCloseSettings?()
            } label: {
                Text(state.t(.saveChanges))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.accentGradient)
                    )
            }
            .buttonStyle(.plain)

            // Reset to defaults — small, fully-rounded pill (height 20), confirmed first.
            Button { showResetConfirm = true } label: {
                Text(state.t(.resetDefaults))
                    .font(.system(size: 11))
                    .foregroundColor(resetHover ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.textPrimary.opacity(resetHover ? 0.12 : 0)))   // bg only on hover
            }
            .buttonStyle(.plain)
            .onHover { resetHover = $0 }
            .confirmationDialog(state.t(.resetConfirm), isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(state.t(.resetDefaults), role: .destructive) { performReset() }
                Button(state.t(.cancel), role: .cancel) {}
            }
        }
    }

    private func performReset() {
        state.resetToDefaults()
        keyField = ""
        showSecondaryProvider = false
        LoginItem.set(state.settings.launchAtLogin)
        MicLevel.shared.showDot = state.settings.showRecordingDot
    }

    // MARK: - Helpers

    private var progress: CGFloat {
        guard state.settings.tokensLimit > 0 else { return 0 }
        return min(1, CGFloat(state.settings.tokensUsed) / CGFloat(state.settings.tokensLimit))
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Uniform gap from a section title to its first content row, across every section.
    private static let titleToContentGap: CGFloat = 28

    /// `rowSpacing` is the owning section's VStack spacing. The bottom padding is set so
    /// that (padding + rowSpacing) == titleToContentGap → a constant 32px under every title,
    /// while the inter-row rhythm inside the section stays untouched.
    private func sectionTitle(_ t: String, _ icon: String,
                              rowSpacing: CGFloat, help: String? = nil) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accentBlue)         // takes the theme accent color
            Text(t.uppercased()).font(.system(size: 11, weight: .bold))
                .tracking(1.3).foregroundColor(Theme.textSecondary)
            if let help { HelpTip(text: help) }
        }
        .padding(.bottom, Self.titleToContentGap - rowSpacing)
    }

    /// One API account block (provider + endpoint + key). Used for primary and secondary.
    private func apiAccount(_ title: String,
                            provider: Binding<APIProvider>,
                            baseURL: Binding<String>,
                            model: Binding<String>,
                            apiKey: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundColor(Theme.textSecondary)

            row(state.t(.provider)) {
                CapsulePicker(selection: Binding(
                    get: { provider.wrappedValue },
                    set: { newValue in
                        provider.wrappedValue = newValue
                        baseURL.wrappedValue = newValue.defaultBaseURL
                        model.wrappedValue = newValue.defaultModel
                    }
                ), options: APIProvider.allCases, title: { $0.rawValue }, width: fieldWidth)
            }
            row(state.t(.baseURL)) {
                TextField("https://api.openai.com/v1", text: baseURL)
                    .textFieldStyle(.plain).fieldStyle(fieldWidth)
            }
            row(state.t(.model)) {
                TextField("gpt-4o-mini", text: model)
                    .textFieldStyle(.plain).fieldStyle(fieldWidth)
            }
            row(state.t(.apiKey)) {
                SecureField("sk-...", text: apiKey)
                    .textFieldStyle(.plain).fieldStyle(fieldWidth)
            }
        }
    }

    /// Uniform fixed row height so labels keep an even rhythm regardless of the control's own
    /// height (a hotkey recorder vs a toggle vs a field would otherwise space labels unevenly).
    static let rowHeight: CGFloat = 26

    private func row<Content: View>(_ label: String, help: String? = nil,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(label).font(labelFont).foregroundColor(Theme.textPrimary)
                if let help { HelpTip(text: help) }
            }
            Spacer()
            content()
        }
        .frame(minHeight: Self.rowHeight)
    }

    /// Persist settings and re-register global hotkeys immediately after a change.
    private func applyHotKeys() {
        state.saveSettings()
        HotKeyManager.shared.reload()
    }

    private func hotkeyBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassPanel(corner: 10)
    }

    /// Persisted Source/Target preference bindings (save immediately on change).
    private var sourceBinding: Binding<Lang> {
        Binding(get: { state.settings.sourceLang },
                set: { state.settings.sourceLang = $0; state.saveSettings() })
    }
    private var targetBinding: Binding<Lang> {
        Binding(get: { state.settings.targetLang },
                set: { state.settings.targetLang = $0; state.saveSettings() })
    }

    private func langPicker(_ prefix: LKey, selection: Binding<Lang>, options: [Lang]) -> some View {
        CapsulePicker(selection: selection, options: options,
                      title: { "\(state.t(prefix)): \($0 == .auto ? state.t(.autoDetect) : $0.code)" },
                      width: 155)
    }
}

/// Content for the standalone, draggable Settings window.
struct SettingsWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var theme: AppTheme

    var body: some View {
        ZStack {
            Theme.windowBackground.opacity(Theme.backgroundOpacity)
            SettingsView()
                .padding(.horizontal, 15)          // side frames like the main window
                .padding(.top, 8).padding(.bottom, 6)   // top matches the gap below the header
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .tooltipLayer()
        // Bottom-right resize affordance — drag it to grow/shrink the settings window.
        .overlay(alignment: .bottomTrailing) {
            WindowResizeGrip()
                .frame(width: 16, height: 16)
                .padding(5)
        }
        // Live recolor of the settings panels via the theme-revision environment (no rebuild,
        // so the open color-picker popover stays put).
        .environment(\.themeRevision, theme.revision)
        .preferredColorScheme(colorScheme)
        .onAppear { theme.installFor(appearance: state.settings.appearance) }
    }

    private var colorScheme: ColorScheme? {
        switch state.settings.appearance {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

private extension View {
    func fieldStyle(_ width: CGFloat) -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(width: width, height: Theme.controlHeight)
            .background(Capsule().fill(Theme.fieldFill))
            .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))   // unified capsule
    }
}

/// Secondary action button — a glass pill that brightens on hover. Used for "Check for
/// Updates Now", the GitHub Star button, and similar non-primary actions. Shows a small
/// spinner when `busy`, or a leading SF Symbol when `systemIcon` is set.
private struct GlassButton: View {
    let title: String
    var busy: Bool = false
    var systemIcon: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                } else if let systemIcon {
                    Image(systemName: systemIcon).font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Small diagonal grip in a text area's bottom-right corner. Drag it to resize the area.
/// Brightens on hover and shows a resize cursor.
private struct ResizeCornerGrip: View {
    @State private var hover = false

    var body: some View {
        Canvas { ctx, size in
            let c = Theme.textPrimary.opacity(hover ? 0.6 : 0.32)
            var p = Path()
            p.move(to: CGPoint(x: size.width, y: size.height * 0.30))
            p.addLine(to: CGPoint(x: size.width * 0.30, y: size.height))
            p.move(to: CGPoint(x: size.width, y: size.height * 0.64))
            p.addLine(to: CGPoint(x: size.width * 0.64, y: size.height))
            ctx.stroke(p, with: .color(c), lineWidth: 1.5)
        }
        .frame(width: 12, height: 12)
        .contentShape(Rectangle())
        .onHover { h in
            hover = h
            if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Marks an area as non-window-drag so a child gesture works instead of moving the window.
private struct _DragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BlockerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
