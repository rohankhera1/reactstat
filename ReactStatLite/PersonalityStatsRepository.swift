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
            let descriptor = try await AnthropicClient.generatePersonalityDescriptor(
                sampleMessages: entry.messages
            )
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
        messageLimit: Int = 5000
    ) async throws -> PersonalityProfile? {

        let messages = try fetchMyMessages(limit: messageLimit)
        let clean = PersonalityAnalyzer.cleaned(messages)
        guard let t = PersonalityAnalyzer.traits(for: clean) else { return nil }

        let descriptor = try await AnthropicClient.generatePersonalityDescriptor(
            sampleMessages: clean
        )

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

    // MARK: - Cross-chat full life analysis

    static func yourFullLifeAnalysis() async throws -> LifeAnalysis? {

        // User's own messages — used for trait computation and date range only.
        let userPairs = try fetchMyMessagesWithDates()
        let cleanedUser: [(text: String, date: Date)] = userPairs.compactMap { text, date in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty && t != "\u{FFFC}" else { return nil }
            return (t, date)
        }
        guard let traits = PersonalityAnalyzer.traits(for: cleanedUser.map { $0.text }) else { return nil }
        let sortedUser = cleanedUser.sorted { $0.date < $1.date }
        let dateRange = formatDateRange(from: sortedUser.first!.date, to: sortedUser.last!.date)

        // All messages with conversation context — used for the timeline.
        let contextPairs = try fetchAllMessagesForContext()

        // Real contacts from the DB (high precision).
        ContactNameCache.shared.warmIfNeeded()
        let groupChats   = fetchGroupChatSummaries()
        let topContacts  = fetchContactsWithTimeline(groupChats: groupChats)
        let contactNames = topContacts.map { $0.name }
        let timePeriods  = groupByTimePeriod(contextPairs.sorted { $0.date < $1.date },
                                             prioritizingNames: contactNames)

        let result = try await AnthropicClient.generateLifeAnalysis(
            timePeriods: timePeriods,
            topContacts: topContacts,
            groupChats: groupChats,
            totalMessages: cleanedUser.count,
            dateRange: dateRange
        )

        return LifeAnalysis(
            archetype: result.archetype,
            personality: result.personality,
            timeline: result.timeline,
            foresight: result.foresight,
            messageCount: cleanedUser.count, dateRange: dateRange,
            warmth: traits.warmth, expressiveness: traits.expressiveness,
            verbosity: traits.verbosity, curiosity: traits.curiosity,
            enthusiasm: traits.enthusiasm, lexicalRichness: traits.lexical
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

    private static func fetchMyMessagesWithDates() throws -> [(text: String, date: Date)] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        // No LIMIT — we need the full history to build an accurate timeline.
        let sql = """
        SELECT m.text, m.date
        FROM message m
        WHERE m.is_from_me = 1
          AND m.text IS NOT NULL
          AND m.text != ''
          AND m.associated_message_guid IS NULL
        ORDER BY m.date ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 904,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        var out: [(text: String, date: Date)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            let text = String(cString: c)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let rawDate = sqlite3_column_int64(stmt, 1)
            // chat.db uses nanoseconds since 2001-01-01 on modern OS (value > 1B indicates ns).
            let secondsSince2001 = rawDate > 1_000_000_000 ? Double(rawDate) / 1_000_000_000 : Double(rawDate)
            let date = Date(timeIntervalSinceReferenceDate: secondsSince2001)
            out.append((text: text, date: date))
        }
        return out
    }

    private static let periodFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private static func formatDateRange(from start: Date, to end: Date) -> String {
        "\(periodFormatter.string(from: start)) – \(periodFormatter.string(from: end))"
    }

    private static func groupByTimePeriod(
        _ pairs: [(text: String, date: Date)],
        prioritizingNames names: [String] = []
    ) -> [TimePeriod] {
        guard pairs.count >= 2 else { return [] }

        let cal = Calendar.current
        let spanMonths = cal.dateComponents(
            [.month], from: pairs.first!.date, to: pairs.last!.date
        ).month ?? 0

        // Use quarterly buckets for histories longer than 2 years so we cover the full span.
        let useQuarterly = spanMonths > 24

        var buckets: [Date: [String]] = [:]
        for pair in pairs {
            var comps = DateComponents()
            comps.year = cal.component(.year, from: pair.date)
            let month = cal.component(.month, from: pair.date)
            comps.month = useQuarterly ? ((month - 1) / 3) * 3 + 1 : month
            comps.day = 1
            if let bucket = cal.date(from: comps) {
                buckets[bucket, default: []].append(pair.text)
            }
        }

        var sorted = buckets.keys.sorted().map { (key: $0, messages: buckets[$0]!) }

        // Cap at 48 buckets (~12 years quarterly / ~4 years monthly) keeping most recent.
        if sorted.count > 48 { sorted = Array(sorted.suffix(48)) }

        let priorityNames = names  // capture for closure

        return sorted.map { bucket in
            let label: String
            if useQuarterly {
                let year    = cal.component(.year,  from: bucket.key)
                let month   = cal.component(.month, from: bucket.key)
                let quarter = (month - 1) / 3 + 1
                label = "Q\(quarter) \(year)"
            } else {
                label = periodFormatter.string(from: bucket.key)
            }

            let clean = bucket.messages.filter {
                $0 != "\u{FFFC}" && !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }

            // Score every snippet by information density, then take the top 15.
            // Name bonus ensures important people surface even in busy periods.
            let sample = clean
                .map { snippet -> (text: String, score: Double) in
                    (snippet, snippetScore(snippet, priorityNames: priorityNames))
                }
                .sorted { $0.score > $1.score }
                .prefix(15)
                .map { String($0.text.prefix(650)) }

            return TimePeriod(label: label, samples: Array(sample))
        }
    }

    // Fetches ALL messages (both sides of every conversation) and returns ±1 conversation
    // snippets anchored on each of the user's messages — so Claude sees context, not bare lines.
    private static func fetchAllMessagesForContext() throws -> [(text: String, date: Date)] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT m.ROWID, m.text, m.date, m.is_from_me,
               COALESCE(h.id, '') AS sender_handle,
               cmj.chat_id
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE m.text IS NOT NULL AND m.text != ''
          AND m.associated_message_guid IS NULL
        ORDER BY cmj.chat_id, m.date ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 905,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        struct Row {
            let rowId: Int64; let text: String; let date: Date
            let isFromMe: Bool; let sender: String; let chatId: Int64
        }

        var seenRowIds: Set<Int64> = []
        var chatBuckets: [Int64: [Row]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)
            guard !seenRowIds.contains(rowId),
                  let textC = sqlite3_column_text(stmt, 1) else { continue }
            seenRowIds.insert(rowId)

            let text = String(cString: textC)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let rawDate = sqlite3_column_int64(stmt, 2)
            let secs = rawDate > 1_000_000_000 ? Double(rawDate) / 1_000_000_000 : Double(rawDate)
            let date = Date(timeIntervalSinceReferenceDate: secs)
            let isFromMe = sqlite3_column_int(stmt, 3) == 1
            let sender   = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let chatId   = sqlite3_column_int64(stmt, 5)

            chatBuckets[chatId, default: []].append(
                Row(rowId: rowId, text: text, date: date,
                    isFromMe: isFromMe, sender: sender, chatId: chatId)
            )
        }

        // For each of the user's messages, build a ±2 conversation snippet.
        var snippets: [(text: String, date: Date)] = []
        for messages in chatBuckets.values {
            for (i, msg) in messages.enumerated() where msg.isFromMe {
                let start  = max(0, i - 2)
                let end    = min(messages.count - 1, i + 2)
                let window = messages[start...end]

                let formatted = window.map { m -> String in
                    let name: String
                    if m.isFromMe {
                        name = "You"
                    } else {
                        let resolved = ContactNameCache.shared.resolve(m.sender)
                        name = (resolved == m.sender || resolved.isEmpty) ? "Friend" : resolved
                    }
                    return "\(name): \(redactOffensiveContent(String(m.text.prefix(120))))"
                }.joined(separator: "\n")

                snippets.append((text: formatted, date: msg.date))
            }
        }
        return snippets.sorted { $0.date < $1.date }
    }

    // Returns contacts with temporal context + DM vs group message split.
    private static func fetchContactsWithTimeline(
        groupChats: [(chatName: String, members: [String])]
    ) -> [ContactSummary] {
        guard let db = try? openDB() else { return [] }
        defer { if db != nil { sqlite3_close(db) } }

        // Count total AND 1:1 DM messages separately.
        // DM chats = chats with exactly 1 handle (the other person).
        let sql = """
        SELECT h.id,
               COUNT(DISTINCT m.ROWID) AS total_msgs,
               COUNT(DISTINCT CASE
                   WHEN cmj.chat_id IN (
                       SELECT chat_id FROM chat_handle_join
                       GROUP BY chat_id HAVING COUNT(*) = 1
                   ) THEN m.ROWID END) AS dm_msgs,
               MIN(m.date)  AS first_date,
               MAX(m.date)  AS last_date
        FROM handle h
        JOIN message m ON m.handle_id = h.ROWID
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE m.associated_message_guid IS NULL
          AND m.text IS NOT NULL AND m.text != ''
        GROUP BY h.id
        ORDER BY total_msgs DESC
        LIMIT 300;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        struct Raw { let handle: String; let total: Int; let dm: Int; let first: Date; let last: Date }
        var raw: [Raw] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            let toDate: (Int64) -> Date = { v in
                let s = v > 1_000_000_000 ? Double(v) / 1_000_000_000 : Double(v)
                return Date(timeIntervalSinceReferenceDate: s)
            }
            raw.append(Raw(
                handle: String(cString: c),
                total: Int(sqlite3_column_int(stmt, 1)),
                dm:    Int(sqlite3_column_int(stmt, 2)),
                first: toDate(sqlite3_column_int64(stmt, 3)),
                last:  toDate(sqlite3_column_int64(stmt, 4))
            ))
        }

        // Resolve handles → contact names; merge duplicates (same person, multiple numbers).
        // For single-word names (e.g. "Nathan"), use the handle as the merge key so that two
        // different people with the same first name stay as separate entries. Full names
        // (containing a space) can safely be merged across phone/email handles.
        struct Merged { var total: Int; var dm: Int; var first: Date; var last: Date; var displayName: String }
        var merged: [String: Merged] = [:]
        for r in raw {
            let name = ContactNameCache.shared.resolve(r.handle)
            guard name != r.handle, !name.isEmpty else { continue }
            let key = name.contains(" ") ? name : r.handle
            if let ex = merged[key] {
                merged[key] = Merged(total: ex.total + r.total, dm: ex.dm + r.dm,
                                     first: min(ex.first, r.first), last: max(ex.last, r.last),
                                     displayName: ex.displayName)
            } else {
                merged[key] = Merged(total: r.total, dm: r.dm, first: r.first, last: r.last,
                                     displayName: name)
            }
        }

        var sharedChats: [String: Int] = [:]
        for chat in groupChats {
            for member in chat.members { sharedChats[member, default: 0] += 1 }
        }

        let recentCutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        return merged.map { _, m -> ContactSummary in
            ContactSummary(
                name: m.displayName,
                messageCount: m.total,
                dmMessageCount: m.dm,
                firstSeen: quarterLabel(for: m.first),
                lastSeen: m.last >= recentCutoff ? "present" : quarterLabel(for: m.last),
                sharedGroupChats: sharedChats[m.displayName, default: 0]
            )
        }
        .sorted { $0.messageCount > $1.messageCount }
    }

    // MARK: - Snippet quality scoring

    // Scores a ±2 conversation snippet by information density.
    // Higher = more worth sending to Claude. Name bonus ensures important people surface.
    private static func snippetScore(_ snippet: String, priorityNames: [String]) -> Double {
        let lines = snippet.split(separator: "\n", omittingEmptySubsequences: true)

        // Primary signal: quality of the user's own message in the snippet.
        let userContent = lines
            .first(where: { $0.hasPrefix("You: ") })
            .map { String($0.dropFirst(5)) } ?? ""
        var score = messageQualityScore(userContent) * 2.0  // user's message weighted double

        // Secondary: context lines also contribute (less weight).
        for line in lines where !line.hasPrefix("You: ") {
            let content = line.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
            score += messageQualityScore(content) * 0.4
        }

        // Name bonus — ensures contacts with high DM counts aren't crowded out.
        if priorityNames.contains(where: { snippet.localizedCaseInsensitiveContains($0) }) {
            score += 5.0
        }

        return score
    }

    // MARK: - Content redaction

    private static let offensivePatterns: [(NSRegularExpression, String)] = {
        let pairs: [(String, String)] = [
            ("\\bretard(?:ed|s)?\\b", "[redacted]"),
            ("\\bfagg?(?:ot|ots)?\\b", "[redacted]"),
            ("\\bn[i1][g9][g9][ae][rszn]?\\b", "[redacted]"),
            ("\\bspics?\\b", "[redacted]"),
            ("\\bkikes?\\b", "[redacted]"),
            ("\\bchinks?\\b", "[redacted]"),
            ("\\bcunts?\\b", "[redacted]"),
        ]
        return pairs.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (regex, replacement)
        }
    }()

    private static func redactOffensiveContent(_ text: String) -> String {
        var result = text
        for (regex, replacement) in offensivePatterns {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return result
    }

    private static let lowQualityWords: Set<String> = [
        "k", "ok", "okay", "yes", "no", "ya", "yep", "nope", "sure", "fine",
        "haha", "hahaha", "hahahaha", "lol", "lmao", "lmaoo", "lmaooo", "hehe",
        "omg", "omgg", "wow", "nice", "cool", "great", "good", "bad", "true",
        "fr", "ngl", "ight", "aight", "bet", "facts", "cap", "💀", "😂", "👍",
        "yea", "yeah", "nah", "ikr", "ik", "idk", "smh", "bruh", "bro",
    ]

    private static func messageQualityScore(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return -3.0 }

        let lower = trimmed.lowercased()
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let wc = words.count

        // Pure single-token reactions / slop
        if wc <= 1 {
            return lowQualityWords.contains(lower) ? -3.0 : 0.5
        }

        // Short low-quality combos ("haha yeah", "lol ok", "omg lol")
        if wc <= 3 && words.map({ $0.lowercased() }).allSatisfy({ lowQualityWords.contains($0) }) {
            return -2.0
        }

        // Laugh/reaction openers with very short tails are still mostly noise
        let lowQualityPrefixes = ["haha", "hahaha", "lol", "lmao", "omg", "lmaoo"]
        if wc <= 4 && lowQualityPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return 0.0
        }

        // Penalty for pure-emoji messages
        let nonEmojiChars = trimmed.unicodeScalars.filter { !$0.properties.isEmojiPresentation }
        if nonEmojiChars.count < 3 { return -1.0 }

        // Length score: sweet spot 6–40 words; diminishing returns after 60 (possible copy-paste)
        let lengthScore: Double
        switch wc {
        case 1...5:   lengthScore = Double(wc) * 0.6
        case 6...40:  lengthScore = 3.0 + Double(wc) * 0.25
        case 41...80: lengthScore = 13.0 + Double(wc - 40) * 0.08
        default:      lengthScore = 13.0 + 40 * 0.08  // cap — very long may be copy-paste
        }

        // Lexical richness bonus: many unique words = substantive, not repetitive
        let uniqueRatio = Double(Set(words.map { $0.lowercased() }).count) / Double(wc)
        let lexBonus = uniqueRatio > 0.8 ? 2.5 : uniqueRatio > 0.6 ? 1.5 : uniqueRatio > 0.4 ? 0.5 : 0.0

        return lengthScore + lexBonus
    }

    private static func quarterLabel(for date: Date) -> String {
        let cal     = Calendar.current
        let year    = cal.component(.year,  from: date)
        let month   = cal.component(.month, from: date)
        let quarter = (month - 1) / 3 + 1
        return "Q\(quarter) \(year)"
    }

    // Returns the top group chats with their resolved participant names.
    private static func fetchGroupChatSummaries() -> [(chatName: String, members: [String])] {
        guard let db = try? openDB() else { return [] }
        defer { if db != nil { sqlite3_close(db) } }

        // Fetch (chat_id, display_name, handle) for all group chats.
        let sql = """
        SELECT c.ROWID,
               COALESCE(NULLIF(c.display_name, ''), c.chat_identifier) AS chat_name,
               h.id AS handle
        FROM chat c
        JOIN chat_handle_join chj ON chj.chat_id = c.ROWID
        JOIN handle h ON h.ROWID = chj.handle_id
        ORDER BY c.ROWID DESC
        LIMIT 2000;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var chats: [Int64: (name: String, handles: [String])] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(stmt, 1),
                  let handleC = sqlite3_column_text(stmt, 2) else { continue }
            let chatId = sqlite3_column_int64(stmt, 0)
            if chats[chatId] == nil {
                chats[chatId] = (name: String(cString: nameC), handles: [])
            }
            chats[chatId]!.handles.append(String(cString: handleC))
        }

        // Keep only chats with 3+ resolved-name participants; take top 15 by size.
        return chats.values.compactMap { chat -> (chatName: String, members: [String])? in
            var seen: Set<String> = []
            let members: [String] = chat.handles.compactMap { handle in
                let name = ContactNameCache.shared.resolve(handle)
                guard name != handle, !name.isEmpty, !seen.contains(name) else { return nil }
                seen.insert(name)
                return name
            }
            guard members.count >= 3 else { return nil }
            return (chatName: chat.name, members: members)
        }
        .sorted { $0.members.count > $1.members.count }
        .prefix(15)
        .map { $0 }
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
