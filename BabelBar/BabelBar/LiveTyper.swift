import AppKit
import Carbon.HIToolbox

// =============================================================================
//  Live typing engine for streaming dictation (v3.0).
//
//  Prints recognition results straight into the frontmost app's text field as
//  they arrive, revising only the not-yet-frozen tail:
//
//    target (String) — the FULL desired text of this dictation session, from
//                      its first character to the current cursor position.
//    frozen (Int)    — how many leading Characters may never be backspaced:
//                      earlier sentences and everything the controller froze.
//
//  Rendering is a single diff of (what's on screen) vs (target): only the
//  difference is erased with backspaces and re-typed, so the visible text
//  stays stable and event traffic stays small. Updates are coalesced (a
//  minimum interval between renders; intermediate states collapse into the
//  newest one) and serialized on a private queue.
//
//  Every synthetic event has its flags cleared — same contract as
//  `CursorTyping`: while the dictation hotkey is still held (⌘Fn), a stray
//  modifier must never turn our keystrokes or backspaces into shortcuts.
// =============================================================================

final class LiveTyper {
    static let shared = LiveTyper()
    private init() {}

    private let queue = DispatchQueue(label: "com.babelbar.livetyper", qos: .userInitiated)

    // Rendered state (queue-confined): what is physically in the field now.
    private var screen = ""
    private var frozenLen = 0

    // Newest desired state (written from the main thread, read on the queue).
    private var latestTarget = ""
    private var latestFrozen = 0

    private var scheduled = false
    private var lastRenderAt = Date.distantPast
    /// Minimum spacing between renders — fast partial updates collapse instead
    /// of hammering the target app with events.
    private let minRenderInterval: TimeInterval = 0.15
    private let typingChunkSize = 16   // UTF-16 units per event, as in CursorTyping

    // MARK: - Public API (main thread)

    /// Start a fresh session: forget everything printed before.
    func reset() {
        queue.async {
            self.screen = ""
            self.frozenLen = 0
            self.latestTarget = ""
            self.latestFrozen = 0
        }
    }

    /// Full desired session text, and how many leading Characters are frozen
    /// (the caller guarantees the frozen prefix of `target` never changes —
    /// so the typer will never backspace into it).
    func render(target: String, frozen: Int) {
        queue.async {
            self.latestTarget = target
            self.latestFrozen = frozen
            self.scheduleNextRender()
        }
    }

    /// Stop revising whatever is on screen: everything typed so far becomes
    /// frozen. Used when the target app/field changes (TZ §16) — from that
    /// moment BabelBar never sends a backspace into the old field again.
    func freezeAll() {
        queue.async {
            self.frozenLen = self.screen.count
            self.latestFrozen = self.frozenLen
            self.latestTarget = self.screen
        }
    }

    // MARK: - Rendering (private queue)

    private func scheduleNextRender() {
        guard !scheduled else { return }
        scheduled = true
        let delay = max(0, minRenderInterval - Date().timeIntervalSince(lastRenderAt))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.performRender()
        }
    }

    private func performRender() {
        let target = latestTarget
        let frozen = min(latestFrozen, screen.count)

        // Chars of the current screen that survive: the common prefix, but
        // never less than the frozen boundary (a target that disagrees with
        // frozen text loses — the screen keeps its version; TZ §16).
        let prefix = Self.commonPrefixLength(screen, target)
        let keep = max(prefix, frozen)

        if keep < screen.count {
            backspace(screen.count - keep)
        }
        let survivor = String(screen.prefix(keep))
        let suffix = String(target.dropFirst(keep))
        if !suffix.isEmpty {
            type(suffix)
        }
        screen = survivor + suffix

        lastRenderAt = Date()
        if latestTarget != target || min(latestFrozen, screen.count) != frozen {
            scheduleNextRender()   // a newer target arrived while we were typing
        }
    }

    // MARK: - Event synthesis

    /// Unicode keystrokes in small chunks — a single giant event is silently
    /// dropped by some apps (terminals / Electron). Flags cleared per event.
    private func type(_ text: String) {
        guard !text.isEmpty else { return }
        let units = Array(text.utf16)
        let src = CGEventSource(stateID: .combinedSessionState)
        var i = 0
        while i < units.count {
            let slice = Array(units[i ..< min(i + typingChunkSize, units.count)])
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { break }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
            up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: slice)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            i += typingChunkSize
            usleep(1500)
        }
    }

    /// Plain backspaces (kVK_Delete = 0x33), one per *grapheme* — that is what
    /// a real editor deletes per keypress. Flags cleared so a held modifier
    /// can't turn this into ⌘⌫ / ⌥⌫ (delete-to-start-of-line/word).
    private func backspace(_ count: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0 ..< min(count, 400) {   // hard cap: never erase more than a screenful
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false) else { break }
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(1200)
        }
    }

    // MARK: - Pure helpers

    /// Longest common prefix of two strings, in Characters (grapheme
    /// clusters): one backspace deletes one grapheme.
    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var n = 0
        var ia = a.startIndex
        var ib = b.startIndex
        while ia < a.endIndex, ib < b.endIndex, a[ia] == b[ib] {
            n += 1
            a.formIndex(after: &ia)
            b.formIndex(after: &ib)
        }
        return n
    }
}
