import AppKit
import Carbon.HIToolbox

// =============================================================================
//  Live typing engine for streaming dictation (v3.0).
//
//  Prints recognition results straight into the frontmost app's text field as
//  they arrive, revising ONLY the volatile (not-yet-final) tail:
//
//    committed — typed and frozen. Never touched again: earlier sentences and
//                anything the user edited by hand are untouchable (TZ §5, §16).
//    volatile  — typed but replaceable. A new partial result rewrites it by
//                erasing the differing tail with backspace events and typing
//                the new one. Backspaces never go past what we typed ourselves.
//
//  Rendering is diff-based (only the difference is typed/erased, so the visible
//  text stays stable and event traffic stays small) and coalesced: partial
//  results that arrive while a render is in flight collapse into the newest
//  one, throttled to a minimum interval between renders.
//
//  Every synthetic event has its flags cleared — same contract as
//  `CursorTyping`: while the dictation hotkey is still held (⌘Fn), a stray
//  modifier must never turn our keystrokes or backspaces into shortcuts.
// =============================================================================

final class LiveTyper {
    static let shared = LiveTyper()
    private init() {}

    private let queue = DispatchQueue(label: "com.babelbar.livetyper", qos: .userInitiated)

    // Rendered state (queue-confined): what is physically in the text field now.
    private var committed = ""
    private var typedVolatile = ""

    // Newest desired state (written from the main thread, read on the queue).
    private var latestCommitted = ""
    private var latestVolatile = ""

    private var scheduled = false
    private var lastRenderAt = Date.distantPast
    /// Minimum spacing between renders — fast partial updates collapse instead
    /// of hammering the target app with events.
    private let minRenderInterval: TimeInterval = 0.15
    /// Backspaces per second are capped implicitly by this pacing between events.
    private let keyEventPauseUs: useconds_t = 1200
    private let typingChunkSize = 16   // UTF-16 units per event, as in CursorTyping

    // MARK: - Public API (main thread)

    /// Start a fresh session: forget everything printed before.
    func reset() {
        queue.async {
            self.committed = ""
            self.typedVolatile = ""
            self.latestCommitted = ""
            self.latestVolatile = ""
        }
    }

    /// Target state for the field: `committed` must only ever grow (the caller
    /// guarantees it — committed text is frozen by contract); `volatile` may be
    /// rewritten freely.
    func render(committed c: String, volatile v: String) {
        queue.async {
            self.latestCommitted = c
            self.latestVolatile = v
            self.scheduleNextRender()
        }
    }

    /// Stop revising whatever is typed: the volatile tail becomes committed as
    /// printed. Used when the target app/field changes (TZ §16) — from that
    /// moment BabelBar never sends a backspace into the old field again.
    func freezeVolatile() {
        queue.async {
            guard !self.typedVolatile.isEmpty else { return }
            self.committed += self.typedVolatile
            self.typedVolatile = ""
            self.latestCommitted = self.committed
            self.latestVolatile = ""
        }
    }

    /// Everything this session has typed so far (committed + volatile), for
    /// correction learning. Async — the completion runs on the main thread.
    func typedText(_ completion: @escaping (String) -> Void) {
        queue.async {
            let text = self.committed + self.typedVolatile
            DispatchQueue.main.async { completion(text) }
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
        let targetC = latestCommitted
        let targetV = latestVolatile

        // Committed text is grow-only. A non-append change would mean the caller
        // rewrote history — we keep what's printed and ignore it (never delete
        // frozen text; TZ §16: never damage user text for a recognition fix).
        if targetC != committed {
            if targetC.hasPrefix(committed) {
                type(String(targetC.dropFirst(committed.count)))
                committed = targetC
            } else {
                NSLog("BabelBar LiveTyper: non-append committed change ignored")
                latestCommitted = committed   // don't fight the caller forever
            }
        }

        // Volatile: replace the differing tail — common prefix stays on screen.
        if targetV != typedVolatile {
            let prefix = Self.commonPrefixLength(typedVolatile, targetV)
            let deleteCount = typedVolatile.count - prefix
            let insert = String(targetV.dropFirst(prefix))
            if deleteCount > 0 { backspace(deleteCount) }
            if !insert.isEmpty { type(insert) }
            typedVolatile = targetV
        }

        lastRenderAt = Date()
        if latestCommitted != targetC || latestVolatile != targetV {
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
            usleep(keyEventPauseUs)
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
