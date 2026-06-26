import Foundation

enum TranslationError: LocalizedError {
    case missingKey
    case badResponse(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .missingKey: return "API key is missing. Add it in Settings."
        case .badResponse(let m): return "API error: \(m)"
        case .noContent: return "No translation returned."
        }
    }
}

struct TranslationResult {
    let text: String
    let totalTokens: Int
    let usedSlot: Int          // which provider slot produced this result
}

/// One API account (provider + endpoint + key).
struct ProviderConfig {
    let slot: Int
    let provider: APIProvider
    let baseURL: String
    let model: String
    let apiKey: String

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Calls an OpenAI-compatible /chat/completions endpoint.
/// Works with OpenAI, DeepSeek, and any compatible provider.
struct TranslationService {

    /// Tries the given accounts in order (starting at `startIndex`, wrapping once). The first
    /// one that succeeds wins; on failure (e.g. exhausted balance / auth) it falls back to the
    /// next configured account. Returns the result and which slot served it.
    func translate(text: String, from: Lang, to: Lang, instructions: String,
                   accounts: [ProviderConfig], startIndex: Int) async throws -> TranslationResult {
        let usable = accounts.filter { $0.hasKey }
        guard !usable.isEmpty else { throw TranslationError.missingKey }

        // Order: start with the active slot, then the rest.
        let ordered = usable.sorted { a, b in
            (a.slot == startIndex ? 0 : 1) < (b.slot == startIndex ? 0 : 1)
        }

        var lastError: Error = TranslationError.missingKey
        for account in ordered {
            do {
                let r = try await request(text: text, from: from, to: to,
                                          instructions: instructions, account: account)
                return r
            } catch {
                lastError = error   // try the next account
            }
        }
        throw lastError
    }

    private func request(text: String, from: Lang, to: Lang, instructions: String,
                         account: ProviderConfig) async throws -> TranslationResult {
        let apiKey = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = account.baseURL.isEmpty ? account.provider.defaultBaseURL : account.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: .init(charactersIn: "/")) + "/chat/completions") else {
            throw TranslationError.badResponse("Invalid base URL")
        }

        let system = """
        You are a professional translation engine. Translate the user's text from \(languageName(from)) to \(languageName(to)).
        Return ONLY the translated text, with no quotes, no explanations, no notes.
        Additional style instructions: \(instructions)
        """

        let body: [String: Any] = [
            "model": account.model.isEmpty ? account.provider.defaultModel : account.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ],
            "temperature": 0.2
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.badResponse("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw TranslationError.badResponse(msg)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TranslationError.noContent
        }
        let usage = json["usage"] as? [String: Any]
        let totalTokens = (usage?["total_tokens"] as? Int)
            ?? (usage?["total_tokens"] as? Double).map(Int.init)
            ?? 0
        return TranslationResult(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            totalTokens: totalTokens,
            usedSlot: account.slot
        )
    }

    private func languageName(_ l: Lang) -> String { l.englishName }
}
