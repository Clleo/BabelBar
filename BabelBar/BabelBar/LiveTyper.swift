import AppKit

/// Values and ranges use UTF-16, as required by the macOS Accessibility API.
struct LiveFieldSnapshot: Equatable {
    var value: String
    var selection: NSRange
}

@MainActor
protocol LiveTextTarget: AnyObject {
    func snapshot() -> LiveFieldSnapshot?
    func replace(_ range: NSRange, with text: String, expected: LiveFieldSnapshot) async -> LiveFieldSnapshot?
}

/// A target is bound to one AX element and process for its entire lifetime.
/// No global Backspace or whole-field value replacement is used.
final class AXLiveTextTarget: LiveTextTarget, @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t
    /// The OS reports `kAXSelectedTextAttribute` as settable. Some Chromium/Electron
    /// editors report this but the write is a no-op (their AX bridge implements the
    /// getter, not the setter) — `replace()` verifies the actual effect and falls back
    /// to synthetic keystrokes the first time that happens, then remembers not to try
    /// the AX setter on this target again.
    private var trustAXTextSetter: Bool
    private var initialSnapshot: LiveFieldSnapshot?

    /// The Accessibility lookups are completed by `probe` off the main thread;
    /// this initializer only attaches that already-validated result to the typer.
    init(probe: AXLiveTextTargetProbe) {
        self.element = probe.element
        self.pid = probe.pid
        self.trustAXTextSetter = probe.trustAXTextSetter
        self.initialSnapshot = probe.snapshot
    }

    /// Resolve and validate the focused accessibility element away from the UI
    /// thread. Asking an Electron/Chromium app for its tree can block noticeably.
    nonisolated static func probe(expectedPID: pid_t) -> AXLiveTextTargetProbe? {
        guard AXIsProcessTrusted() else { Self.log("not AXIsProcessTrusted"); return nil }
        let pid = expectedPID
        guard let element = Self.focusedElement() else {
            Self.log("no focused UI element")
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.2)
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else {
            Self.log("focused element belongs to a different process (frontmost=\(pid), element=\(elementPID))")
            return nil
        }
        var canSelect = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &canSelect) == .success,
              canSelect.boolValue else {
            Self.log("kAXSelectedTextRangeAttribute not settable (role=\(Self.debugRole(element)))")
            return nil
        }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard let snapshot = Self.readSnapshot(element: element, pid: pid) else {
            Self.log("snapshot() nil right after acquiring the element (role=\(Self.debugRole(element)))")
            return nil
        }
        return AXLiveTextTargetProbe(element: element, pid: pid,
                                     trustAXTextSetter: settable.boolValue, snapshot: snapshot)
    }

    /// Temporary diagnostics for editors that fail to bind — visible in Console.app
    /// (filter: process is BabelBar) without shipping a debug build.
    nonisolated private static func log(_ message: String) { NSLog("BabelBar live-target: %@", message) }
    nonisolated private static func debugRole(_ element: AXUIElement) -> String {
        var role: CFTypeRef?; var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return "\(role as? String ?? "?")/\(subrole as? String ?? "?")"
    }

    /// Asks an app to expose its accessibility tree (Electron: AXManualAccessibility,
    /// Chromium/WebKit: AXEnhancedUserInterface). Native editors ignore both.
    nonisolated static func requestAccessibilityTree(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    nonisolated private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    nonisolated private static func readSnapshot(element: AXUIElement, pid: pid_t) -> LiveFieldSnapshot? {
        guard let focused = Self.focusedElement(), CFEqual(focused, element) else { return nil }
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success,
              let value = raw as? String else { return nil }
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.length >= 0,
              range.location <= value.utf16.count, range.length <= value.utf16.count - range.location else { return nil }
        return LiveFieldSnapshot(value: value, selection: NSRange(location: range.location, length: range.length))
    }

    @MainActor
    func snapshot() -> LiveFieldSnapshot? {
        if let initialSnapshot {
            self.initialSnapshot = nil
            return initialSnapshot
        }
        return Self.readSnapshot(element: element, pid: pid)
    }

    private func select(_ range: NSRange) -> Bool {
        var range = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    @MainActor
    func replace(_ range: NSRange, with text: String, expected: LiveFieldSnapshot) async -> LiveFieldSnapshot? {
        guard !Task.isCancelled else { return nil }
        guard await acknowledge(expected) != nil else {
            Self.log("replace(): field changed before starting")
            return nil
        }
        if trustAXTextSetter {
            let selected = select(range)
            let current = LiveFieldSnapshot(value: expected.value, selection: range)
            if selected, await acknowledge(current) != nil {
                let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
                let next = Self.replacing(current, with: text)
                if status == .success, let result = await acknowledge(next, replacing: range) { return result }
                // Some editors report a settable attribute but reject or ignore
                // writes. Fall back only while the original value is still intact.
                guard let unchanged = snapshot(), unchanged == current else {
                    Self.log("replace(): AX write was not acknowledged and field state changed")
                    return nil
                }
                Self.log("replace(): AX text setter unavailable; using keyboard events")
            } else {
                // Editors that expose a caret but reject an AX selection can still
                // accept process-targeted keyboard events.
                guard let afterSelect = snapshot(), afterSelect.value == expected.value else {
                    Self.log("replace(): selection changed the field unexpectedly")
                    return nil
                }
                Self.log("replace(): AX selection unavailable; using keyboard events")
            }
            trustAXTextSetter = false
        }
        // Electron/browser editors may expose a caret but not a working AX text
        // setter, and some only support MOVING the caret, not selecting an
        // arbitrary range — attempting to select one just snaps back to a
        // collapsed caret. Detect that and fall back to real Backspace
        // keystrokes, which every text field understands natively.
        guard let fallbackStart = snapshot(), fallbackStart.value == expected.value else { return nil }
        var current = fallbackStart
        if range.length > 0 {
            guard let after = await collapseAndDelete(range, in: current) else { return nil }
            current = after
        } else {
            guard current.selection == range || select(range) else { Self.log("replace(): could not move the caret"); return nil }
            let moved = LiveFieldSnapshot(value: expected.value, selection: range)
            guard let acknowledged = await acknowledge(moved) else { Self.log("replace(): caret move never acknowledged"); return nil }
            current = acknowledged
        }
        guard !text.isEmpty else { return current }
        return await typeCharacters(text, from: current)
    }

    /// Moves the caret to the end of `range` and removes it with real Backspace
    /// keystrokes — the fallback for editors that only support a collapsed caret
    /// over Accessibility, never an arbitrary selection.
    private func collapseAndDelete(_ range: NSRange, in current: LiveFieldSnapshot) async -> LiveFieldSnapshot? {
        let caret = NSRange(location: range.location + range.length, length: 0)
        guard current.selection == caret || select(caret) else { Self.log("collapseAndDelete: could not move the caret to the end of the range"); return nil }
        let atCaret = LiveFieldSnapshot(value: current.value, selection: caret)
        guard var confirmed = await acknowledge(atCaret) else {
            Self.log("collapseAndDelete: caret move never acknowledged, last seen: \(snapshot().map { Self.diff(atCaret, $0) } ?? "snapshot() nil")")
            return nil
        }
        let remaining = (current.value as NSString).substring(with: range)
        for character in remaining.reversed() {
            guard !Task.isCancelled else { return nil }
            let length = String(character).utf16.count
            let deleted = NSRange(location: confirmed.selection.location - length, length: length)
            let expected = LiveFieldSnapshot(value: (confirmed.value as NSString).replacingCharacters(in: deleted, with: ""),
                                             selection: NSRange(location: deleted.location, length: 0))
            guard let acknowledged = await postAndAcknowledge(keyCode: 51, text: nil,
                                                               before: confirmed, expected: expected) else {
                Self.log("collapseAndDelete: backspace was not acknowledged; \(snapshot().map { Self.diff(expected, $0) } ?? "snapshot() nil")")
                return nil
            }
            confirmed = acknowledged
        }
        return confirmed
    }

    /// Some editors accept only the first few events from a burst, then stop updating
    /// their AX value. Wait for each grapheme to appear before sending the next one.
    private func typeCharacters(_ text: String, from start: LiveFieldSnapshot) async -> LiveFieldSnapshot? {
        guard let before = snapshot(), before == start else {
            Self.log("typeCharacters: field changed before typing — \(snapshot().map { Self.diff(start, $0) } ?? "snapshot() nil")")
            return nil
        }
        var current = start
        for character in text {
            guard !Task.isCancelled else { return nil }
            let part = String(character)
            let expected = Self.replacing(current, with: part)
            guard let acknowledged = await postAndAcknowledge(keyCode: 0, text: part,
                                                               before: current, expected: expected) else {
                Self.log("typeCharacters: character was not acknowledged; \(snapshot().map { Self.diff(expected, $0) } ?? "snapshot() nil")")
                return nil
            }
            current = acknowledged
        }
        return current
    }

    /// Retry only when the field is still exactly as it was before the event.
    /// That avoids doubling a character that arrived late or replacing user edits.
    private func postAndAcknowledge(keyCode: CGKeyCode, text: String?,
                                    before: LiveFieldSnapshot,
                                    expected: LiveFieldSnapshot) async -> LiveFieldSnapshot? {
        for _ in 0..<2 {
            guard !Task.isCancelled, snapshot() == before else { return nil }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return nil }
            let units = text.map { Array($0.utf16) }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: LiveInputGuard.marker)
                if let units { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
                event.postToPid(pid)
            }
            if let acknowledged = await acknowledge(expected) { return acknowledged }
        }
        return nil
    }

    private func acknowledge(_ expected: LiveFieldSnapshot, replacing replacedRange: NSRange? = nil) async -> LiveFieldSnapshot? {
        // Some editors apply AX/event writes on their next run-loop iteration.
        // Chromium/Electron in particular serialize their accessibility tree
        // separately from the keystroke itself, and that readback can lag well
        // over half a second under load — waiting costs nothing, giving up ends
        // the whole session.
        let deadline = Date().addingTimeInterval(1.8)
        while Date() < deadline {
            guard !Task.isCancelled else { return nil }
            if let current = snapshot() {
                if current == expected { return expected }
                // AX setters differ in whether they collapse the replacement.
                // Collapse only our own replacement selection, after checking
                // the exact resulting value; never move an unrelated caret.
                if let replacedRange, current.value == expected.value {
                    let inserted = NSRange(location: replacedRange.location,
                                           length: expected.selection.location - replacedRange.location)
                    if current.selection == replacedRange || current.selection == inserted {
                        guard !Task.isCancelled, select(expected.selection) else { return nil }
                        if snapshot() == expected { return expected }
                    }
                }
            }
            do { try await Task.sleep(nanoseconds: 15_000_000) } catch { return nil }
        }
        return nil
    }

    private static func diff(_ expected: LiveFieldSnapshot, _ actual: LiveFieldSnapshot) -> String {
        "expected value len=\(expected.value.utf16.count) sel=\(expected.selection), got value len=\(actual.value.utf16.count) sel=\(actual.selection)"
    }

    static func replacing(_ old: LiveFieldSnapshot, with text: String) -> LiveFieldSnapshot {
        LiveFieldSnapshot(value: (old.value as NSString).replacingCharacters(in: old.selection, with: text),
                          selection: NSRange(location: old.selection.location + text.utf16.count, length: 0))
    }

    /// One grapheme cluster per synthetic keystroke. A batched multi-character
    /// `keyboardSetUnicodeString` payload is valid CGEvent API, but several
    /// Chromium/Electron input pipelines process it as a single physical key
    /// press and keep only part of the string — observed dropping 1 of 3
    /// characters in a chunk. One event per character matches how a real key
    /// press arrives, which every text field's input handling is built for.
    static func chunks(_ text: String) -> [String] {
        text.map(String.init)
    }
}

/// A validated, immutable handoff from the background Accessibility probe to the
/// main-actor target. AXUIElement is a CoreFoundation handle, so it is intentionally
/// transferred without Swift value-level Sendable checking.
struct AXLiveTextTargetProbe: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t
    let trustAXTextSetter: Bool
    let snapshot: LiveFieldSnapshot
}

/// Interrupt on actual typing/clicking, including an edit followed by undo that
/// could otherwise leave the same AX value. Our own synthetic events are tagged.
@MainActor
final class LiveInputGuard {
    static let marker: Int64 = 0x424142454C
    private var global: Any?
    private var local: Any?
    func start(_ interrupt: @escaping () -> Void) {
        stop()
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let handle: (NSEvent) -> Void = { event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.marker { interrupt() }
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle)
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in handle(event); return event }
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
    }
}

/// Serial, acknowledged edits. A new freeze boundary only takes effect AFTER
/// the corresponding replacement succeeds, even when updates are coalesced.
@MainActor
final class LiveTyper {
    static let shared = LiveTyper()
    var onInvalidated: (() -> Void)?
    private var target: LiveTextTarget?
    private var expected: LiveFieldSnapshot?
    private var origin = 0
    private var initialLength = 0
    private(set) var screen = ""
    private var frozen = 0
    private var desired = ""
    private var desiredFrozen = 0
    private var task: Task<Void, Never>?
    private var epoch = 0

    @discardableResult
    func begin(target: LiveTextTarget) -> Bool {
        cancel()
        guard let snapshot = target.snapshot() else { return false }
        self.target = target; expected = snapshot
        origin = snapshot.selection.location; initialLength = snapshot.selection.length
        screen = ""; frozen = 0; desired = ""; desiredFrozen = 0
        return true
    }

    func isCurrent() -> Bool { target?.snapshot() == expected && expected != nil }

    func render(target text: String, frozen boundary: Int) {
        guard target != nil else { return }
        desired = text; desiredFrozen = boundary
        guard task == nil else { return }
        let generation = epoch
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            // Coalesce partials, not the final acknowledgement or ownership checks.
            await Task.yield()
            while !Task.isCancelled, self.epoch == generation {
                let text = self.desired, boundary = self.desiredFrozen
                guard await self.apply(text, boundary: boundary) else {
                    if self.epoch == generation { self.cancel(); self.onInvalidated?() }
                    return
                }
                if self.desired == text, self.desiredFrozen == boundary { break }
            }
            if self.epoch == generation { self.task = nil }
        }
    }

    func flush() async { await task?.value }

    func cancel() {
        epoch += 1; task?.cancel(); task = nil
        target = nil; expected = nil
    }

    private func apply(_ text: String, boundary: Int) async -> Bool {
        guard let target, let expected else { NSLog("BabelBar live-typer: apply() with no target"); return false }
        // AX readback may briefly lag a write that was already acknowledged.
        // Wait a short, bounded interval before treating a mismatch as an edit.
        let deadline = Date().addingTimeInterval(0.35)
        while target.snapshot() != expected {
            guard !Task.isCancelled, Date() < deadline else {
                NSLog("BabelBar live-typer: apply() aborted — field changed or lost focus")
                return false
            }
            do { try await Task.sleep(nanoseconds: 25_000_000) } catch { return false }
        }
        guard Array(text.prefix(frozen)) == Array(screen.prefix(frozen)), text.count >= frozen else {
            NSLog("BabelBar live-typer: apply() aborted — new text does not extend the already-frozen prefix")
            return false
        }
        let keep = Self.commonPrefixLength(screen, text)
        if text != screen {
            let prefix = String(screen.prefix(keep)).utf16.count
            let range = NSRange(location: origin + prefix,
                                length: screen.utf16.count - prefix + initialLength)
            let generation = epoch
            guard let next = await target.replace(range, with: String(text.dropFirst(keep)), expected: expected),
                  !Task.isCancelled, generation == epoch else {
                NSLog("BabelBar live-typer: apply() — target.replace() failed or was superseded")
                return false
            }
            self.expected = next; screen = text; initialLength = 0
        }
        frozen = max(frozen, min(boundary, screen.count))
        return true
    }

    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix(while: { $0 == $1 }).count
    }
}
