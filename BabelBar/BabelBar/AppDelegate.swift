import AppKit
import SwiftUI
import CoreImage

/// Borderless window that still accepts key focus and main status (needed for text editing).
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Real, adjustable Gaussian blur of whatever is behind the window, via the private
/// `CABackdropLayer` + `CAFilter(gaussianBlur)` recipe (the same machinery NSVisualEffectView
/// uses internally). Fine for direct distribution; not for the Mac App Store. Falls back to a
/// system `NSVisualEffectView` (alpha-faded) when the backdrop layer isn't available.
final class VariableBlurView: NSView {
    private var backdrop: CALayer?
    private var fallback: NSVisualEffectView?
    /// Gaussian radius at full intensity (kept gentle — even small radii read as strong blur).
    private let maxRadius: CGFloat = 12

    override init(frame f: NSRect) {
        super.init(frame: f)
        wantsLayer = true
        // Required by the backdrop recipe: it's rendered by the window server, not Core Image.
        layerUsesCoreImageFilters = false
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Instantiate a private `CAFilter` by type string (e.g. "gaussianBlur").
    private static func makeCAFilter(_ type: String) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel) else { return nil }
        return (cls as AnyObject).perform(sel, with: type)?.takeUnretainedValue() as? NSObject
    }

    private func build() {
        guard let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            let v = NSVisualEffectView(frame: bounds)
            v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
            v.autoresizingMask = [.width, .height]
            addSubview(v); fallback = v
            return
        }
        let bd = cls.init()
        bd.frame = bounds
        bd.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        bd.masksToBounds = true
        // Capture & blend what's BEHIND the window (the desktop), via the window server.
        bd.setValue(true, forKey: "windowServerAware")
        bd.setValue(1.0, forKey: "scale")
        bd.setValue(true, forKey: "allowsGroupBlending")
        bd.setValue(0.0, forKey: "bleedAmount")
        bd.setValue(UUID().uuidString, forKey: "groupName")

        if let blur = Self.makeCAFilter("gaussianBlur") {
            blur.setValue("gaussianBlur", forKey: "name")
            blur.setValue(true, forKey: "inputNormalizeEdges")   // no transparent edge bleed
            blur.setValue(0.0, forKey: "inputRadius")
            bd.setValue([blur], forKey: "filters")
        }
        layer?.addSublayer(bd)
        backdrop = bd
        apply()
    }

    /// 0 = no blur (clear desktop), 1 = full strength.
    var intensity: CGFloat = 0 { didSet { apply() } }
    var appearanceOverride: NSAppearance? { didSet { fallback?.appearance = appearanceOverride } }

    private func apply() {
        let i = max(0, min(1, intensity))
        if let bd = backdrop {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bd.isHidden = i <= 0.001
            bd.setValue(i * maxRadius, forKeyPath: "filters.gaussianBlur.inputRadius")
            CATransaction.commit()
        } else {
            fallback?.alphaValue = i
        }
    }
}

/// Hosts the SwiftUI content inside a rounded, blurred NSVisualEffectView and propagates
/// the SwiftUI intrinsic size up so the window auto-resizes (translator ⇄ settings).
final class BlurContainerViewController: NSViewController {
    private let radius: CGFloat
    private let content: NSViewController
    /// When false, the controller does NOT push its content's preferred size up to the window,
    /// so a user-resizable window won't keep snapping back to the SwiftUI intrinsic size.
    private let tracksPreferredSize: Bool

    init(content: NSViewController, radius: CGFloat, tracksPreferredSize: Bool = true) {
        self.content = content
        self.radius = radius
        self.tracksPreferredSize = tracksPreferredSize
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The blur layer lives BELOW the content so its radius (the Blur slider) gives a real,
    /// adjustable Gaussian blur — and at 0 disappears, revealing the clear desktop.
    private(set) weak var blurView: VariableBlurView?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = radius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        container.layer?.borderWidth = 1

        let blur = VariableBlurView(frame: container.bounds)
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)
        self.blurView = blur

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)          // content sits ON TOP of the blur layer
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if tracksPreferredSize { preferredContentSize = content.preferredContentSize }
    }

    /// Apply the live chrome: blur intensity (0…1) + appearance.
    func applyChrome(blurAlpha: CGFloat, appearance: NSAppearance?) {
        blurView?.intensity = blurAlpha
        blurView?.appearanceOverride = appearance
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        // SwiftUI content changed its intrinsic height (translator ⇄ settings) → resize window.
        guard tracksPreferredSize else { return }
        preferredContentSize = viewController.preferredContentSize
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var panel: KeyableBorderlessWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private static let onboardingCompletedKey = "babelbar.onboardingCompleted"
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure menu-bar agent: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Apply the saved theme before the first view renders.
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        appState.theme.install(isDark: appState.settings.appearance == .light ? false
                               : appState.settings.appearance == .dark ? true : systemDark)

        setupStatusItem()

        appState.onRequestShow = { [weak self] in self?.showPanel() }
        appState.onRequestToggle = { [weak self] in self?.togglePanel() }
        appState.onRequestClose = { [weak self] in self?.hidePanel() }
        appState.onPinChanged = { [weak self] pinned in self?.applyPinned(pinned) }
        appState.onOpenSettings = { [weak self] in self?.showSettings() }
        appState.onCloseSettings = { [weak self] in self?.closeSettings() }
        appState.onMenuBarVisibilityChanged = { [weak self] visible in self?.statusItem.isVisible = visible }

        HotKeyManager.shared.configure(appState: appState)
        HotKeyManager.shared.start()

        // Global voice shortcuts: dictate at the cursor (Fn) and dictate→translate→insert (Shift+Fn).
        VoiceHotkeys.shared.bindings = { [weak appState] in
            guard let s = appState, s.settings.voiceInputEnabled else { return [] }   // master off → no hotkeys
            var list: [(ModifierCombo, VoiceAction)] = []
            if !s.settings.dictateHotkey.isEmpty {
                list.append((s.settings.dictateHotkey, .dictateToCursor))
            }
            if !s.settings.translateDictateHotkey.isEmpty {
                list.append((s.settings.translateDictateHotkey, .dictateTranslateToCursor))
            }
            return list
        }
        VoiceHotkeys.shared.onStart = { [weak appState] action in
            switch action {
            case .dictateToCursor:          appState?.startCursorDictation()
            case .dictateTranslateToCursor: appState?.startCursorTranslateDictation()
            }
        }
        VoiceHotkeys.shared.onStop = { [weak appState] action in
            switch action {
            case .dictateToCursor:          appState?.stopCursorDictation()
            case .dictateTranslateToCursor: appState?.stopCursorTranslateDictation()
            }
        }
        VoiceHotkeys.shared.start()

        // Keep window chrome (light/dark appearance + blur material) in sync with the theme.
        appState.theme.onChromeChanged = { [weak self] in self?.applyChrome() }
        applyChrome()

        showOnboardingIfNeeded()
    }

    private func nsAppearance(_ isDark: Bool) -> NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func applyChrome() {
        let a = nsAppearance(appState.theme.currentIsDark)
        let blurAlpha = appState.theme.blurAlpha
        for window in [panel, settingsWindow, onboardingWindow].compactMap({ $0 }) {
            window.appearance = a
            (window.contentViewController as? BlurContainerViewController)?
                .applyChrome(blurAlpha: blurAlpha, appearance: a)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.action = #selector(handleStatusClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Reflect the saved preference (the panel is still reachable via the global hotkey
        // when the icon is hidden, so the user can't lock themselves out).
        statusItem.isVisible = appState.settings.showMenuBarIcon
    }

    /// Menu-bar glyph — the custom BabelBar PDF (template, tints to the menu bar).
    static func menuBarIcon() -> NSImage {
        if let img = NSImage(named: "StatusBarIcon") {
            img.isTemplate = true
            let h: CGFloat = 18
            let ratio = img.size.height > 0 ? img.size.width / img.size.height : 1
            img.size = NSSize(width: h * ratio, height: h)
            return img
        }
        // Fallback: simple drawn glyph if the asset is missing.
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let box = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 1.6, width: 14.8, height: 14.8),
                                   xRadius: 4.2, yRadius: 4.2)
            box.lineWidth = 1.25; box.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Stretchable rounded-rect mask image — the supported way to round NSVisualEffectView.
    static func cornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    @objc private func handleStatusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let show = NSMenuItem(title: appState.t(.menuShow), action: #selector(menuShow), keyEquivalent: "")
        show.target = self; menu.addItem(show)
        let settings = NSMenuItem(title: appState.t(.menuSettings), action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: appState.t(.menuQuit), action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func menuShow() { showPanel() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Panel window

    private func makePanel() -> KeyableBorderlessWindow {
        let root = RootView()
            .environmentObject(appState)
            .environmentObject(appState.theme)
        let hosting = NSHostingController(rootView: root)
        // No `.preferredContentSize` sizing → the window is free to be resized by the user
        // (the SwiftUI content stretches to fill it) instead of being pinned to 600×388.

        let container = BlurContainerViewController(content: hosting, radius: 16,
                                                    tracksPreferredSize: false)

        let window = KeyableBorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 388),
            styleMask: [.borderless, .fullSizeContentView, .resizable],   // drag a corner to resize
            backing: .buffered, defer: false
        )
        window.contentViewController = container
        window.minSize = NSSize(width: 480, height: 320)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.appearance = nsAppearance(appState.theme.currentIsDark)
        container.view.appearance = nsAppearance(appState.theme.currentIsDark)
        window.level = appState.isPinned ? .floating : .normal
        // Come to the CURRENT space/screen when shown instead of yanking the user back to
        // wherever the window was last opened (multi-monitor / multi-Space fix).
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        enableBackdropHosting(window)
        return window
    }

    /// Re-register the window's layer tree with the window server so the CABackdropLayer
    /// actually captures the desktop behind it (needed when layers are already hosted).
    private func enableBackdropHosting(_ window: NSWindow) {
        _ = window.contentViewController?.view   // force the view + layer tree to load
        guard window.responds(to: NSSelectorFromString("setCanHostLayersInWindowServer:")) else { return }
        window.setValue(false, forKey: "canHostLayersInWindowServer")
        window.setValue(true, forKey: "canHostLayersInWindowServer")
    }

    /// The screen the user is currently on (under the mouse), falling back to the key screen.
    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func togglePanel() {
        if let panel, panel.isVisible { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        let window = panel ?? makePanel()
        panel = window
        applyChrome()
        let wasVisible = window.isVisible
        positionUnderStatusItem(window)
        if !wasVisible {
            // Keep it invisible until we've re-asserted the position from the *settled*
            // status-item geometry — on first show the menu-bar layout isn't final yet, which
            // used to drop the window off to the side instead of centered under the icon.
            window.alphaValue = 0
        }
        window.makeKeyAndOrderFront(nil)
        updateActivationPolicy()              // .regular while open → appears in Cmd-Tab + Dock
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible {
            DispatchQueue.main.async {
                self.positionUnderStatusItem(window)   // final geometry → truly centered
                self.animateAppearance(window)
            }
        } else {
            positionUnderStatusItem(window)
        }
    }

    /// Subtle fade + slide-down on show (mimics the old popover reveal).
    private func animateAppearance(_ window: NSWindow) {
        let final = window.frame
        var start = final
        start.origin.y += 8
        window.setFrame(start, display: false)
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(final, display: true)
        }
    }

    func hidePanel() {
        panel?.orderOut(nil)
        updateActivationPolicy()              // drop Dock/Cmd-Tab presence if nothing else is open
    }

    private func positionUnderStatusItem(_ window: NSWindow) {
        let target = currentScreen()
        let size = window.frame.size
        func clampX(_ x: CGFloat) -> CGFloat {
            min(max(x, target.visibleFrame.minX + 8), target.visibleFrame.maxX - size.width - 8)
        }

        // If the menu-bar icon is on the current screen, drop the panel right under it.
        if let button = statusItem.button, let bWin = button.window, bWin.screen == target {
            let onScreen = bWin.convertToScreen(button.convert(button.bounds, to: nil))
            window.setFrameOrigin(NSPoint(x: clampX(onScreen.midX - size.width / 2),
                                          y: onScreen.minY - size.height - 6))
        } else {
            // Otherwise (status item lives on another display) — top-center of the current screen.
            let vf = target.visibleFrame
            window.setFrameOrigin(NSPoint(x: clampX(vf.midX - size.width / 2),
                                          y: vf.maxY - size.height - 8))
        }
    }

    private func applyPinned(_ pinned: Bool) {
        panel?.level = pinned ? .floating : .normal
    }

    // MARK: - Settings window (separate, draggable)

    /// While any of our windows is open → become a regular app (Dock icon + visible in Cmd-Tab);
    /// when everything is closed → back to a pure menu-bar accessory.
    private func updateActivationPolicy() {
        let anyOpen = (panel?.isVisible ?? false) || (settingsWindow?.isVisible ?? false)
            || (onboardingWindow?.isVisible ?? false)
        let desired: NSApplication.ActivationPolicy = anyOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != desired else { return }
        NSApp.setActivationPolicy(desired)
        if desired == .regular { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Place Settings right where the app is: aligned to the main panel's top, centered on it
    /// and nudged slightly left. If the panel isn't open, fall back to under the status item.
    private func positionSettings(_ window: NSWindow) {
        let size = window.frame.size
        let vf = currentScreen().visibleFrame
        func clamp(_ p: NSPoint) -> NSPoint {
            NSPoint(x: min(max(p.x, vf.minX + 8), vf.maxX - size.width - 8),
                    y: min(max(p.y, vf.minY + 8), vf.maxY - size.height - 8))
        }
        if let panel, panel.isVisible {
            let pf = panel.frame
            let x = pf.midX - size.width / 2 - 24      // small nudge to the left
            let y = pf.maxY - size.height              // align top edges
            window.setFrameOrigin(clamp(NSPoint(x: x, y: y)))
        } else {
            positionUnderStatusItem(window)            // no app window → drop under the icon
        }
    }

    func showSettings() {
        if let win = settingsWindow {
            positionSettings(win)                 // open on/near the app window
            win.makeKeyAndOrderFront(nil)
            updateActivationPolicy()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = SettingsWindowView()
            .environmentObject(appState)
            .environmentObject(appState.theme)
        let hosting = NSHostingController(rootView: content)
        // tracksPreferredSize:false so the user-resizable window isn't pinned to the content size.
        let container = BlurContainerViewController(content: hosting, radius: 16,
                                                    tracksPreferredSize: false)

        // Borderless (no titlebar dead zone); draggable by background; resizable from a corner.
        let window = KeyableBorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false
        )
        window.contentViewController = container
        window.minSize = NSSize(width: 560, height: 420)
        window.setContentSize(NSSize(width: 600, height: 680))   // default size, resizable after
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.appearance = nsAppearance(appState.theme.currentIsDark)
        container.view.appearance = nsAppearance(appState.theme.currentIsDark)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        settingsWindow = window
        enableBackdropHosting(window)
        positionSettings(window)
        applyChrome()
        window.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSettings() {
        settingsWindow?.orderOut(nil)
        updateActivationPolicy()   // drop the Dock icon when settings closes
    }

    // MARK: - Onboarding (first-launch setup wizard)

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) else { return }
        showOnboarding()
    }

    private func showOnboarding() {
        if let win = onboardingWindow {
            win.center()
            win.makeKeyAndOrderFront(nil)
            updateActivationPolicy()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = OnboardingWindowView(onFinish: { [weak self] in self?.finishOnboarding() })
            .environmentObject(appState)
            .environmentObject(appState.theme)
        let hosting = NSHostingController(rootView: content)
        let container = BlurContainerViewController(content: hosting, radius: 16, tracksPreferredSize: false)

        // Fixed-size, non-resizable — a short guided wizard, not a resizable workspace window.
        let window = KeyableBorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentViewController = container
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.appearance = nsAppearance(appState.theme.currentIsDark)
        container.view.appearance = nsAppearance(appState.theme.currentIsDark)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        onboardingWindow = window
        enableBackdropHosting(window)
        applyChrome()
        window.center()
        window.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        onboardingWindow?.orderOut(nil)
        updateActivationPolicy()
        showPanel()
    }
}
