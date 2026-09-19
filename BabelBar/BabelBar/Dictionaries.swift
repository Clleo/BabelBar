import Foundation
import AppKit

// =============================================================================
//  BabelBar dictionaries (v3.0 live dictation):
//   • DeveloperDictionary    — built-in tech terminology + phonetic aliases
//   • PersonalDictionaryStore — user rules (higher priority) + learned candidates
//   • FrequencyTracker       — usage counters that bias future recognition
//   • TranscriptCorrector    — word-boundary replacement engine
//   • DictionaryContext      — contextualStrings for the speech request
//   • CorrectionObserver     — learns personal rules from manual edits (AX, opt-in)
//  Everything lives locally on the Mac; nothing is ever sent anywhere (TZ §14).
// =============================================================================

/// One replacement rule: `spoken` is what recognition produces, `written` is
/// what gets typed instead. Matching is case-insensitive, on word boundaries,
/// with ё folded to е (the recognizer writes both spellings).
struct DictEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var spoken: String
    var written: String
    var enabled: Bool = true

    init(spoken: String, written: String, enabled: Bool = true) {
        self.spoken = spoken
        self.written = written
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        spoken = (try? c.decode(String.self, forKey: .spoken)) ?? ""
        written = (try? c.decode(String.self, forKey: .written)) ?? ""
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }
}

// MARK: - Developer Dictionary (built-in)

/// Built-in developer terminology (TZ §8) and phonetic aliases (TZ §9) for
/// mixed Russian speech with English tech terms.
///
/// Kept as code — not a bundled JSON — so it is versioned with the app and
/// reviewed in diffs; extending it means adding rows below.
enum DeveloperDictionary {

    /// Canonical terms. These are fed to `contextualStrings` so the recognizer
    /// *prefers* writing them correctly; they are never force-replaced.
    static let terms: [String] = [
        // Languages & frameworks
        "JavaScript", "TypeScript", "Swift", "SwiftUI", "Python", "PHP", "React",
        "Next.js", "Vue", "Svelte", "Node.js",
        // Web
        "HTML", "CSS", "SCSS", "REST", "GraphQL", "WebSocket",
        // Data
        "PostgreSQL", "MariaDB", "Redis", "Meilisearch", "Supabase",
        // Infra & tools
        "Vercel", "Cloudflare", "GitHub", "GitLab", "Docker", "Git", "Homebrew",
        // AI
        "OpenAI", "ChatGPT", "Codex", "Claude", "Gemini", "DeepSeek", "Cursor",
        "LLM", "RAG", "MCP",
        // General
        "API", "SDK", "CLI", "npm", "pnpm",
        // Conventions & React hooks
        "camelCase", "PascalCase", "snake_case",
        "useEffect", "useState", "useMemo", "useCallback",
        // The app itself
        "BabelBar",
    ]

    /// What a Russian speaker *says* (and the recognizer therefore writes in
    /// Cyrillic) → the correct written form. These ARE force-replaced in the
    /// transcript — hearing "тайп скрипт" must print "TypeScript".
    ///
    /// Both single-word and spaced spellings are listed: the recognizer is
    /// inconsistent about whether "тайпскрипт" arrives as one token or two.
    static let aliases: [(spoken: String, written: String)] = [
        // From the TZ
        ("некст джей эс", "Next.js"),
        ("некст жс", "Next.js"),
        ("тайп скрипт", "TypeScript"),
        ("тайпскрипт", "TypeScript"),
        ("супа бейс", "Supabase"),
        ("супабейз", "Supabase"),
        ("клауд флэр", "Cloudflare"),
        ("клаудфлер", "Cloudflare"),
        ("юз эффект", "useEffect"),
        ("гит хаб", "GitHub"),
        ("гитхаб", "GitHub"),
        ("постгрес", "PostgreSQL"),
        ("постгри", "PostgreSQL"),
        ("свифт ю ай", "SwiftUI"),
        ("эм си пи", "MCP"),
        // Common pronunciations the recognizer transcribes this way
        ("джава скрипт", "JavaScript"),
        ("джаваскрипт", "JavaScript"),
        ("реакт", "React"),
        ("свелт", "Svelte"),
        ("вью джей эс", "Vue"),
        ("ноуд джей эс", "Node.js"),
        ("ноуд джи эс", "Node.js"),
        ("ноуд жс", "Node.js"),
        ("гит лаб", "GitLab"),
        ("гитлаб", "GitLab"),
        ("гит", "Git"),
        ("докер", "Docker"),
        ("редис", "Redis"),
        ("мария дб", "MariaDB"),
        ("мария ди би", "MariaDB"),
        ("мейли серч", "Meilisearch"),
        ("мили серч", "Meilisearch"),
        ("версель", "Vercel"),
        ("опен ай ай", "OpenAI"),
        ("опен ай", "OpenAI"),
        ("чат джи пи ти", "ChatGPT"),
        ("чат жпт", "ChatGPT"),
        ("джемини", "Gemini"),
        ("дип сик", "DeepSeek"),
        ("дипсик", "DeepSeek"),
        ("пайтон", "Python"),
        ("пехапе", "PHP"),
        ("пэ ха пэ", "PHP"),
        ("свифт", "Swift"),
        ("граф кюэл", "GraphQL"),
        ("графкьюэл", "GraphQL"),
        ("веб сокет", "WebSocket"),
        ("вебсокет", "WebSocket"),
        ("эл эл эм", "LLM"),
        ("элэлэм", "LLM"),
        ("раг", "RAG"),
        ("рэг", "RAG"),
        ("си эл ай", "CLI"),
        ("сиэлай", "CLI"),
        ("эс ди кей", "SDK"),
        ("эн пи эм", "npm"),
        ("нпм", "npm"),
        ("пи эн пм", "pnpm"),
        ("пнпм", "pnpm"),
        ("хоумбрю", "Homebrew"),
        ("кэмел кейс", "camelCase"),
        ("камел кейс", "camelCase"),
        ("паскаль кейс", "PascalCase"),
        ("снейк кейс", "snake_case"),
        ("юс стейт", "useState"),
        ("юс мемо", "useMemo"),
        ("юс колбэк", "useCallback"),
        ("юз колбэк", "useCallback"),
        ("апи", "API"),
        ("а пи и", "API"),
        ("бабел бар", "BabelBar"),
        ("бабелбар", "BabelBar"),
    ]

    /// All built-in rules as `DictEntry`-shaped data.
    static var entries: [DictEntry] { aliases.map { DictEntry(spoken: $0.spoken, written: $0.written) } }
}

// MARK: - Transcript corrector

/// Applies dictionary rules to transcript text on word boundaries. Pure
/// Foundation, no side effects — deliberately styled after `VoiceCommands`:
/// tokens are compared by a normalized core (lowercased, ё→е, edge punctuation
/// stripped) and the longest phrase match wins, so "тайп скрипт" is never
/// partially replaced. Personal rules are matched before developer aliases
/// (caller passes them concatenated in priority order).
enum TranscriptCorrector {

    /// Replacements applied to `text`. Returns the text unchanged when no rule
    /// matches. Leading/trailing punctuation of a matched span is preserved,
    /// the written form itself is used verbatim (camelCase never re-cased).
    static func correct(_ text: String, rules: [DictEntry]) -> String {
        let active = rules.filter { $0.enabled && !$0.spoken.isEmpty && !$0.written.isEmpty }
        guard !active.isEmpty else { return text }

        var table: [String: String] = [:]
        var maxWords = 1
        for rule in active {
            let key = normalized(rule.spoken)
            guard !key.isEmpty else { continue }
            // First rule for an identical spoken phrase wins → caller's order = priority.
            if table[key] == nil { table[key] = rule.written }
            maxWords = max(maxWords, key.components(separatedBy: " ").count)
        }

        return text.components(separatedBy: "\n").map { line in
            correctLine(line, table: table, maxWords: maxWords)
        }.joined(separator: "\n")
    }

    private static func correctLine(_ line: String, table: [String: String], maxWords: Int) -> String {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return line }

        var out = ""
        var i = 0
        while i < tokens.count {
            var length = min(maxWords, tokens.count - i)
            var matched = false
            while length > 0 {
                let key = tokens[i ..< i + length].map(core).joined(separator: " ")
                if let written = table[key] {
                    appendReplacement(written, after: tokens[i], ending: tokens[i + length - 1], into: &out)
                    i += length
                    matched = true
                    break
                }
                length -= 1
            }
            if !matched {
                out += out.isEmpty ? tokens[i] : " " + tokens[i]
                i += 1
            }
        }
        return out
    }

    /// Emit a replacement, keeping punctuation the recognizer glued to the
    /// first/last token of the matched span ("постгрес," → "PostgreSQL,").
    private static func appendReplacement(_ written: String, after first: String,
                                          ending last: String, into out: inout String) {
        let lead = String(first.prefix { edgePunctChars.contains($0) })
        let trail = String(last.reversed().prefix { edgePunctChars.contains($0) }.reversed())
        var piece = lead + written + trail
        if !out.isEmpty { piece = " " + piece }
        out += piece
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?…—-«»\"'()")
    /// Same characters, as a Character set for prefix/suffix filtering.
    private static let edgePunctChars = Set<Character>(".,;:!?…—-«»\"'()")

    /// Comparable form of a token: lowercased, ё folded to е, glued punctuation
    /// stripped (same normalization as `VoiceCommands.core`).
    private static func core(_ token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: edgePunctuation)
    }

    private static func normalized(_ phrase: String) -> String {
        phrase.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Frequency tracking

/// Counts how often dictionary terms appear in dictation output. The top of the
/// list is fed into `contextualStrings` (TZ §12: frequently used terms get a
/// priority boost when recognition is ambiguous). Local only.
enum FrequencyTracker {
    private static let key = "babelbar.termFrequency"

    /// Bump the counter for each term that occurs in `text` (case-insensitive,
    /// word-boundary-ish containment is enough for counting purposes).
    /// `personalTerms` are the written forms of the user's own rules (the store
    /// is MainActor, so callers hand the list over instead of us reading it).
    static func recordHits(in text: String, personalTerms: [String] = []) {
        let lower = " " + text.lowercased() + " "
        var counts = load()
        for term in allTrackableTerms(personalTerms: personalTerms) where !term.isEmpty {
            let needle = " " + term.lowercased() + " "
            if lower.contains(needle) { counts[term, default: 0] += 1 }
        }
        save(counts)
    }

    /// Most frequently used terms first.
    static func topTerms(limit: Int = 40) -> [String] {
        load()
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    static func count(for term: String) -> Int { load()[term] ?? 0 }

    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    /// Everything worth counting: canonical developer terms, the written forms
    /// of the built-in aliases, and the caller-supplied personal terms.
    private static func allTrackableTerms(personalTerms: [String]) -> [String] {
        var terms = DeveloperDictionary.terms
        terms += DeveloperDictionary.aliases.map(\.written)
        terms += personalTerms
        return Array(Set(terms))
    }

    private static func load() -> [String: Int] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
    }

    private static func save(_ counts: [String: Int]) {
        if let data = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Personal dictionary + learned candidates

/// A repeated manual correction observed by `CorrectionObserver`. Becomes a
/// real personal rule only after the user confirms it in Settings (TZ §11:
/// single edits must not turn into rules; confidence grows with repetitions).
struct LearnedCandidate: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var spoken: String
    var written: String
    var count: Int = 1

    init(spoken: String, written: String, count: Int = 1) {
        self.spoken = spoken
        self.written = written
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        spoken = (try? c.decode(String.self, forKey: .spoken)) ?? ""
        written = (try? c.decode(String.self, forKey: .written)) ?? ""
        count = (try? c.decode(Int.self, forKey: .count)) ?? 1
    }
}

/// The user's own spoken → written rules, stored locally in UserDefaults.
/// Higher priority than the developer dictionary: `activeRules()` puts
/// personal entries first so an identical spoken phrase resolves to the
/// user's variant. Main-actor: mutated from Settings and the dictation
/// controller, both main-thread.
@MainActor
final class PersonalDictionaryStore: ObservableObject {
    static let shared = PersonalDictionaryStore()

    @Published private(set) var entries: [DictEntry] = []
    @Published private(set) var candidates: [LearnedCandidate] = []

    private static let entriesKey = "babelbar.personalDictionary"
    private static let candidatesKey = "babelbar.dictCandidates"
    /// How many times the same correction must repeat before it is even shown
    /// as a suggestion (TZ §11 confidence threshold).
    private let suggestionThreshold = 2

    init() { load() }

    // MARK: Entries CRUD

    func add(spoken: String, written: String) {
        let s = spoken.trimmingCharacters(in: .whitespaces)
        let w = written.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !w.isEmpty else { return }
        entries.append(DictEntry(spoken: s, written: w))
        save()
    }

    func update(_ id: UUID, spoken: String, written: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let s = spoken.trimmingCharacters(in: .whitespaces)
        let w = written.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !w.isEmpty else { return }
        entries[i].spoken = s
        entries[i].written = w
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].enabled = on
        save()
    }

    // MARK: Learned candidates

    /// Register an observed correction. Identical (spoken → written) pairs bump
    /// the counter; only pairs seen `suggestionThreshold` times become visible.
    func proposeCandidate(spoken: String, written: String) {
        let s = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !w.isEmpty, s != w else { return }
        // Ignore corrections we would have made ourselves with the right rule.
        if entries.contains(where: { $0.enabled && $0.spoken.lowercased() == s.lowercased() }) { return }
        if let i = candidates.firstIndex(where: {
            $0.spoken.caseInsensitiveCompare(s) == .orderedSame && $0.written.caseInsensitiveCompare(w) == .orderedSame
        }) {
            candidates[i].count += 1
        } else {
            candidates.append(LearnedCandidate(spoken: s, written: w))
        }
        save()
    }

    /// Candidates that passed the confidence threshold — the ones Settings shows.
    var confidentCandidates: [LearnedCandidate] {
        candidates.filter { $0.count >= suggestionThreshold }
    }

    /// Promote a candidate to a real personal rule.
    func confirmCandidate(_ id: UUID) {
        guard let c = candidates.first(where: { $0.id == id }) else { return }
        add(spoken: c.spoken, written: c.written)
        candidates.removeAll { $0.id == id }
        save()
    }

    func dismissCandidate(_ id: UUID) {
        candidates.removeAll { $0.id == id }
        save()
    }

    // MARK: Rule resolution

    /// All rules that apply to a live session, in priority order: personal
    /// (user's own words) before the developer dictionary (TZ §10, §13).
    func activeRules(developerEnabled: Bool) -> [DictEntry] {
        var rules = entries
        if developerEnabled { rules += DeveloperDictionary.entries }
        return rules
    }

    private func load() {
        let d = UserDefaults.standard
        entries = (d.data(forKey: Self.entriesKey)).flatMap { try? JSONDecoder().decode([DictEntry].self, from: $0) } ?? []
        candidates = (d.data(forKey: Self.candidatesKey)).flatMap { try? JSONDecoder().decode([LearnedCandidate].self, from: $0) } ?? []
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(entries) { d.set(data, forKey: Self.entriesKey) }
        if let data = try? JSONEncoder().encode(candidates) { d.set(data, forKey: Self.candidatesKey) }
    }
}

// MARK: - Recognition bias strings

/// Assembles `contextualStrings` for a speech recognition request: the strings
/// the recognizer should *prefer* to output. Only written forms are biased —
/// biasing the Cyrillic spoken forms would push the recognizer toward printing
/// transliterations, the opposite of what we want.
enum DictionaryContext {
    static func contextualStrings(personal: [DictEntry], limit: Int = 150) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func push(_ s: String) {
            let key = s.lowercased()
            guard !s.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            out.append(s)
        }
        // Personal rules carry the user's vocabulary — highest priority.
        for e in personal where e.enabled { push(e.written); push(e.spoken) }
        // Then frequency-ranked terms (what this user actually dictates).
        for term in FrequencyTracker.topTerms(limit: 60) { push(term) }
        // Then the built-in dictionary.
        for term in DeveloperDictionary.terms { push(term) }
        return Array(out.prefix(limit))
    }
}

// MARK: - Correction observer (learns from manual edits, opt-in)

/// Detects manual corrections of BabelBar-typed text through the Accessibility
/// API (TZ §11). At the end of a live session the focused field's value is
/// snapshotted **in memory only** — full field text is never persisted. When
/// the next live session starts in the same app, the value is re-read; if our
/// typed fragment was edited, the edit is extracted as a candidate rule and
/// handed to `PersonalDictionaryStore`.
///
/// Apps that don't expose their text fields through AX (some Electron/custom
/// editors) simply yield nothing — learning silently stays off there. Reading
/// happens only for the field the user dictated into, only while this feature
/// is enabled in Settings.
enum CorrectionObserver {
    /// In-memory snapshot from the previous live session. Never persisted.
    private static var snapshot: (bundleID: String, value: String, typed: String)?

    /// Called when a live session ends. `typed` = the final text BabelBar
    /// printed into the field this session.
    static func noteSessionEnded(typed: String) {
        guard !typed.isEmpty, let value = focusedFieldValue() else {
            snapshot = nil
            return
        }
        snapshot = (frontmostBundleID(), value, typed)
    }

    /// Called when the next live session begins. If the field we dictated into
    /// last time no longer contains our text verbatim, someone edited it.
    static func checkPreviousSessionCorrection() {
        guard let snap = snapshot else { return }
        snapshot = nil
        guard snap.bundleID == frontmostBundleID(), let now = focusedFieldValue() else { return }
        if now.contains(snap.typed) { return }   // untouched — nothing to learn
        if let fix = extractCorrection(oldValue: snap.value, typed: snap.typed, newValue: now) {
            Task { @MainActor in
                PersonalDictionaryStore.shared.proposeCandidate(spoken: fix.spoken, written: fix.written)
            }
        }
    }

    static func forget() { snapshot = nil }

    /// Word anchors around the typed fragment locate its replacement in the
    /// edited value. Returns nil when the change can't be attributed to our
    /// text (e.g. the user rewrote the whole field, or anchors aren't found).
    static func extractCorrection(oldValue: String, typed: String,
                                  newValue: String) -> (spoken: String, written: String)? {
        guard let range = oldValue.range(of: typed) else { return nil }
        let before = oldValue[..<range.lowerBound]
        let after = oldValue[range.upperBound...]

        func wordsTail(_ s: Substring) -> [String] {
            Array(s.split(whereSeparator: \.isWhitespace).suffix(2).map(String.init))
        }
        func wordsHead(_ s: Substring) -> [String] {
            Array(s.split(whereSeparator: \.isWhitespace).prefix(2).map(String.init))
        }
        let leftAnchor = wordsTail(before)
        let rightAnchor = wordsHead(after)
        let typedWords = typed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !typedWords.isEmpty else { return nil }

        // Locate the anchored window in the new value.
        var searchRange = newValue.startIndex..<newValue.endIndex
        var windowStart: String.Index?
        for word in leftAnchor {
            guard let r = newValue.range(of: word, range: searchRange) else { return nil }
            windowStart = r.upperBound
            searchRange = r.upperBound..<newValue.endIndex
        }
        var windowEnd: String.Index?
        let anchorStart = windowStart ?? newValue.startIndex
        if !rightAnchor.isEmpty {
            var r = anchorStart..<newValue.endIndex
            for word in rightAnchor {
                guard let found = newValue.range(of: word, range: r) else { return nil }
                windowEnd = found.lowerBound
                r = found.upperBound..<newValue.endIndex
                break   // first right-anchor word is enough
            }
        }
        let lower = windowStart ?? newValue.startIndex
        let upper = windowEnd ?? newValue.endIndex
        guard lower <= upper else { return nil }
        let replacement = String(newValue[lower ..< upper])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Sanity gates: non-empty, letters present, plausibly a rewrite of `typed`
        // (not the whole paragraph), not identical.
        guard !replacement.isEmpty, replacement != typed,
              replacement.contains(where: \.isLetter),
              replacement.count <= max(8, typed.count * 3) else { return nil }
        let spoken = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard spoken.count <= 80 else { return nil }   // don't learn from giant fragments

        // The user usually fixes one word of the dictated span, not the span —
        // refine to the differing middle ("сделай компонент" → "создай компонент"
        // is really the rule сделай → создай).
        let spokenWords = spoken.components(separatedBy: " ").filter { !$0.isEmpty }
        let writtenWords = replacement.components(separatedBy: " ").filter { !$0.isEmpty }
        var head = 0
        while head < spokenWords.count, head < writtenWords.count,
              spokenWords[head] == writtenWords[head] { head += 1 }
        var tail = 0
        while tail < spokenWords.count - head, tail < writtenWords.count - head,
              spokenWords[spokenWords.count - 1 - tail] == writtenWords[writtenWords.count - 1 - tail] {
            tail += 1
        }
        let spokenMid = spokenWords[head ..< spokenWords.count - tail].joined(separator: " ")
        let writtenMid = writtenWords[head ..< writtenWords.count - tail].joined(separator: " ")
        guard !spokenMid.isEmpty, !writtenMid.isEmpty, spokenMid != writtenMid,
              writtenMid.contains(where: \.isLetter) else { return nil }
        return (spokenMid, writtenMid)
    }

    // MARK: - AX plumbing

    private static func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    /// Value of the system-wide focused UI element when it is a text field that
    /// exposes its contents. Capped so a huge document can't stall the read.
    private static func focusedFieldValue() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let rawFocused = focused else { return nil }
        let element = unsafeBitCast(rawFocused, to: AXUIElement.self)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        guard text.count <= 100_000 else { return nil }
        return text
    }
}
