import AppKit
import Carbon.HIToolbox

/// Registers global hotkeys from user settings:
///   • Open BabelBar     → single Carbon hotkey (default ⌥Space)
///   • Translate Screenshot  → single Carbon hotkey (default ⇧⌘2)
///   • Translate selection   → double-tap of a combo via global monitor (default ⌘C)
final class HotKeyManager {
    static let shared = HotKeyManager()
    private init() {}

    private weak var appState: AppState?
    private var carbonHandler: EventHandlerRef?
    private var openHotKey: EventHotKeyRef?
    private var shotHotKey: EventHotKeyRef?
    private var globalMonitor: Any?
    private var lastTapDate: Date?

    private let openID: UInt32 = 1
    private let shotID: UInt32 = 2

    func configure(appState: AppState) {
        self.appState = appState
    }

    func start() {
        installCarbonHandlerIfNeeded()
        registerFromSettings()
        registerDoubleTapMonitor()
    }

    /// Re-register everything after the user changes a hotkey in Settings.
    func reload() {
        unregisterCarbon()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        registerFromSettings()
        registerDoubleTapMonitor()
    }

    // MARK: - Carbon hotkeys (single-press: Open, Screenshot)

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            manager.handleCarbonHotKey(id: hkID.id)
            return noErr
        }, 1, &eventType, selfPtr, &carbonHandler)
    }

    private func registerFromSettings() {
        guard let s = appState?.settings else { return }
        register(combo: s.openHotKey, id: openID, ref: &openHotKey)
        register(combo: s.screenshotHotKey, id: shotID, ref: &shotHotKey)
    }

    private func register(combo: KeyCombo, id: UInt32, ref: inout EventHotKeyRef?) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54424152), id: id) // 'TBAR'
        RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    private func unregisterCarbon() {
        if let r = openHotKey { UnregisterEventHotKey(r); openHotKey = nil }
        if let r = shotHotKey { UnregisterEventHotKey(r); shotHotKey = nil }
    }

    private func handleCarbonHotKey(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let state = self.appState else { return }
            switch id {
            case self.openID: state.onRequestToggle?()   // press again to hide
            case self.shotID: state.handleScreenshotTranslate()
            default: break
            }
        }
    }

    // MARK: - Double-tap monitor (Translate selection)

    private func registerDoubleTapMonitor() {
        guard let combo = appState?.settings.selectionHotKey else { return }
        let wantMods = combo.eventModifiers.intersection([.command, .shift, .option, .control])

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            // Match by physical key code (layout-independent) + exact modifier set.
            let haveMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let match = event.keyCode == UInt16(combo.keyCode) && haveMods == wantMods
            guard match else { return }

            let now = Date()
            if let last = self.lastTapDate, now.timeIntervalSince(last) < 0.5 {
                self.lastTapDate = nil
                DispatchQueue.main.async { self.appState?.handleTranslateSelection() }
            } else {
                self.lastTapDate = now
            }
        }
    }
}
