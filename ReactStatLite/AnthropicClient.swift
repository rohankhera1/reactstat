import Foundation

enum AnthropicClient {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    // Haiku: fast + cheap for short personality descriptors
    private static let model = "claude-haiku-4-5-20251001"

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // Returns 2–3 sentence free-form personality descriptor.
    static func generatePersonalityDescriptor(
        sampleMessages: [String],
        apiKey: String
    ) async throws -> String {

        // Shuffle for variety; only drop the attachment placeholder char.
        // Short messages like "lol", "k", "omg" are kept — they're the signal.
        let sample = sampleMessages
            .filter { $0 != "\u{FFFC}" && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .shuffled()
            .prefix(80)
            .map { "• \($0)" }
            .joined(separator: "\n")

        let prompt = """
        These are real iMessages someone sent in a group chat:

        \(sample)

        In 2–3 sentences, describe the personality and vibe of whoever wrote these. \
        Focus on what's interesting and specific about them — their humor, energy, vocabulary, \
        what they react to, how they come across. \
        Do not describe message length or use generic personality labels. \
        Be direct and vivid, written like someone who has been in the chat with them for months.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 220,
            "messages": [["role": "user", "content": prompt]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No HTTP response")
        }
        guard http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw APIError(message: "Anthropic API error \(http.statusCode): \(raw.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw APIError(message: "Unexpected API response format")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
