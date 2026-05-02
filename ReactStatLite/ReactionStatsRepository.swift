import Foundation
import SQLite3

enum ReactionKind: Int, CaseIterable, Identifiable {
    case loved = 2000
    case liked = 2001
    case disliked = 2002
    case laughed = 2003
    case emphasized = 2004
    case questioned = 2005

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .laughed: return "Haha"
        case .liked: return "Like"
        case .loved: return "Love"
        case .emphasized: return "Emphasize"
        case .questioned: return "Question"
        case .disliked: return "Dislike"
        }
    }

    var emoji: String {
        switch self {
        case .laughed: return "😂"
        case .liked: return "👍"
        case .loved: return "❤️"
        case .emphasized: return "‼️"
        case .questioned: return "❓"
        case .disliked: return "👎"
        }
    }
}

struct LeaderRow: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct RatioRow: Identifiable {
    let id = UUID()
    let name: String
    let numerator: Int
    let denominator: Int
    let ratio: Double

    let numeratorLabel: String
    let denominatorLabel: String
}

struct ShareRow: Identifiable {
    let id = UUID()
    let name: String
    let messages: Int
    let share: Double
}

enum ReactionStatsRepository {

    // MARK: - DB helper

    private static func openDB() throws -> OpaquePointer? {
        let dbPath = MessagesDBHealth.chatDBURL().path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            defer { if db != nil { sqlite3_close(db) } }
            let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            throw NSError(domain: "ReactStatLite", code: 900, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        sqlite3_busy_timeout(db, 1500)
        return db
    }

    private static func text(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    private static func resolveName(_ raw: String) -> String {
        ContactNameCache.shared.resolve(raw)
    }

    // MARK: - Totals

    static func totalReactionsInChat(chatRowId: Int64) throws -> Int {
        // Check if this is demo data (negative ID)
        if chatRowId == -1 {
            return DemoData.demoAllReactions.reduce(0) { $0 + $1.count }
        }
        
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT COUNT(*)
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
          AND r.associated_message_type BETWEEN 2000 AND 2005;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ReactStatLite", code: 120, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    static func totalMessagesInChat(chatRowId: Int64) throws -> Int {
        // Check if this is demo data (negative ID)
        if chatRowId == -1 {
            return DemoData.demoMessageCounts.values.reduce(0, +)
        }
        
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT COUNT(*)
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        WHERE cmj.chat_id = ?
          AND m.associated_message_guid IS NULL;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ReactStatLite", code: 121, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Messages sent per person (exclude reaction rows)

    static func messageCountsBySender(chatRowId: Int64) throws -> [String: Int] {
        // Check if this is demo data (negative ID)
        if chatRowId == -1 {
            return DemoData.demoMessageCounts
        }
        
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
          CASE
            WHEN m.is_from_me = 1 THEN 'Me'
            ELSE COALESCE(h.id, 'Unknown')
          END AS person,
          COUNT(*) AS c
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE cmj.chat_id = ?
          AND m.associated_message_guid IS NULL
        GROUP BY person;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ReactStatLite", code: 130, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)

        var out: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let raw = text(stmt, 0) ?? "Unknown"
            let person = resolveName(raw)
            let count = Int(sqlite3_column_int(stmt, 1))
            out[person] = count
        }
        return out
    }

    static func messageShareLeaderboard(chatRowId: Int64, limit: Int = 10, minMessages: Int = 20) throws -> [ShareRow] {
        let counts = try messageCountsBySender(chatRowId: chatRowId)
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }

        var rows: [ShareRow] = []
        rows.reserveCapacity(counts.count)

        for (person, msgs) in counts where msgs >= minMessages {
            rows.append(ShareRow(name: person, messages: msgs, share: Double(msgs) / Double(total)))
        }

        rows.sort {
            if $0.share != $1.share { return $0.share > $1.share }
            return $0.messages > $1.messages
        }

        return Array(rows.prefix(limit))
    }

    // MARK: - Reaction givers (existing)

    static func topReactionGivers(chatRowId: Int64, kind: ReactionKind, limit: Int = 10) throws -> [LeaderRow] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
          CASE
            WHEN r.is_from_me = 1 THEN 'Me'
            ELSE COALESCE(h.id, 'Unknown')
          END AS person,
          COUNT(*) AS c
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        LEFT JOIN handle h ON h.ROWID = r.handle_id
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
          AND r.associated_message_type = ?
        GROUP BY person
        ORDER BY c DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ReactStatLite", code: 101, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(kind.rawValue))
        sqlite3_bind_int(stmt, 3, Int32(limit))

        var out: [LeaderRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let raw = text(stmt, 0) ?? "Unknown"
            let person = resolveName(raw)
            let count = Int(sqlite3_column_int(stmt, 1))
            out.append(LeaderRow(name: person, count: count))
        }
        return out
    }

    // MARK: - Receiver engine (Swift, fast)  ✅ uses your working normalization

    private static func canonicalGuidKeys(_ guid: String) -> [String] {
        let g0 = guid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g0.isEmpty else { return [] }

        var keys: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { keys.append(t) }
        }

        add(g0)

        if g0.hasPrefix("p:") { add(String(g0.dropFirst(2))) }
        if g0.hasPrefix("bp:") { add(String(g0.dropFirst(3))) }

        if let slash = g0.lastIndex(of: "/") {
            add(String(g0[g0.index(after: slash)...]))
        }

        if g0.hasPrefix("p:") {
            let s = String(g0.dropFirst(2))
            add(s)
            if let slash = s.lastIndex(of: "/") {
                add(String(s[s.index(after: slash)...]))
            }
        }
        if g0.hasPrefix("bp:") {
            let s = String(g0.dropFirst(3))
            add(s)
            if let slash = s.lastIndex(of: "/") {
                add(String(s[s.index(after: slash)...]))
            }
        }

        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private static func buildGuidToSenderMap(chatRowId: Int64, messageScanLimit: Int) throws -> [String: String] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
          m.guid,
          CASE
            WHEN m.is_from_me = 1 THEN 'Me'
            ELSE COALESCE(h.id, 'Unknown')
          END AS sender
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE cmj.chat_id = ?
          AND m.associated_message_guid IS NULL
          AND m.guid IS NOT NULL
        ORDER BY m.date DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 301, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(messageScanLimit))

        var map: [String: String] = [:]
        map.reserveCapacity(messageScanLimit)

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let guid = text(stmt, 0) else { continue }
            let senderRaw = text(stmt, 1) ?? "Unknown"
            let sender = resolveName(senderRaw)

            for k in canonicalGuidKeys(guid) {
                if map[k] == nil { map[k] = sender }
            }
        }

        return map
    }

    private static func receiverCountsByKind(
        chatRowId: Int64,
        reactionScanLimit: Int,
        messageScanLimit: Int
    ) throws -> [ReactionKind: [String: Int]] {
        
        // Check if this is demo data (negative ID)
        if chatRowId == -1 {
            var out: [ReactionKind: [String: Int]] = [:]
            for reaction in DemoData.demoAllReactions {
                var dict = out[reaction.kind] ?? [:]
                dict[reaction.to, default: 0] += reaction.count
                out[reaction.kind] = dict
            }
            return out
        }

        let guidToSender = try buildGuidToSenderMap(chatRowId: chatRowId, messageScanLimit: messageScanLimit)

        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
          r.associated_message_guid,
          r.associated_message_type
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
          AND r.associated_message_type BETWEEN 2000 AND 2005
        ORDER BY r.date DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 302, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(reactionScanLimit))

        var out: [ReactionKind: [String: Int]] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let assoc = text(stmt, 0) else { continue }
            let t = Int(sqlite3_column_int(stmt, 1))
            guard let rk = ReactionKind(rawValue: t) else { continue }

            var receiver: String? = nil
            for k in canonicalGuidKeys(assoc) {
                if let found = guidToSender[k] {
                    receiver = found
                    break
                }
            }
            guard let receiver else { continue }

            var dict = out[rk] ?? [:]
            dict[receiver, default: 0] += 1
            out[rk] = dict
        }

        return out
    }

    // MARK: - Given counts for all kinds in one pass (fast SQL)

    private static func givenCountsByKind(chatRowId: Int64) throws -> [ReactionKind: [String: Int]] {
        // Check if this is demo data (negative ID)
        if chatRowId == -1 {
            var out: [ReactionKind: [String: Int]] = [:]
            for reaction in DemoData.demoAllReactions {
                var dict = out[reaction.kind] ?? [:]
                dict[reaction.from, default: 0] += reaction.count
                out[reaction.kind] = dict
            }
            return out
        }
        
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
          r.associated_message_type AS t,
          CASE
            WHEN r.is_from_me = 1 THEN 'Me'
            ELSE COALESCE(h.id, 'Unknown')
          END AS person,
          COUNT(*) AS c
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        LEFT JOIN handle h ON h.ROWID = r.handle_id
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
          AND r.associated_message_type BETWEEN 2000 AND 2005
        GROUP BY t, person;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 401, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)

        var out: [ReactionKind: [String: Int]] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let t = Int(sqlite3_column_int(stmt, 0))
            guard let kind = ReactionKind(rawValue: t) else { continue }

            let raw = text(stmt, 1) ?? "Unknown"
            let person = resolveName(raw)
            let c = Int(sqlite3_column_int(stmt, 2))

            var dict = out[kind] ?? [:]
            dict[person] = (dict[person] ?? 0) + c
            out[kind] = dict
        }

        return out
    }

    // MARK: - Public: ratio leaderboards for ALL kinds (what the UI will use)

    static func givenPerMessageLeaderboardsAllKinds(
        chatRowId: Int64,
        kinds: [ReactionKind],
        limit: Int = 10,
        minMessages: Int = 30
    ) throws -> [ReactionKind: [RatioRow]] {

        let given = try givenCountsByKind(chatRowId: chatRowId)
        let msgs = try messageCountsBySender(chatRowId: chatRowId)

        var out: [ReactionKind: [RatioRow]] = [:]

        for kind in kinds {
            let givenCounts = given[kind] ?? [:]

            var rows: [RatioRow] = []
            for (person, m) in msgs where m >= minMessages {
                let num = givenCounts[person] ?? 0
                let ratio = m > 0 ? Double(num) / Double(m) : 0
                rows.append(RatioRow(
                    name: person,
                    numerator: num,
                    denominator: m,
                    ratio: ratio,
                    numeratorLabel: "\(kind.emoji) given",
                    denominatorLabel: "msgs"
                ))
            }

            rows.sort {
                if $0.ratio != $1.ratio { return $0.ratio > $1.ratio }
                return $0.denominator > $1.denominator
            }

            out[kind] = Array(rows.prefix(limit))
        }

        return out
    }

    static func receivedPerMessageLeaderboardsAllKinds(
        chatRowId: Int64,
        kinds: [ReactionKind],
        limit: Int = 10,
        minMessages: Int = 30,
        reactionScanLimit: Int = 80_000,
        messageScanLimit: Int = 80_000
    ) throws -> [ReactionKind: [RatioRow]] {

        let received = try receiverCountsByKind(
            chatRowId: chatRowId,
            reactionScanLimit: reactionScanLimit,
            messageScanLimit: messageScanLimit
        )
        let msgs = try messageCountsBySender(chatRowId: chatRowId)

        var out: [ReactionKind: [RatioRow]] = [:]

        for kind in kinds {
            let receivedCounts = received[kind] ?? [:]

            var rows: [RatioRow] = []
            for (person, m) in msgs where m >= minMessages {
                let num = receivedCounts[person] ?? 0
                let ratio = m > 0 ? Double(num) / Double(m) : 0
                rows.append(RatioRow(
                    name: person,
                    numerator: num,
                    denominator: m,
                    ratio: ratio,
                    numeratorLabel: "\(kind.emoji) received",
                    denominatorLabel: "msgs"
                ))
            }

            rows.sort {
                if $0.ratio != $1.ratio { return $0.ratio > $1.ratio }
                return $0.denominator > $1.denominator
            }

            out[kind] = Array(rows.prefix(limit))
        }

        return out
    }

    // MARK: - Optional debug (keep)

    static func debugTapbackTypes(chatRowId: Int64, limit: Int = 50) throws -> [(type: Int, count: Int)] {
        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT r.associated_message_type AS t, COUNT(*) AS c
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
        GROUP BY t
        ORDER BY c DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ReactStatLite", code: 201, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var out: [(Int, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((Int(sqlite3_column_int(stmt, 0)), Int(sqlite3_column_int(stmt, 1))))
        }
        return out
    }
}
