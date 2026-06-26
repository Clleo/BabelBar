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

    /// Simulates ⌘C in the frontmost app to copy the current selection,
    /// then returns the new pasteboard contents.
    static func copySelectionAndRead() -> String? {
        let pb = NSPasteboard.general
        let previousChange = pb.changeCount

        simulateCmdC()

        // Give the frontmost app a brief moment to write to the pasteboard.
        let deadline = Date().addingTimeInterval(0.4)
        while pb.changeCount == previousChange && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard pb.changeCount != previousChange else { return nil }
        return pb.string(forType: .string)
    }

    private static func simulateCmdC() {
        postShortcut(virtualKey: 0x08) // C
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
