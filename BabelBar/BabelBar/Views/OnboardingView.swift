import SwiftUI
import AppKit

/// First-launch setup wizard: welcome → permissions → API key → finish. Shown once
/// (gated by `AppDelegate`'s `babelbar.onboardingCompleted` flag) in its own borderless
/// window, styled like the rest of the app (glass panels, capsule controls, accent gradient).
enum OnboardingStep: Int, CaseIterable {
    case welcome, accessibility, inputMonitoring, screenRecording, microphone, apiKey, finish
}

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var permRefresh = 0
    @State private var keyField: String = ""
    @State private var micRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            stepContent
                .padding(.horizontal, 32)
            Spacer(minLength: 12)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { keyField = state.settings.apiKey }
        // Settings changed system permissions while our window was in the background —
        // re-read them the moment the app regains focus (mirrors SettingsView's own pattern).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permRefresh &+= 1
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("BabelBar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:         welcomeStep
        case .accessibility:   permissionStep(kind: .accessibility, icon: "accessibility",
                                              title: state.t(.permAccessibility), desc: state.t(.obPermAccessibilityDesc))
        case .inputMonitoring: permissionStep(kind: .inputMonitoring, icon: "keyboard",
                                              title: state.t(.permInput), desc: state.t(.obPermInputDesc))
        case .screenRecording: permissionStep(kind: .screenRecording, icon: "rectangle.dashed",
                                              title: state.t(.permScreen), desc: state.t(.obPermScreenDesc))
        case .microphone:      microphoneStep
        case .apiKey:          apiKeyStep
        case .finish:          finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            appIcon
            Text(state.t(.obWelcomeTitle))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(state.t(.obWelcomeSubtitle))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    private var appIcon: some View {
        Group {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(Theme.accentGradient).opacity(0.18)
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accentGradient)
                }
            }
        }
        .frame(width: 76, height: 76)
    }

    /// One permission screen: icon, title, description, then a status row with the pill
    /// used elsewhere in Settings. Not blocking — Continue always works regardless of grant state.
    private func permissionStep(kind: Permissions.Kind, icon: String, title: String, desc: String) -> some View {
        let granted: Bool = {
            _ = permRefresh
            switch kind {
            case .accessibility:   return Permissions.accessibility()
            case .inputMonitoring: return Permissions.inputMonitoring()
            case .screenRecording: return Permissions.screenRecording()
            case .microphone:      return Permissions.microphone()
            }
        }()
        return VStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(Theme.accentBlue)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(desc)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13)).foregroundColor(Theme.textSecondary).frame(width: 20)
                Text(title).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                Spacer()
                PermissionPill(granted: granted, grantedText: state.t(.granted),
                               actionText: state.t(.openSettings)) { Permissions.openSettings(kind) }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassPanel(corner: 12)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    /// Microphone gets its own step: unlike the other three, macOS lets us trigger the
    /// native access prompt directly (no need to send the user to System Settings first).
    private var microphoneStep: some View {
        let granted: Bool = { _ = permRefresh; return Permissions.microphone() }()
        return VStack(spacing: 22) {
            Image(systemName: "mic")
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(Theme.accentBlue)
            Text(state.t(.permMic))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(state.t(.obPermMicDesc))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
            HStack(spacing: 11) {
                Image(systemName: "mic")
                    .font(.system(size: 13)).foregroundColor(Theme.textSecondary).frame(width: 20)
                Text(state.t(.permMic)).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                Spacer()
                if granted {
                    PermissionPill(granted: true, grantedText: state.t(.granted), actionText: "") {}
                } else if micRequesting {
                    ProgressView().controlSize(.small)
                } else {
                    HoverTextButton(title: state.t(.obGrantAccess)) { requestMic() }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassPanel(corner: 12)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    private func requestMic() {
        guard !micRequesting else { return }
        micRequesting = true
        state.requestMicrophoneAccess { _ in
            micRequesting = false
            permRefresh &+= 1
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.fill")
                .font(.system(size: 34))
                .foregroundColor(Theme.accentBlue)
            Text(state.t(.obApiKeyTitle))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(state.t(.obApiKeySubtitle))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(state.t(.provider)).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                    Spacer()
                    CapsulePicker(selection: Binding(
                        get: { state.settings.provider },
                        set: { newValue in
                            state.settings.provider = newValue
                            state.settings.baseURL = newValue.defaultBaseURL
                            state.settings.model = newValue.defaultModel
                        }
                    ), options: APIProvider.allCases, title: { $0.rawValue }, width: 200)
                }
                if let url = Self.keySignupURL(for: state.settings.provider) {
                    HStack {
                        Spacer()
                        Button { NSWorkspace.shared.open(url) } label: {
                            HStack(spacing: 4) {
                                Text(String(format: state.t(.obGetApiKeyFmt), state.settings.provider.rawValue))
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.accentBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text(state.t(.apiKey)).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
                    Spacer()
                    SecureField("sk-...", text: $keyField)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(width: 240, height: Theme.controlHeight)
                        .background(Capsule().fill(Theme.fieldFill))
                        .overlay(Capsule().stroke(Theme.controlBorder, lineWidth: 1))
                        .onChange(of: keyField) { state.settings.apiKey = $0 }
                }
            }
            .padding(24)
            .glassPanel(corner: 16)
            .frame(maxWidth: 420)

            Text(state.t(.obApiKeySkipNote))
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    private var finishStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.accentGreen)
            Text(state.t(.obFinishTitle))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(state.t(.obFinishSubtitle))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            VStack(spacing: 10) {
                hotkeyRow(state.t(.openBabelBar), state.settings.openHotKey.display)
                hotkeyRow(state.t(.translateAuto), state.settings.selectionHotKey.displayDoubled)
                hotkeyRow(state.t(.translateScreenshot), state.settings.screenshotHotKey.display)
                hotkeyRow(state.t(.dictateToCursor), state.settings.dictateHotkey.display)
            }
            .padding(20)
            .glassPanel(corner: 16)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    /// Where to get an API key for the given provider (nil for `.custom` — no fixed page to link to).
    private static func keySignupURL(for provider: APIProvider) -> URL? {
        switch provider {
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")
        case .deepseek:  return URL(string: "https://platform.deepseek.com/api_keys")
        case .zai:       return URL(string: "https://z.ai/manage-apikey/apikey-list")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .groq:      return URL(string: "https://console.groq.com/keys")
        case .custom:    return nil
        }
    }

    private func hotkeyRow(_ label: String, _ combo: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(Theme.textPrimary)
            Spacer()
            Text(combo)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.textPrimary.opacity(0.08)))
        }
    }

    // MARK: - Bottom bar (Back / dots / Skip / Continue)

    private var bottomBar: some View {
        ZStack {
            HStack {
                if step != .welcome {
                    HoverTextButton(title: state.t(.obBack)) { goBack() }
                }
                Spacer()
                if step != .finish {
                    HoverTextButton(title: state.t(.obSkip)) { finish() }
                }
                primaryButton
            }
            dots
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(height: 32)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s == step ? Theme.accentBlue : Theme.textPrimary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            if step == .finish { finish() } else { goNext() }
        } label: {
            Text(step == .finish ? state.t(.obGetStarted) : state.t(.obContinue))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .frame(height: 32)
                .background(Capsule(style: .continuous).fill(Theme.accentGradient))
        }
        .buttonStyle(.plain)
    }

    private func goNext() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { finish(); return }
        withAnimation(.easeInOut(duration: 0.15)) { step = next }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { step = prev }
    }

    private func finish() {
        state.saveSettings()
        onFinish()
    }
}

/// Content for the standalone onboarding window (adds the themed background + sizing,
/// same split as `SettingsWindowView` does for `SettingsView`).
struct OnboardingWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var theme: AppTheme
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            Theme.windowBackground.opacity(Theme.backgroundOpacity)
            OnboardingView(onFinish: onFinish)
                .padding(.horizontal, 15)
                .padding(.top, 10).padding(.bottom, 8)
        }
        .frame(width: 560, height: 620)
        .tooltipLayer()
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
