import Foundation
import SQLite3

enum PersonalityStatsRepository {

    // MARK: - DB helper

    private static func openDB() throws -> OpaquePointer? {
        let dbPath = MessagesDBHealth.chatDBURL().path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            defer { if db != nil { sqlite3_close(db) } }
            let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown error"
            throw NSError(domain: "ReactStatLite", code: 901,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        sqlite3_busy_timeout(db, 1500)
        return db
    }

    // MARK: - Per-chat profiles

    static func personalityProfiles(
        chatRowId: Int64,
        apiKey: String,
        messageLimit: Int = 3000
    ) async throws -> [PersonalityProfile] {

        if chatRowId == -1 { return demoChatProfiles() }

        // --- 1. Fetch messages from DB (sync, fast) ---
        let messagesBySender = try fetchMessagesBySender(chatRowId: chatRowId, limit: messageLimit)

        // --- 2. Compute traits locally (parallel, no network) ---
        struct PersonEntry {
            let name: String
            let count: Int
            let traits: PersonalityTraits
            let messages: [String]
        }
        var entries: [PersonEntry] = []
        for (handle, messages) in messagesBySender {
            let displayName = handle == "me" ? "You" : ContactNameCache.shared.resolve(handle)
            let clean = PersonalityAnalyzer.cleaned(messages)
            guard let t = PersonalityAnalyzer.traits(for: clean) else { continue }
            entries.append(PersonEntry(name: displayName, count: clean.count, traits: t, messages: clean))
        }

        // --- 3. Call Claude sequentially to avoid concurrent-connection rate limits ---
        var profiles: [PersonalityProfile] = []
        for entry in entries {
            let descriptor: String
            if apiKey.isEmpty {
                descriptor = PersonalityAnalyzer.fallbackDescriptor(
                    traits: entry.traits, messageCount: entry.count
                )
            } else {
                descriptor = try await AnthropicClient.generatePersonalityDescriptor(
                    sampleMessages: entry.messages,
                    apiKey: apiKey
                )
            }
            profiles.append(PersonalityProfile(
                name: entry.name,
                messageCount: entry.count,
                warmth: entry.traits.warmth,
                expressiveness: entry.traits.expressiveness,
                verbosity: entry.traits.verbosity,
                curiosity: entry.traits.curiosity,
                enthusiasm: entry.traits.enthusiasm,
                lexicalRichness: entry.traits.lexical,
                descriptor: descriptor
            ))
        }

        return profiles.sorted {
            if $0.name == "You" { return true }
            if $1.name == "You" { return false }
            return $0.messageCount > $1.messageCount
        }
    }

    // MARK: - Cross-chat "Your" profile

    static func yourCrossGroupProfile(
        apiKey: String,
        messageLimit: Int = 5000
    ) async throws -> PersonalityProfile? {

        let messages = try fetchMyMessages(limit: messageLimit)
        let clean = PersonalityAnalyzer.cleaned(messages)
        guard let t = PersonalityAnalyzer.traits(for: clean) else { return nil }

        let descriptor: String
        if apiKey.isEmpty {
            descriptor = PersonalityAnalyzer.fallbackDescriptor(traits: t, messageCount: clean.count)
        } else {
            descriptor = try await AnthropicClient.generatePersonalityDescriptor(
                sampleMessages: clean,
                apiKey: apiKey
            )
        }

        return PersonalityProfile(
            name: "You",
            messageCount: clean.count,
            warmth: t.warmth,
            expressiveness: t.expressiveness,
            verbosity: t.verbosity,
            curiosity: t.curiosity,
            enthusiasm: t.enthusiasm,
            lexicalRichness: t.lexical,
            descriptor: descriptor
        )
    }

    // MARK: - SQL helpers

    private static func fetchMessagesBySender(chatRowId: Int64, limit: Int) throws -> [String: [String]] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
            CASE WHEN m.is_from_me = 1 THEN 'me' ELSE COALESCE(h.id, 'unknown') END AS sender,
            m.text
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE cmj.chat_id = ?
          AND m.text IS NOT NULL
          AND m.text != ''
          AND m.associated_message_guid IS NULL
        ORDER BY m.date DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 902,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var out: [String: [String]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sC = sqlite3_column_text(stmt, 0),
                  let tC = sqlite3_column_text(stmt, 1) else { continue }
            let text = String(cString: tC)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            out[String(cString: sC), default: []].append(text)
        }
        return out
    }

    private static func fetchMyMessages(limit: Int) throws -> [String] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT m.text
        FROM message m
        WHERE m.is_from_me = 1
          AND m.text IS NOT NULL
          AND m.text != ''
          AND m.associated_message_guid IS NULL
        ORDER BY m.date DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 903,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            let text = String(cString: c)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            out.append(text)
        }
        return out
    }

    // MARK: - Demo

    private static func demoChatProfiles() -> [PersonalityProfile] {
        let fixtures: [(String, Double, Double, Double, Double, Double, Double, String)] = [
            ("Donald Trump", 0.52, 0.72, 0.42, 0.12, 0.65, 0.44,
             "Communicates in bold, declarative bursts — everything is the best, the biggest, the most incredible. Rarely asks questions because he already has the answers. The group chat equivalent of a press conference that somehow becomes about him."),
            ("Kim Jong Un", 0.32, 0.08, 0.15, 0.06, 0.04, 0.58,
             "Says almost nothing, but when he does, the whole chat stops scrolling. His silence carries more weight than most people's paragraphs. You're never sure if he's reading everything or nothing."),
            ("Emmanuel Macron", 0.63, 0.18, 0.72, 0.38, 0.18, 0.82,
             "Writes long, carefully structured messages that feel like policy memos with better lighting. Asks probing questions that make everyone else feel slightly underprepared. The one who follows up with a three-paragraph correction if something was phrased imprecisely."),
            ("Vladimir Putin", 0.38, 0.09, 0.19, 0.09, 0.06, 0.60,
             "Economical to the point of being cryptic — short messages that could mean anything. Doesn't react to things, but you get the sense he's tracking every thread. The group chat reads differently knowing he's in it."),
            ("Justin Trudeau", 0.78, 0.38, 0.44, 0.22, 0.38, 0.67,
             "Consistently the warmest presence in the chat — responds to everything, validates everyone, and somehow makes a logistics discussion feel meaningful. Uses exclamation marks sincerely, which is rarer than it sounds."),
            ("Joe Biden", 0.68, 0.26, 0.81, 0.28, 0.27, 0.74,
             "Writes the longest messages by a wide margin, usually because he starts with a story from 1987 before getting to the point. Genuinely means well and the warmth comes through, even when the message could have been half as long."),
        ]
        return fixtures.map { name, w, ex, v, cu, en, lex, desc in
            PersonalityProfile(name: name, messageCount: Int.random(in: 50...500),
                               warmth: w, expressiveness: ex, verbosity: v,
                               curiosity: cu, enthusiasm: en, lexicalRichness: lex,
                               descriptor: desc)
        }
    }
}
