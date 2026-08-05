import Foundation

/// Spoken punctuation → real punctuation ("запятая" → ",", "с новой строки" → a line break).
///
/// Whisper has no instruction-following: told "insert a comma when I say «запятая»" it simply
/// writes the word — the `prompt` parameter of the Whisper API biases vocabulary and style, it
/// is not a command. So dictation commands have to be resolved *after* recognition. This layer
/// does that, and it runs before translation, so «запятая» never reaches the LLM as a word.
///
/// Deliberately conservative: only the nominative, standalone form counts as a command
/// ("запятая", never "запятую"), so a sentence that merely *mentions* punctuation
/// ("поставь здесь запятую") is left alone.
enum VoiceCommands {

    /// What a recognized command inserts.
    private enum Mark {
        case punct(String)    // glued to the previous word, space after it
        case spaced(String)   // spaces on both sides (dash)
        case glued(String)    // no spaces at all (hyphen)
        case newline(Int)     // one line break, or two for a new paragraph
    }

    /// Longest phrase in `table`, in words — the matcher tries this many tokens first.
    private static let maxPhrase = 3

    private static let table: [[String]: Mark] = [
        // Russian
        ["точка", "с", "запятой"]:  .punct(";"),
        ["точка"]:                  .punct("."),
        ["запятая"]:                .punct(","),
        ["двоеточие"]:              .punct(":"),
        ["вопросительный", "знак"]: .punct("?"),
        ["восклицательный", "знак"]: .punct("!"),
        ["многоточие"]:             .punct("…"),
        ["тире"]:                   .spaced("—"),
        ["дефис"]:                  .glued("-"),
        ["с", "новой", "строки"]:   .newline(1),
        ["новая", "строка"]:        .newline(1),
        ["с", "красной", "строки"]: .newline(2),
        ["новый", "абзац"]:         .newline(2),
        // English
        ["period"]:                 .punct("."),
        ["full", "stop"]:           .punct("."),
        ["comma"]:                  .punct(","),
        ["colon"]:                  .punct(":"),
        ["semicolon"]:              .punct(";"),
        ["question", "mark"]:       .punct("?"),
        ["exclamation", "mark"]:    .punct("!"),
        ["exclamation", "point"]:   .punct("!"),
        ["ellipsis"]:               .punct("…"),
        ["dash"]:                   .spaced("—"),
        ["hyphen"]:                 .glued("-"),
        ["new", "line"]:            .newline(1),
        ["newline"]:                .newline(1),
        ["new", "paragraph"]:       .newline(2),
    ]

    /// Characters Whisper glues to a word and that a command must not carry with it.
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?…—-«»\"'()")
    /// Marks that end a sentence — the next word gets capitalized.
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]

    /// Replace spoken punctuation with the marks themselves and tidy the spacing around them.
    /// Existing line breaks are preserved; each line is processed on its own.
    static func apply(to text: String) -> String {
        text.components(separatedBy: "\n")
            .map(processLine)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func processLine(_ line: String) -> String {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return "" }
        let cores = tokens.map(core)

        var out = ""
        var capitalizeNext = true
        var glueNext = false          // previous mark was a hyphen: no space before the next word
        var i = 0

        while i < tokens.count {
            var length = min(maxPhrase, tokens.count - i)
            var matched = false
            // Longest match wins, so "точка с запятой" is never read as "точка" + "с" + "запятой".
            while length > 0 {
                let phrase = Array(cores[i ..< i + length])
                if !phrase.contains(where: \.isEmpty), let mark = table[phrase] {
                    emit(mark, into: &out, capitalizeNext: &capitalizeNext, glueNext: &glueNext)
                    i += length
                    matched = true
                    break
                }
                length -= 1
            }
            if matched { continue }
            append(word: tokens[i], into: &out, capitalizeNext: &capitalizeNext, glueNext: &glueNext)
            i += 1
        }
        return out
    }

    private static func emit(_ mark: Mark, into out: inout String,
                             capitalizeNext: inout Bool, glueNext: inout Bool) {
        trimTrailingSpaces(&out)
        switch mark {
        case .punct(let s):
            // Nothing to attach a comma to yet — a leading mark would just be noise.
            guard !out.isEmpty, !out.hasSuffix("\n") else { return }
            // Whisper usually already put a mark of its own where the command word was
            // ("…попробуем, запятая, а потом") — drop it, ours replaces it.
            stripTrailingMarks(&out)
            out += s
            capitalizeNext = sentenceEnders.contains(Character(s))
            glueNext = false
        case .spaced(let s):
            out += (out.isEmpty || out.hasSuffix("\n")) ? s : " " + s
            capitalizeNext = false
            glueNext = false
        case .glued(let s):
            out += s
            capitalizeNext = false
            glueNext = true
        case .newline(let count):
            guard !out.isEmpty else { return }
            stripTrailingMarks(&out, keeping: sentenceEnders)
            out += String(repeating: "\n", count: count)
            capitalizeNext = true
            glueNext = false
        }
    }

    private static func append(word token: String, into out: inout String,
                               capitalizeNext: inout Bool, glueNext: inout Bool) {
        let word = capitalizeNext ? capitalizingFirstLetter(token) : token
        if out.isEmpty || out.hasSuffix("\n") || glueNext {
            out += word
        } else {
            out += " " + word
        }
        // Honor the punctuation Whisper produced on its own, too.
        capitalizeNext = endsSentence(token)
        glueNext = false
    }

    // MARK: - Helpers

    /// Comparable form of a token: lowercased, stripped of glued punctuation, ё folded to е
    /// (Whisper writes both). Empty when the token is punctuation only.
    private static func core(_ token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: edgePunctuation)
    }

    private static func endsSentence(_ token: String) -> Bool {
        for ch in token.reversed() {
            if sentenceEnders.contains(ch) { return true }
            if ch == "\"" || ch == "»" || ch == "'" || ch == ")" { continue }
            return false
        }
        return false
    }

    private static func capitalizingFirstLetter(_ token: String) -> String {
        guard let i = token.firstIndex(where: { $0.isLetter }) else { return token }
        return token.replacingCharacters(in: i...i, with: token[i...i].uppercased())
    }

    private static func trimTrailingSpaces(_ s: inout String) {
        while let last = s.last, last == " " || last == "\t" { s.removeLast() }
    }

    /// Drop punctuation Whisper attached to the previous word, so we never emit ",," or ",.".
    private static func stripTrailingMarks(_ s: inout String, keeping keep: Set<Character> = []) {
        while let last = s.last, ".,;:!?…".contains(last), !keep.contains(last) { s.removeLast() }
    }
}
