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
@MainActor
final class AXLiveTextTarget: LiveTextTarget {
    let element: AXUIElement
    let pid: pid_t
    private let canSetText: Bool

    init?() {
        guard AXIsProcessTrusted(), let element = Self.focusedElement(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        self.element = element
        self.pid = pid
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else { return nil }
        var canSelect = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &canSelect) == .success,
              canSelect.boolValue else { return nil }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        canSetText = settable.boolValue
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard snapshot() != nil else { return nil }
    }

    /// Asks an app to expose its accessibility tree (Electron: AXManualAccessibility,
    /// Chromium/WebKit: AXEnhancedUserInterface). Native editors ignore both.
    static func requestAccessibilityTree(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    static func focusedElement() -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    func snapshot() -> LiveFieldSnapshot? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = Self.focusedElement(), CFEqual(focused, element) else { return nil }
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

    private func select(_ range: NSRange) -> Bool {
        var range = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    func replace(_ range: NSRange, with text: String, expected: LiveFieldSnapshot) async -> LiveFieldSnapshot? {
        guard !Task.isCancelled, !text.isEmpty || canSetText, snapshot() == expected, select(range) else { return nil }
        var current = LiveFieldSnapshot(value: expected.value, selection: range)
        guard snapshot() == current else { return nil }
        if canSetText {
            guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return nil }
            let next = Self.replacing(current, with: text)
            return await acknowledge(next, replacing: range)
        }
        // Electron/browser editors may expose the selection but not an AX text
        // setter. Replace the verified selection with process-targeted Unicode
        // input, checking focus, value and caret before every chunk. Never delete
        // relative to an unverified cursor, never retry a failed write blindly.
        let chunks = Self.chunks(text)
        guard !chunks.isEmpty else { return nil } // no safe empty replacement without AX setter
        for chunk in chunks {
            guard !Task.isCancelled, snapshot() == current else { return nil }
            let units = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return nil }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: LiveInputGuard.marker)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.postToPid(pid)
            }
            let next = Self.replacing(current, with: chunk)
            guard let acknowledged = await acknowledge(next) else { return nil }
            current = acknowledged
        }
        return current
    }

    private func acknowledge(_ expected: LiveFieldSnapshot, replacing replacedRange: NSRange? = nil) async -> LiveFieldSnapshot? {
        // Some editors apply AX/event writes on their next run-loop iteration;
        // browsers and Electron can take a few hundred milliseconds. Waiting
        // costs nothing, giving up ends the whole session.
        let deadline = Date().addingTimeInterval(0.6)
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
            do { try await Task.sleep(nanoseconds: 8_000_000) } catch { return nil }
        }
        return nil
    }

    static func replacing(_ old: LiveFieldSnapshot, with text: String) -> LiveFieldSnapshot {
        LiveFieldSnapshot(value: (old.value as NSString).replacingCharacters(in: old.selection, with: text),
                          selection: NSRange(location: old.selection.location + text.utf16.count, length: 0))
    }

    static func chunks(_ text: String) -> [String] {
        var result: [String] = [], chunk = ""
        for character in text {
            let next = String(character)
            if !chunk.isEmpty, chunk.utf16.count + next.utf16.count > 16 { result.append(chunk); chunk = "" }
            chunk += next // never split a surrogate pair or grapheme cluster
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
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
        guard let target, let expected, target.snapshot() == expected else { return false }
        guard Array(text.prefix(frozen)) == Array(screen.prefix(frozen)), text.count >= frozen else { return false }
        let keep = Self.commonPrefixLength(screen, text)
        if text != screen {
            let prefix = String(screen.prefix(keep)).utf16.count
            let range = NSRange(location: origin + prefix,
                                length: screen.utf16.count - prefix + initialLength)
            let generation = epoch
            guard let next = await target.replace(range, with: String(text.dropFirst(keep)), expected: expected),
                  !Task.isCancelled, generation == epoch else { return false }
            self.expected = next; screen = text; initialLength = 0
        }
        frozen = max(frozen, min(boundary, screen.count))
        return true
    }

    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix(while: { $0 == $1 }).count
    }
}
