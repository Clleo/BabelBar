import AppKit

enum ClipboardHelper {

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func read() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// Simulates ⌘V in the frontmost app (pastes the current clipboard).
    /// Requires Accessibility permission.
    static func paste() {
        postShortcut(virtualKey: 0x09) // V
    }

    /// Posts ⌘+<key> as a synthetic key combo to the HID event tap.
    private static func postShortcut(virtualKey: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true) // Command
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
        keyUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

        let loc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: loc)
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
    }
}
