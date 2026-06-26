import AppKit
import Carbon.HIToolbox

/// A user-configurable keyboard shortcut: a key code plus modifier flags.
/// Stored in settings and used both for Carbon hotkeys and the global NSEvent monitor.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var command: Bool = false
    var shift: Bool = false
    var option: Bool = false
    var control: Bool = false

    /// Carbon modifier mask for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if command { m |= UInt32(cmdKey) }
        if shift   { m |= UInt32(shiftKey) }
        if option  { m |= UInt32(optionKey) }
        if control { m |= UInt32(controlKey) }
        return m
    }

    /// NSEvent modifier flags (for comparing against live events).
    var eventModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if command { f.insert(.command) }
        if shift   { f.insert(.shift) }
        if option  { f.insert(.option) }
        if control { f.insert(.control) }
        return f
    }

    var hasModifier: Bool { command || shift || option || control }

    var keyName: String { KeyCodeMap.name(for: keyCode) }

    /// Human-readable badge, e.g. "⌥ + Space" or "⇧ + ⌘ + 2".
    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined(separator: "  +  ")
    }

    /// Badge for a double-tap shortcut, e.g. "⌘ + C + C".
    var displayDoubled: String { display + "  +  " + keyName }
}

/// Maps macOS virtual key codes to readable names.
enum KeyCodeMap {
    static func name(for code: UInt32) -> String {
        if let n = table[code] { return n }
        return "Key \(code)"
    }

    private static let table: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}
