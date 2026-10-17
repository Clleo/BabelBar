import AppKit
import Carbon.HIToolbox

/// Inserts recognized text into the frontmost app.
/// Default method is `paste`: stash the clipboard → write our text → wait for the dictation
/// modifiers to be released → ⌘V → restore the clipboard. This is far more reliable than
/// per-character key synthesis for long/multilingual text (mirrors FreeFlow / Wispr Flow),
/// and avoids the "text not inserted / focus jumps to Dock" failure of typing while a
/// modifier is still held.
enum TextInserter {
    static func insert(_ text: String, method: InsertMethod) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        switch method {
        case .type:  CursorTyping.type(t)
        case .paste: paste(t)
        }
    }

    static func insertDictation(_ text: String, method: InsertMethod) {
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        let spaced = LiveJoin.spaceAfterPunctuation(base, atEnd: true)
        switch method {
        case .type: CursorTyping.type(spaced)
        case .paste: paste(spaced)
        }
    }

    // MARK: - Clipboard paste

    private static func paste(_ text: String) {
        let trailingSpaces = text.reversed().prefix(while: { $0 == " " }).count
        let payload = String(text.dropLast(trailingSpaces))
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        pb.clearContents()
        pb.setString(payload, forType: .string)
        // Transient markers so clipboard managers (Maccy, Raycast, Paste, …) skip this entry.
        for t in transientTypes { pb.setString("", forType: t) }
        let writtenChange = pb.changeCount

        DispatchQueue.global(qos: .userInitiated).async {
            waitForModifiersReleased()       // never ⌘V while Fn/Shift is still held
            usleep(30_000)
            postCmdV()
            usleep(120_000)                  // let the target app consume the paste
            for _ in 0..<trailingSpaces { _ = postSpace(); usleep(15_000) }
            DispatchQueue.main.async { restore(saved, to: pb, ifChangeCount: writtenChange, wrote: payload) }
        }
    }

    /// Paste one append-only live fragment while Fn may still be held. Each
    /// fragment owns the pasteboard until the destination has consumed ⌘V.
    /// LivePasteSession serializes calls so fragments cannot overwrite each other.
    @MainActor
    static func pasteLive(_ text: String, destinationPID: pid_t) async -> Bool {
        guard !text.isEmpty,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == destinationPID else { return false }
        // Some rich editors trim spaces at the edges of a paste. Send boundary
        // spaces as ordinary key events so punctuation at the end of a phrase
        // still leaves a real space when Fn is released.
        let leadingSpaces = text.prefix(while: { $0 == " " }).count
        let withoutLeading = String(text.dropFirst(leadingSpaces))
        let trailingSpaces = withoutLeading.reversed().prefix(while: { $0 == " " }).count
        let payload = String(withoutLeading.dropLast(trailingSpaces))
        if payload.isEmpty {
            for _ in 0..<(leadingSpaces + trailingSpaces) {
                guard postSpace() else { return false }
            }
            return true
        }
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        pb.setString(payload, forType: .string)
        for type in transientTypes { pb.setString("", forType: type) }
        let writtenChange = pb.changeCount

        // Let pasteboard observers see the new value before the key event. The
        // event itself explicitly carries Command, regardless of held Fn.
        await delay(30)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destinationPID else {
            restore(saved, to: pb, ifChangeCount: writtenChange, wrote: payload)
            return false
        }
        for _ in 0..<leadingSpaces {
            guard postSpace() else {
                restore(saved, to: pb, ifChangeCount: writtenChange, wrote: payload)
                return false
            }
        }
        if leadingSpaces > 0 { await delay(20) }
        postCmdV()
        await delay(180)
        for _ in 0..<trailingSpaces {
            guard postSpace() else {
                restore(saved, to: pb, ifChangeCount: writtenChange, wrote: payload)
                return false
            }
        }
        await delay(70)
        restore(saved, to: pb, ifChangeCount: writtenChange, wrote: payload)
        return true
    }

    private static func delay(_ milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }

    private static let transientTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.TransientType"),
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.AutoGeneratedType"),
        .init("de.petermaurer.TransientPasteboardType"),
    ]

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { dict[type] = data } }
            return dict
        }
    }

    /// Restore the saved clipboard — but only if it still holds exactly what we wrote (or
    /// nothing changed), so we never clobber something the user copied in the meantime.
    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]],
                                to pb: NSPasteboard, ifChangeCount expected: Int, wrote: String) {
        let stillOurs = pb.string(forType: .string) == wrote
        guard pb.changeCount == expected || stillOurs else { return }
        pb.clearContents()
        let items: [NSPasteboardItem] = saved.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    private static func waitForModifiersReleased(maxWaitMs: Int = 800) {
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .control, .option, .function]
        var waited = 0
        while !NSEvent.modifierFlags.isDisjoint(with: relevant), waited < maxWaitMs {
            usleep(20_000); waited += 20
        }
    }

    private static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private static func postSpace() -> Bool {
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: false) else { return false }
        down.flags = []; up.flags = []
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}

/// Serializes short pasteboard transactions for live WhisperKit output.
/// A completed fragment is never replayed, including during final flush.
@MainActor
final class LivePasteSession {
    var onInvalidated: (() -> Void)?
    private let destinationPID: pid_t
    private var pending: [String] = []
    private var worker: Task<Void, Never>?
    private var cancelled = false

    init(destinationPID: pid_t) { self.destinationPID = destinationPID }

    func append(_ text: String) {
        guard !cancelled, !text.isEmpty else { return }
        pending.append(text)
        NSLog("BabelBar live-whisperkit: queued paste (%ld characters, %ld pending)", text.count, pending.count)
        if worker == nil { startWorker() }
    }

    func flush() async {
        await worker?.value
    }

    func cancel() {
        cancelled = true
        pending.removeAll()
        worker?.cancel()
        onInvalidated = nil
    }

    private func startWorker() {
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.cancelled, !self.pending.isEmpty {
                let text = self.pending.removeFirst()
                guard await TextInserter.pasteLive(text, destinationPID: self.destinationPID) else {
                    if !self.cancelled { self.onInvalidated?() }
                    break
                }
                NSLog("BabelBar live-whisperkit: paste event sent (%ld characters)", text.count)
            }
            self.worker = nil
        }
    }
}
