import AppKit
import SwiftUI
import Carbon.HIToolbox

// =============================================================================
//  Configurable global modifier-only voice shortcuts. They support hold-to-talk
//  (hold → speak → release) and tap-to-toggle (tap → speak → tap).
//  Implemented with a CGEventTap so the Fn key can be detected (keyCode 63) reliably.
//  Requires Accessibility permission.
// =============================================================================

/// A modifier-only shortcut (Fn / Shift / Ctrl / Opt / Cmd), e.g. "Fn" or "Shift + Fn".
struct ModifierCombo: Codable, Equatable {
    var fn = false
    var shift = false
    var control = false
    var option = false
    var command = false

    var isEmpty: Bool { !(fn || shift || control || option || command) }
    var modifierCount: Int { [fn, shift, control, option, command].filter { $0 }.count }

    /// True when every modifier of `other` is also held here (`Shift+Fn` contains `Fn`).
    func contains(_ other: ModifierCombo) -> Bool {
        (!other.fn || fn) && (!other.shift || shift) && (!other.control || control)
            && (!other.option || option) && (!other.command || command)
    }

    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        if fn      { parts.append("fn") }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }
}

enum VoiceAction: Equatable {
    case dictateToCursor
    case dictateTranslateToCursor
    case liveDictateToCursor

    var usesBatchCapture: Bool { self != .liveDictateToCursor }
}

/// Types a string at the current cursor position in the frontmost app (no clipboard).
enum CursorTyping {
    /// Typed in small chunks: a single giant unicode event is silently dropped by some
    /// apps (terminals / Electron). Flags are cleared on every event so a still-held
    /// modifier (Fn / Shift) can't turn the inserted characters into a shortcut —
    /// which used to send focus to the Dock and drop the text.
    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let units = Array(text.utf16)
        let chunkSize = 16
        DispatchQueue.global(qos: .userInitiated).async {
            let src = CGEventSource(stateID: .combinedSessionState)
            var i = 0
            while i < units.count {
                let slice = Array(units[i ..< min(i + chunkSize, units.count)])
                guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { break }
                down.flags = []            // no stray modifiers → plain text, never a shortcut
                up.flags = []
                down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
                up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                i += chunkSize
                usleep(1500)               // let the target app keep up
            }
        }
    }
}

/// Global modifier-combo detector with hold/tap session handling.
///
/// The CGEventTap runs on its **own dedicated thread + run loop**, never the main
/// run loop. This matters: during long dictation the main thread can get busy
/// (overlay animation, recognizer callbacks, SwiftUI updates). If the tap lived on
/// the main run loop and that loop stalled, macOS would disable the tap by timeout
/// and the Fn keypress would **leak to the system** — stealing focus to the Dock and
/// firing Fn's default action (the "Dock activates / everything freezes" bug).
/// On a private thread the tap always services events promptly and keeps swallowing
/// Fn regardless of how busy the UI is.
final class VoiceHotkeys {
    static let shared = VoiceHotkeys()
    private init() {}

    /// Provides the current bindings (combo → action). Reassigning refreshes the cache.
    var bindings: () -> [(ModifierCombo, VoiceAction)] = { [] } {
        didSet { refreshBindings() }
    }
    var onStart: ((VoiceAction) -> Void)?
    var onStop: ((VoiceAction) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private let tapLifecycleLock = NSLock()
    private var fnDown = false

    // Thread-safe snapshot of the bindings so the tap thread never reads AppState directly.
    private let bindingsLock = NSLock()
    private var cachedBindings: [(ModifierCombo, VoiceAction)] = []
    private var shortcutRecording = false

    // Session state machine.
    private enum Phase { case idle, holdPending, toggling, toggleStopPending }
    private var phase: Phase = .idle
    private var activeAction: VoiceAction?
    private var activeCombo = ModifierCombo()
    private var pressStart: TimeInterval = 0
    private var prevHeld = false
    private let tapThreshold: TimeInterval = 0.4   // < this on release = treat as a tap (toggle)

    // Safety net: a session must always end. If the release event is lost (tap disabled, key
    // stuck, another app grabbing the modifier) the recording would otherwise run forever.
    private var sessionID = 0
    private let maxSessionDuration: TimeInterval = 300

    // Modifiers of a combo arrive as separate flagsChanged events, so "Shift+Fn" can be
    // seen as a bare "Fn" first. When a matched combo is also the prefix of a longer
    // binding we let the flags settle before committing to an action.
    private var latestCombo = ModifierCombo()
    private var latestEventTime: TimeInterval = 0
    private var startPending = false
    private let comboSettleDelay: TimeInterval = 0.15

    /// Re-snapshot the bindings. Call on the main thread (reads app state).
    func refreshBindings() {
        let list = bindings()
        bindingsLock.lock(); cachedBindings = list; bindingsLock.unlock()
    }

    private func snapshotBindings() -> [(ModifierCombo, VoiceAction)] {
        bindingsLock.lock(); defer { bindingsLock.unlock() }
        return shortcutRecording ? [] : cachedBindings
    }

    /// Let the active settings window receive Fn while its shortcut recorder is open.
    func setShortcutRecording(_ recording: Bool) {
        bindingsLock.lock(); shortcutRecording = recording; bindingsLock.unlock()
        if recording {
            if activeAction != nil { finish() }
            cancelActiveSession()
        }
    }

    private func isShortcutRecording() -> Bool {
        bindingsLock.lock(); defer { bindingsLock.unlock() }
        return shortcutRecording
    }

    func start() {
        stop()
        refreshBindings()

        let thread = Thread { [weak self] in
            guard let self, !Thread.current.isCancelled else { return }
            let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            let callback: CGEventTapCallBack = { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<VoiceHotkeys>.fromOpaque(userInfo).takeUnretainedValue()
                return me.handle(type: type, event: event)
            }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: mask,
                                              callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                NSLog("BabelBar: voice event tap unavailable (Accessibility permission?)")
                return
            }
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let rl = CFRunLoopGetCurrent()
            self.tapLifecycleLock.lock()
            guard !Thread.current.isCancelled else {
                self.tapLifecycleLock.unlock()
                CFMachPortInvalidate(tap)
                return
            }
            CFRunLoopAddSource(rl, src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.tap = tap
            self.source = src
            self.tapRunLoop = rl
            self.fnDown = NSEvent.modifierFlags.contains(.function)
            self.tapLifecycleLock.unlock()
            NSLog("BabelBar startup: voice shortcut listener ready")
            // Service the tap on this private run loop until stop() tears it down.
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.5, false)
            }
        }
        thread.name = "com.babelbar.voicehotkeys"
        thread.qualityOfService = .userInteractive
        tapLifecycleLock.lock(); tapThread = thread; tapLifecycleLock.unlock()
        thread.start()
    }

    func stop() {
        tapLifecycleLock.lock()
        tapThread?.cancel()
        let rl = tapRunLoop, source = self.source, tap = self.tap
        self.tap = nil; self.source = nil; tapRunLoop = nil; tapThread = nil
        tapLifecycleLock.unlock()
        if let rl {
            if let source { CFRunLoopRemoveSource(rl, source, .commonModes) }
            CFRunLoopStop(rl)
        }
        if let tap { CFMachPortInvalidate(tap) }
    }

    private func anyBindingUsesFn() -> Bool { snapshotBindings().contains { $0.0.fn } }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disabled the tap (timeout/user input) — re-enable so global hotkeys keep working.
            NSLog("BabelBar: voice event tap was disabled (%u); reenabling", type.rawValue)
            tapLifecycleLock.lock(); let tap = self.tap; tapLifecycleLock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // No flagsChanged was delivered while the tap was off, so the release that ends an
            // active session may have been dropped. The state machine would then stay in
            // `.holdPending` forever: the mic keeps recording, the pill stays on screen and the
            // hotkey looks dead — the "app froze during dictation" bug. Re-read the real modifier
            // state and replay it so a missed release is still seen.
            let flags = NSEvent.modifierFlags
            fnDown = flags.contains(.function)
            let settled = combo(from: flags)
            let eventTime = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { self.process(current: settled, at: eventTime) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged, let ns = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        // Track the real Fn state from the Fn key itself (keyCode 63).
        if ns.keyCode == 63 { fnDown = ns.modifierFlags.contains(.function) }

        if isShortcutRecording() { return Unmanaged.passUnretained(event) }

        let current = combo(from: ns.modifierFlags)
        let eventTime = ns.timestamp
        DispatchQueue.main.async { self.process(current: current, at: eventTime) }

        // Swallow the standalone Fn press so macOS doesn't trigger its own Fn action.
        if ns.keyCode == 63 && anyBindingUsesFn() { return nil }
        return Unmanaged.passUnretained(event)
    }

    private func combo(from flags: NSEvent.ModifierFlags) -> ModifierCombo {
        ModifierCombo(fn: fnDown,
                      shift: flags.contains(.shift),
                      control: flags.contains(.control),
                      option: flags.contains(.option),
                      command: flags.contains(.command))
    }

    private func match(_ c: ModifierCombo) -> (ModifierCombo, VoiceAction)? {
        guard !c.isEmpty else { return nil }
        return snapshotBindings().first { $0.0 == c }
    }

    /// True when a longer binding could still be completed from `c` (e.g. `Fn` → `Shift+Fn`).
    private func needsComboSettling(_ combo: ModifierCombo, action: VoiceAction) -> Bool {
        let longer = snapshotBindings().filter { $0.0 != combo && $0.0.contains(combo) }
        // Both batch actions start the same capture. Begin immediately and select
        // the stop action if Shift joins Fn, without opening a second microphone.
        return !longer.isEmpty && (!action.usesBatchCapture || longer.contains { !$0.1.usesBatchCapture })
    }

    private func begin(_ combo: ModifierCombo, _ action: VoiceAction, pressedAt: TimeInterval) {
        phase = .holdPending
        activeAction = action
        activeCombo = combo
        pressStart = pressedAt
        prevHeld = true
        sessionID &+= 1
        let id = sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + maxSessionDuration) { [weak self] in
            guard let self, self.sessionID == id, self.phase != .idle else { return }
            // Live dictation supports long sessions; its controller owns stop,
            // field-change and error handling. Keep the batch-recording limit.
            guard self.activeAction != .liveDictateToCursor else { return }
            self.finish()
        }
        onStart?(action)
    }

    func process(current: ModifierCombo, at eventTime: TimeInterval) {
        latestCombo = current
        latestEventTime = eventTime

        switch phase {
        case .idle:
            guard !startPending, let (combo, action) = match(current) else { return }
            guard needsComboSettling(combo, action: action) else {
                begin(combo, action, pressedAt: eventTime)
                return
            }
            // Wait for the remaining modifiers before committing, so "Shift+Fn" isn't
            // started as a plain "Fn" dictation session.
            startPending = true
            let pressedAt = eventTime
            let pendingSession = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + comboSettleDelay) { [weak self] in
                guard let self, self.sessionID == pendingSession, self.startPending else { return }
                self.startPending = false
                guard self.phase == .idle else { return }
                let settled = self.latestCombo
                if let (c, a) = self.match(settled) {
                    self.begin(c, a, pressedAt: pressedAt)
                } else {
                    // Released within the settle window: start the original action and
                    // immediately replay the current (released) flags so the tap/hold
                    // state machine still sees the release.
                    self.begin(combo, action, pressedAt: pressedAt)
                    self.process(current: settled, at: self.latestEventTime)
                }
            }

        case .holdPending, .toggling, .toggleStopPending:
            if phase == .holdPending, activeAction?.usesBatchCapture == true,
               eventTime - pressStart <= comboSettleDelay,
               let (combo, action) = match(current), action.usesBatchCapture,
               combo != activeCombo, combo.contains(activeCombo) {
                activeCombo = combo
                activeAction = action
            }
            // Extra modifiers must not look like a release of the dictation key.
            let held = current.contains(activeCombo)
            if held && !prevHeld {
                // combo pressed again (second tap) while in a toggle session
                if phase == .toggling { phase = .toggleStopPending }
            } else if !held && prevHeld {
                // combo released
                switch phase {
                case .holdPending:
                    if eventTime - pressStart < tapThreshold {
                        phase = .toggling                 // quick tap → keep listening
                    } else {
                        finish()                          // hold release → stop + insert
                    }
                case .toggleStopPending:
                    finish()                              // second tap release → stop
                default: break
                }
            }
            prevHeld = held
        }
    }

    /// The controller may stop on a field change, input, or recognition failure.
    /// Reset the key state as well so the very next Fn press starts a new session.
    func cancelActiveSession() {
        sessionID &+= 1
        phase = .idle; activeAction = nil; activeCombo = ModifierCombo()
        prevHeld = false; startPending = false
    }

    /// Stop microphone capture when dictation is disabled or its mode changes.
    func stopActiveSession() {
        if activeAction != nil { finish() }
        cancelActiveSession()
    }

    private func finish() {
        if let action = activeAction { onStop?(action) }
        phase = .idle
        activeAction = nil
        activeCombo = ModifierCombo()
        prevHeld = false
    }
}

// MARK: - Settings recorder for a modifier-only combo

struct ModifierComboRecorder: View {
    @Binding var combo: ModifierCombo
    var recordingPrompt: String = "Press modifiers…"
    var clearLabel: String = "Clear"
    var onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var pending = ModifierCombo()
    @State private var hover = false
    @Environment(\.themeRevision) private var revision   // re-render on theme switch

    var body: some View {
        let _ = revision
        return HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
            Text(recording ? (pending.isEmpty ? recordingPrompt : pending.display) : combo.display)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(recording ? Theme.accentPurple : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(minWidth: 95).frame(height: Theme.controlHeight)   // uniform badge size
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(recording ? 0.14 : (hover ? 0.10 : 0.05)))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(recording ? Theme.accentPurple.opacity(0.6) : Theme.controlBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            if !combo.isEmpty {
                Button { clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(clearLabel)
                .accessibilityLabel(clearLabel)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        pending = ModifierCombo()
        recording = true
        VoiceHotkeys.shared.setShortcutRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown]) { event in
            if event.type == .leftMouseDown { stop(); return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { stop(); return nil } // Escape cancels.
                if event.keyCode == 51 || event.keyCode == 117 { clear(); return nil }
                return event
            }
            let f = event.modifierFlags
            let c = ModifierCombo(fn: f.contains(.function),
                                  shift: f.contains(.shift),
                                  control: f.contains(.control),
                                  option: f.contains(.option),
                                  command: f.contains(.command))
            // Keep the largest held combo; flagsChanged arrives once per modifier.
            // Save on release, when Shift+Fn cannot be mistaken for bare Shift.
            if c.modifierCount >= pending.modifierCount && !c.isEmpty {
                pending = c
            } else if c.isEmpty && !pending.isEmpty {
                combo = pending
                stop()
                onChange()
            }
            return event
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        VoiceHotkeys.shared.setShortcutRecording(false)
    }

    private func clear() {
        stop()
        combo = ModifierCombo()
        onChange()
    }
}
