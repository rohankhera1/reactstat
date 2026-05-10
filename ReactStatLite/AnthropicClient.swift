import Foundation

enum AnthropicClient {

    // MARK: - Proxy config (fill these in after deploying the Cloudflare Worker)
    private static let proxyEndpoint = URL(string: "https://reactstat-proxy.reactstat.workers.dev/messages")!
    private static let appSecret     = "10a1385325bd4c0cbbff883abd00533d1e90b209c6f04081e2899c72a72554d6"

    private static let haiku  = "claude-haiku-4-5-20251001"   // fast/cheap — per-chat profiles
    private static let sonnet = "claude-sonnet-4-6"            // smarter — life analysis

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // Returns 2–3 sentence free-form personality descriptor.
    static func generatePersonalityDescriptor(
        sampleMessages: [String]
    ) async throws -> String {

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

        return try await post(prompt: prompt, model: haiku, maxTokens: 220, endpoint: "personality")
    }

    // Returns structured (personality, timeline, foresight) from timestamped message history.
    static func generateLifeAnalysis(
        timePeriods: [TimePeriod],
        topContacts: [ContactSummary],
        groupChats: [(chatName: String, members: [String])],
        totalMessages: Int,
        dateRange: String
    ) async throws -> (archetype: String, personality: String, timeline: String, foresight: String, patterns: String) {

        let periodsText = timePeriods.map { period in
            let snippets = period.samples.map { snippet -> String in
                snippet.split(separator: "\n", omittingEmptySubsequences: true)
                    .map { "    \($0)" }
                    .joined(separator: "\n")
            }.joined(separator: "\n  ---\n")
            return "\(period.label):\n\(snippets)"
        }.joined(separator: "\n\n")

        let contactsSection: String
        if topContacts.isEmpty {
            contactsSection = ""
        } else {
            let list = topContacts.prefix(40).map { c -> String in
                let dmStr    = c.dmMessageCount > 0 ? "\(c.dmMessageCount) DMs" : "0 DMs"
                let grpStr   = "\(c.messageCount - c.dmMessageCount) group"
                let chatStr  = c.sharedGroupChats > 0 ? "\(c.sharedGroupChats) shared group chat\(c.sharedGroupChats == 1 ? "" : "s")" : "no shared group chats"
                return "  \(c.name) — \(dmStr) + \(grpStr) msgs · \(c.firstSeen)→\(c.lastSeen) · \(chatStr)"
            }.joined(separator: "\n")
            contactsSection = """
            PEOPLE THEY'VE TEXTED (real contacts from their address book):
            \(list)

            HOW TO INTERPRET THIS DATA:
            - DMs (1:1 direct messages) are by far the strongest signal of genuine closeness. Someone with 500 group msgs but 3 DMs is a casual contact, not a close friend.
            - High group message count with low DMs often means a sports chat, meme group, or work channel — not a meaningful personal relationship.
            - firstSeen→lastSeen is when they exchanged messages. An end date signals a breakup, falling out, or someone moving away.
            - People whose firstSeen dates cluster together entered the person's life at the same time (same school year, same move, same job).
            - Shared group chats reveal social circles — people in 2–3 of the same chats are in the same friend group.
            - 0 shared group chats + high DMs = likely a romantic relationship or a close friend in a different city.
            - Every person with 15+ DMs MUST be mentioned in your timeline.

            """
        }

        let groupChatsSection: String
        if groupChats.isEmpty {
            groupChatsSection = ""
        } else {
            let list = groupChats.map { chat in
                "  \"\(chat.chatName)\": \(chat.members.joined(separator: ", "))"
            }.joined(separator: "\n")
            groupChatsSection = """
            THEIR GROUP CHATS (shows who belongs to which social circle):
            \(list)

            Use this to understand friend groups. People who share a group chat are part of \
            the same social circle. This helps you distinguish close friends from casual contacts.

            """
        }

        let prompt = """
        \(contactsSection)\(groupChatsSection)The following are real iMessages sent by one person, organized by time period \
        (\(totalMessages) messages total, \(dateRange)):

        \(periodsText)

        You are doing a deep, data-driven life analysis of whoever sent these messages. \
        Study them carefully — names, places, recurring topics, tone shifts, emotional intensity, \
        inside references, and how patterns change across time periods. \
        Then write four sections:

        [ARCHETYPE]
        2–4 words starting with "The". A vivid, specific archetype that captures this person — \
        something like "The Magnetic Realist" or "The Loyal Agitator" or "The Quiet Catalyst". \
        Not a generic type label. Make it feel written for this person specifically.

        [PERSONALITY]
        3–4 sentences. Who is this person, really — their humor, energy, values, communication style, \
        and how they relate to the people around them. Be vivid and specific, not generic. \
        Describe them as someone who has read every message they've ever sent.

        [TIMELINE]
        A narrative timeline of their life as revealed by their messages. This is the most important \
        section — be thorough and specific. Cover every person from the frequency list above. Also cover:
        - For each close friend: when they first appear, how central they are, whether that changes
        - Romantic relationships: try to identify the person's name and gender. Note when they start \
          (a new name appearing with warmth and frequency) and when they likely end (name disappears, \
          tone darkens, or emotional language spikes without that name)
        - Major life transitions: school, graduation, moves, jobs — look for topic and vocabulary shifts
        - Periods of stress, excitement, or emotional change and what the data suggests caused them
        - How the social circle evolves across the full time range
        Write at least 6 substantial paragraphs. Be precise about time periods. Use actual names from \
        the messages — do not anonymize people you can clearly identify.

        [FORESIGHT]
        3–4 sentences. Based on the clear patterns and trajectory in their communication — \
        who keeps showing up, what they keep returning to, how their tone has shifted most recently — \
        what does the data predict about where their story is heading? Be specific and personal, \
        not a generic horoscope.

        [PATTERNS]
        Identify recurring behavioral patterns visible in the messaging data. Split into two parts:

        Destructive patterns:
        2–3 specific patterns that show up repeatedly and tend to work against them — \
        things like going quiet when overwhelmed, escalating conflict over text, \
        dropping people suddenly, or leaning too hard on one person. \
        Each pattern should be grounded in actual evidence from the messages, not inferred from personality.

        Positive patterns:
        2–3 specific patterns that show up repeatedly and tend to serve them well — \
        things like checking in on people unprompted, de-escalating tension, \
        being the one who keeps relationships alive, or showing up consistently. \
        Same standard: evidence-based, specific to this person.

        Be honest and direct. These should feel like genuine insights from someone who has \
        read every message, not generic self-help observations.

        Use exactly those five section headers ([ARCHETYPE], [PERSONALITY], [TIMELINE], [FORESIGHT], [PATTERNS]). Do not add any other text before [ARCHETYPE].

        IMPORTANT: Write in PG-13 language suitable for sharing. Never directly quote slurs or \
        offensive language — paraphrase the sentiment instead. If the same first name appears \
        more than once in the contact list, those are DIFFERENT people; use their message counts \
        and date ranges to distinguish which one is which.
        """

        let text = try await post(prompt: prompt, model: sonnet, maxTokens: 9000, timeout: 300, endpoint: "life-analysis")

        return (
            archetype:   extractSection("ARCHETYPE",   nextMarker: "PERSONALITY", from: text),
            personality: extractSection("PERSONALITY", nextMarker: "TIMELINE",    from: text),
            timeline:    extractSection("TIMELINE",    nextMarker: "FORESIGHT",   from: text),
            foresight:   extractSection("FORESIGHT",   nextMarker: "PATTERNS",    from: text),
            patterns:    extractSection("PATTERNS",    nextMarker: nil,           from: text)
        )
    }

    // Returns (dynamic, investment) for a 1:1 relationship.
    static func generateRelationshipAnalysis(
        contactName: String,
        sampleMessages: [(text: String, isFromMe: Bool)],
        userSent: Int,
        contactSent: Int,
        userAvgWords: Double,
        contactAvgWords: Double,
        userInitiationPct: Double,
        dateRange: String
    ) async throws -> (dynamic: String, investment: String) {

        let msgSample = sampleMessages
            .map { "\($0.isFromMe ? "You" : contactName): \($0.text)" }
            .joined(separator: "\n")

        let prompt = """
        Analyze this 1:1 iMessage relationship using real data.

        Stats:
        - You sent \(userSent) messages (avg \(String(format: "%.1f", userAvgWords)) words each)
        - \(contactName) sent \(contactSent) messages (avg \(String(format: "%.1f", contactAvgWords)) words each)
        - You initiate \(Int(userInitiationPct * 100))% of conversations
        - Active: \(dateRange)

        Sample messages:
        \(msgSample)

        [DYNAMIC]
        2–3 sentences: What is the energy and structure of this relationship? \
        Who leads, who follows, what do they bond over, how do they communicate?

        [INVESTMENT]
        1 sentence: Who invests more — in frequency, length, initiation — \
        and what does that asymmetry (or balance) suggest about where each person stands?

        Be specific and grounded in the data above. No generic observations. \
        Write in PG-13 language.
        """

        let text = try await post(prompt: prompt, model: haiku, maxTokens: 320, endpoint: "personality")

        return (
            dynamic:    extractSection("DYNAMIC",    nextMarker: "INVESTMENT", from: text),
            investment: extractSection("INVESTMENT", nextMarker: nil,          from: text)
        )
    }

    // MARK: - Shared HTTP helper

    private static func post(prompt: String, model: String, maxTokens: Int, timeout: TimeInterval = 60, endpoint: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]

        var request = URLRequest(url: proxyEndpoint)
        request.httpMethod = "POST"
        request.setValue(appSecret, forHTTPHeaderField: "X-App-Token")
        request.setValue(endpoint, forHTTPHeaderField: "X-Endpoint")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No HTTP response")
        }
        guard http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw APIError(message: "Proxy error \(http.statusCode): \(raw.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw APIError(message: "Unexpected API response format")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Section parser

    private static func extractSection(_ marker: String, nextMarker: String?, from text: String) -> String {
        let header = "[\(marker)]"
        guard let headerRange = text.range(of: header) else { return "" }
        let searchStart = headerRange.upperBound

        if let next = nextMarker {
            let nextHeader = "[\(next)]"
            if let nextRange = text.range(of: nextHeader, range: searchStart..<text.endIndex) {
                return String(text[searchStart..<nextRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return String(text[searchStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
