import Foundation
import SQLite3

enum PremiumStatsRepository {

    struct DirectedEdge {
        let fromName: String
        let toName: String
        let count: Int
    }

    private struct ReactionAggregates {
        var totalReactions: Int = 0
        var totalByKind: [ReactionKind: Int] = [:]

        var givenByPerson: [String: Int] = [:]
        var receivedByPerson: [String: Int] = [:]

        var givenByPersonByKind: [String: [ReactionKind: Int]] = [:]
    }

    private static let allKinds: [ReactionKind] = [.laughed, .liked, .loved, .emphasized, .questioned, .disliked]

    // MARK: - Public API

    static func premiumStats(
        chatRowId: Int64,
        reactionScanLimit: Int = 120_000,
        messageScanLimit: Int = 120_000
    ) throws -> [PremiumStat] {

        // Build guid -> sender map once
        let guidToSender = try buildGuidToSenderMap(chatRowId: chatRowId, messageScanLimit: messageScanLimit)

        // Existing stats use laughed edges (only 😂)
        let laughEdges = try laughedDirectedEdgesFromMap(
            chatRowId: chatRowId,
            guidToSender: guidToSender,
            minCount: 1,
            reactionScanLimit: reactionScanLimit
        )

        // New stats need all reactions (all kinds)
        let aggs = try reactionAggregatesFromMap(
            chatRowId: chatRowId,
            guidToSender: guidToSender,
            reactionScanLimit: reactionScanLimit
        )

        let msgCounts = try ReactionStatsRepository.messageCountsBySender(chatRowId: chatRowId)
        let totalMsgs = max(1, msgCounts.values.reduce(0, +))
        let participantCount = max(1, msgCounts.count)

        func msgBaselineShare(_ person: String) -> Double {
            let m = msgCounts[person] ?? 0
            let b = Double(m) / Double(totalMsgs)
            return max(0.0005, b)
        }

        // Existing premium stats
        let glazer = biggestGlazerOrFallback(edges: laughEdges, baseline: msgBaselineShare)
        let romance = buddingRomanceOrFallback(edges: laughEdges, baseline: msgBaselineShare)

        // New premium stats
        let ignored = mostIgnoredOrFallback(
            msgCounts: msgCounts,
            totalMsgs: totalMsgs,
            receivedByPerson: aggs.receivedByPerson,
            totalReactions: aggs.totalReactions
        )

        let king = reactionKingOrFallback(
            msgCounts: msgCounts,
            totalMsgs: totalMsgs,
            receivedByPerson: aggs.receivedByPerson,
            totalReactions: aggs.totalReactions
        )

        let personality = reactionPersonalityOrFallback(
            givenByPersonByKind: aggs.givenByPersonByKind,
            totalByKind: aggs.totalByKind,
            totalReactions: aggs.totalReactions
        )

        let watcher = silentWatcherOrFallback(
            msgCounts: msgCounts,
            totalMsgs: totalMsgs,
            participantCount: participantCount,
            givenByPerson: aggs.givenByPerson
        )

        // Order matters (what shows first)
        return [glazer, romance, king, ignored, personality, watcher]
    }

    // MARK: - Biggest Glazer

    private static func biggestGlazerOrFallback(
        edges: [DirectedEdge],
        baseline: (String) -> Double
    ) -> PremiumStat {
        let minCount = 3
        let minShare = 0.30

        if edges.isEmpty {
            return PremiumStat(kind: .biggestGlazer,
                               title: "Biggest Glazer",
                               subtitle: "Not enough 😂 reactions in this chat yet.",
                               score: 0)
        }

        var totalsGiven: [String: Int] = [:]
        for e in edges { totalsGiven[e.fromName, default: 0] += e.count }

        var best: (edge: DirectedEdge, share: Double, adjustment: Double, score: Double)? = nil

        for e in edges where e.count >= minCount {
            guard let total = totalsGiven[e.fromName], total > 0 else { continue }

            let share = Double(e.count) / Double(total)
            guard share >= minShare else { continue }

            let expected = baseline(e.toName)
            let adjustment = (share / expected) - 1.0 // +0.20 => +20%

            let score = max(0.0, adjustment) * log(1.0 + Double(e.count))

            if best == nil || score > best!.score {
                best = (e, share, adjustment, score)
            }
        }

        guard let best else {
            if let top = edges.max(by: { $0.count < $1.count }) {
                return PremiumStat(kind: .biggestGlazer,
                                   title: "Biggest Glazer",
                                   subtitle: "Not enough data yet. Top 😂 link: \(top.fromName) → \(top.toName) (\(top.count)).",
                                   score: 0)
            }
            return PremiumStat(kind: .biggestGlazer,
                               title: "Biggest Glazer",
                               subtitle: "Not enough 😂 reactions in this chat yet.",
                               score: 0)
        }

        let pct = Int((best.share * 100).rounded())
        let adjPct = Int((best.adjustment * 100).rounded())

        let phrase: String
        if adjPct >= 0 {
            phrase = "+\(adjPct)% above expected (message-volume adjusted)"
        } else {
            phrase = "\(abs(adjPct))% below expected (message-volume adjusted)"
        }

        let subtitle = "\(best.edge.fromName) 😂→ \(best.edge.toName) (\(best.edge.count) times, \(pct)% of their 😂 reactions, \(phrase))"

        return PremiumStat(kind: .biggestGlazer,
                           title: "Biggest Glazer",
                           subtitle: subtitle,
                           score: best.score)
    }

    // MARK: - Budding Romance

    private static func buddingRomanceOrFallback(
        edges: [DirectedEdge],
        baseline: (String) -> Double
    ) -> PremiumStat {
        let minEachDirection = 2

        if edges.isEmpty {
            return PremiumStat(kind: .buddingRomance,
                               title: "Budding Romance",
                               subtitle: "Not enough 😂 reactions in this chat yet.",
                               score: 0)
        }

        var totalsGiven: [String: Int] = [:]
        var map: [String: [String: Int]] = [:]

        for e in edges {
            totalsGiven[e.fromName, default: 0] += e.count
            map[e.fromName, default: [:]][e.toName] = e.count
        }

        var best: (a: String, b: String, ab: Int, ba: Int, shareAB: Double, shareBA: Double, mutualAdj: Double, score: Double)? = nil

        for e in edges {
            let a = e.fromName
            let b = e.toName
            if a > b { continue }

            let ab = e.count
            guard let ba = map[b]?[a] else { continue }
            guard ab >= minEachDirection, ba >= minEachDirection else { continue }

            guard let totalA = totalsGiven[a], totalA > 0,
                  let totalB = totalsGiven[b], totalB > 0 else { continue }

            let shareAB = Double(ab) / Double(totalA)
            let shareBA = Double(ba) / Double(totalB)

            let adjAB = (shareAB / baseline(b)) - 1.0
            let adjBA = (shareBA / baseline(a)) - 1.0
            let mutualAdj = (adjAB + adjBA) / 2.0

            let vol = log(1.0 + Double(ab + ba))
            let score = max(0.0, mutualAdj) * vol

            if best == nil || score > best!.score {
                best = (a, b, ab, ba, shareAB, shareBA, mutualAdj, score)
            }
        }

        guard let best else {
            return PremiumStat(kind: .buddingRomance,
                               title: "Budding Romance",
                               subtitle: "Not enough two-way 😂 yet.",
                               score: 0)
        }

        let pctA = Int((best.shareAB * 100).rounded())
        let pctB = Int((best.shareBA * 100).rounded())

        let adjPct = Int((best.mutualAdj * 100).rounded())

        let phrase: String
        if adjPct >= 0 {
            phrase = "+\(adjPct)% above expected (message-volume adjusted)"
        } else {
            phrase = "\(abs(adjPct))% below expected (message-volume adjusted)"
        }

        let subtitle = "\(best.a) ↔ \(best.b) (😂 \(best.ab)/\(best.ba), \(pctA)%/\(pctB)% of their 😂 reactions, \(phrase))"

        return PremiumStat(kind: .buddingRomance,
                           title: "Budding Romance",
                           subtitle: subtitle,
                           score: best.score)
    }

    // MARK: - NEW: Most Ignored

    private static func mostIgnoredOrFallback(
        msgCounts: [String: Int],
        totalMsgs: Int,
        receivedByPerson: [String: Int],
        totalReactions: Int
    ) -> PremiumStat {
        guard totalReactions > 0 else {
            return PremiumStat(kind: .mostIgnored,
                               title: "Most Ignored",
                               subtitle: "Not enough reactions in this chat yet.",
                               score: 0)
        }

        let minMessages = 20
        let minMsgShare = 0.10

        var bestName: String? = nil
        var bestScore: Double = -1
        var bestMsgShare: Double = 0
        var bestReactShare: Double = 0

        for (name, msgs) in msgCounts where msgs >= minMessages {
            let msgShare = Double(msgs) / Double(totalMsgs)
            guard msgShare >= minMsgShare else { continue }

            let recvd = receivedByPerson[name] ?? 0
            let reactShare = Double(recvd) / Double(totalReactions)

            // How far below expected (expected = msgShare)
            let gap = msgShare - reactShare
            let score = max(0.0, gap) * log(1.0 + Double(msgs))

            if score > bestScore {
                bestScore = score
                bestName = name
                bestMsgShare = msgShare
                bestReactShare = reactShare
            }
        }

        guard let bestName else {
            return PremiumStat(kind: .mostIgnored,
                               title: "Most Ignored",
                               subtitle: "Not enough message volume to call it.",
                               score: 0)
        }

        let msgPct = Int((bestMsgShare * 100).rounded())
        let reactPct = Int((bestReactShare * 100).rounded())

        // vs expected phrasing
        let expected = bestMsgShare
        let adj = (bestReactShare / max(0.0005, expected)) - 1.0
        let adjPct = Int((adj * 100).rounded())
        let phrase: String = adjPct >= 0
            ? "+\(adjPct)% above expected"
            : "\(abs(adjPct))% below expected"

        let subtitle = "\(bestName) (\(msgPct)% of msgs, \(reactPct)% of reactions, \(phrase))"

        return PremiumStat(kind: .mostIgnored,
                           title: "Most Ignored",
                           subtitle: subtitle,
                           score: bestScore)
    }

    // MARK: - NEW: Reaction King / Queen

    private static func reactionKingOrFallback(
        msgCounts: [String: Int],
        totalMsgs: Int,
        receivedByPerson: [String: Int],
        totalReactions: Int
    ) -> PremiumStat {
        guard totalMsgs > 0, totalReactions > 0 else {
            return PremiumStat(kind: .reactionKing,
                               title: "Reaction King/Queen",
                               subtitle: "Not enough data yet.",
                               score: 0)
        }

        let minMessages = 10
        let minReactionsReceived = 5

        let avgRPM = Double(totalReactions) / Double(totalMsgs)

        var bestName: String? = nil
        var bestRatio: Double = -1
        var bestMsgs: Int = 0
        var bestRecv: Int = 0

        for (name, msgs) in msgCounts where msgs >= minMessages {
            let recvd = receivedByPerson[name] ?? 0
            guard recvd >= minReactionsReceived else { continue }

            let rpm = Double(recvd) / Double(msgs)
            let ratio = rpm / max(0.0001, avgRPM)

            if ratio > bestRatio {
                bestRatio = ratio
                bestName = name
                bestMsgs = msgs
                bestRecv = recvd
            }
        }

        guard let bestName else {
            return PremiumStat(kind: .reactionKing,
                               title: "Reaction King/Queen",
                               subtitle: "Not enough consistent reactions yet.",
                               score: 0)
        }

        let subtitle = "\(bestName) (\(String(format: "%.1f", bestRatio))× reactions received per msg vs avg, \(bestRecv) reacts / \(bestMsgs) msgs)"

        return PremiumStat(kind: .reactionKing,
                           title: "Reaction King/Queen",
                           subtitle: subtitle,
                           score: bestRatio)
    }

    // MARK: - NEW: Reaction Personality

    private static func reactionPersonalityOrFallback(
        givenByPersonByKind: [String: [ReactionKind: Int]],
        totalByKind: [ReactionKind: Int],
        totalReactions: Int
    ) -> PremiumStat {

        // We no longer use totalByKind/totalReactions for the baseline,
        // but keep the signature so your call site doesn't change.
        let minTotalGiven = 12
        let minDominantShare = 0.45

        // 1) Build per-person shares
        var personTotalGiven: [String: Int] = [:]
        var personShareByKind: [String: [ReactionKind: Double]] = [:]

        for (name, byKind) in givenByPersonByKind {
            let totalGiven = byKind.values.reduce(0, +)
            guard totalGiven >= minTotalGiven else { continue }

            personTotalGiven[name] = totalGiven

            var shares: [ReactionKind: Double] = [:]
            for kind in allKinds {
                let c = byKind[kind] ?? 0
                shares[kind] = Double(c) / Double(totalGiven)
            }
            personShareByKind[name] = shares
        }

        guard !personShareByKind.isEmpty else {
            return PremiumStat(kind: .reactionPersonality,
                               title: "Reaction Personality",
                               subtitle: "Not enough reactions yet.",
                               score: 0)
        }

        // 2) Baseline = average share across PEOPLE (not total counts)
        var baselineByKind: [ReactionKind: Double] = [:]
        for kind in allKinds {
            var sum: Double = 0
            var n: Double = 0
            for (_, shares) in personShareByKind {
                if let s = shares[kind] {
                    sum += s
                    n += 1
                }
            }
            baselineByKind[kind] = (n > 0) ? (sum / n) : 0.0005
        }

        // 3) Find strongest personality: dominant kind vs baseline
        var bestName: String? = nil
        var bestKind: ReactionKind? = nil
        var bestShare: Double = 0
        var bestBaseline: Double = 0
        var bestScore: Double = -1

        for (name, shares) in personShareByKind {
            // dominant kind for this person
            guard let (kind, share) = shares.max(by: { $0.value < $1.value }) else { continue }
            guard share >= minDominantShare else { continue }

            let base = max(0.0005, baselineByKind[kind] ?? 0.0005)
            let score = share / base

            if score > bestScore {
                bestScore = score
                bestName = name
                bestKind = kind
                bestShare = share
                bestBaseline = base
            }
        }

        guard let bestName, let bestKind else {
            return PremiumStat(kind: .reactionPersonality,
                               title: "Reaction Personality",
                               subtitle: "No strong reaction personality yet.",
                               score: 0)
        }

        let pct = Int((bestShare * 100).rounded())
        let basePct = Int((bestBaseline * 100).rounded())
        let x = bestScore

        let subtitle = "\(bestName) (known for \(bestKind.emoji) — \(pct)% of their reactions, avg \(basePct)% → \(String(format: "%.1f", x))×)"

        return PremiumStat(kind: .reactionPersonality,
                           title: "Reaction Personality",
                           subtitle: subtitle,
                           score: bestScore)
    }


    // MARK: - NEW: Silent Watcher

    private static func silentWatcherOrFallback(
        msgCounts: [String: Int],
        totalMsgs: Int,
        participantCount: Int,
        givenByPerson: [String: Int]
    ) -> PremiumStat {
        guard participantCount > 0 else {
            return PremiumStat(kind: .silentWatcher,
                               title: "Silent Watcher",
                               subtitle: "Not enough data yet.",
                               score: 0)
        }

        let avgMsgs = Double(totalMsgs) / Double(participantCount)

        // "silent" threshold: half the average, but at least 8 msgs
        let silentMaxMsgs = max(8, Int((avgMsgs * 0.5).rounded()))

        let minReactionsGiven = 12

        var bestName: String? = nil
        var bestScore: Double = -1
        var bestMsgs: Int = 0
        var bestGiven: Int = 0

        for (name, msgs) in msgCounts where msgs <= silentMaxMsgs {
            let given = givenByPerson[name] ?? 0
            guard given >= minReactionsGiven else { continue }

            let score = Double(given) / Double(max(1, msgs)) // reacts per msg
            if score > bestScore {
                bestScore = score
                bestName = name
                bestMsgs = msgs
                bestGiven = given
            }
        }

        guard let bestName else {
            return PremiumStat(kind: .silentWatcher,
                               title: "Silent Watcher",
                               subtitle: "No true silent watchers yet.",
                               score: 0)
        }

        let subtitle = "\(bestName) (\(bestMsgs) msgs, \(bestGiven) reactions)"

        return PremiumStat(kind: .silentWatcher,
                           title: "Silent Watcher",
                           subtitle: subtitle,
                           score: bestScore)
    }

    // MARK: - Directed edges A -> B for 😂 (wrapper kept for compatibility)

    static func laughedDirectedEdges(
        chatRowId: Int64,
        minCount: Int,
        reactionScanLimit: Int,
        messageScanLimit: Int
    ) throws -> [DirectedEdge] {
        let guidToSender = try buildGuidToSenderMap(chatRowId: chatRowId, messageScanLimit: messageScanLimit)
        return try laughedDirectedEdgesFromMap(
            chatRowId: chatRowId,
            guidToSender: guidToSender,
            minCount: minCount,
            reactionScanLimit: reactionScanLimit
        )
    }

    // MARK: - Internal: laughed edges using existing guid->sender map

    private static func laughedDirectedEdgesFromMap(
        chatRowId: Int64,
        guidToSender: [String: String],
        minCount: Int,
        reactionScanLimit: Int
    ) throws -> [DirectedEdge] {

        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        let sql = """
        SELECT
          r.associated_message_guid,
          r.is_from_me,
          COALESCE(h.id, 'Unknown') AS reactor_handle
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        LEFT JOIN handle h ON h.ROWID = r.handle_id
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
          AND r.associated_message_type = ?
        ORDER BY r.date DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 9202, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(ReactionKind.laughed.rawValue))
        sqlite3_bind_int(stmt, 3, Int32(reactionScanLimit))

        var counts: [String: [String: Int]] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let assoc = text(stmt, 0) else { continue }

            let isFromMe = sqlite3_column_int(stmt, 1) == 1
            let reactorRaw = isFromMe ? "Me" : (text(stmt, 2) ?? "Unknown")
            let reactor = resolveName(reactorRaw)

            var receiver: String? = nil
            for k in canonicalGuidKeys(assoc) {
                if let found = guidToSender[k] {
                    receiver = found
                    break
                }
            }
            guard let receiver else { continue }

            var inner = counts[reactor] ?? [:]
            inner[receiver, default: 0] += 1
            counts[reactor] = inner
        }

        var edges: [DirectedEdge] = []
        for (from, inner) in counts {
            for (to, c) in inner where c >= minCount {
                edges.append(DirectedEdge(fromName: from, toName: to, count: c))
            }
        }

        return edges
    }

    // MARK: - NEW: scan all reaction kinds once to get aggregates

    private static func reactionAggregatesFromMap(
        chatRowId: Int64,
        guidToSender: [String: String],
        reactionScanLimit: Int
    ) throws -> ReactionAggregates {

        let db = try openDB()
        defer { if db != nil { sqlite3_close(db) } }

        // Build IN (...) list of associated_message_type values for reaction kinds.
        let kindList = allKinds.map { String(Int($0.rawValue)) }.joined(separator: ",")

        let sql = """
        SELECT
          r.associated_message_guid,
          r.associated_message_type,
          r.is_from_me,
          COALESCE(h.id, 'Unknown') AS reactor_handle
        FROM message r
        JOIN chat_message_join cmj ON cmj.message_id = r.ROWID
        LEFT JOIN handle h ON h.ROWID = r.handle_id
        WHERE cmj.chat_id = ?
          AND r.associated_message_guid IS NOT NULL
          AND r.associated_message_type IN (\(kindList))
        ORDER BY r.date DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 9210, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatRowId)
        sqlite3_bind_int(stmt, 2, Int32(reactionScanLimit))

        var aggs = ReactionAggregates()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let assoc = text(stmt, 0) else { continue }
            let type = Int(sqlite3_column_int(stmt, 1))
            guard let kind = ReactionKind(rawValue: type) else { continue }

            let isFromMe = sqlite3_column_int(stmt, 2) == 1
            let reactorRaw = isFromMe ? "Me" : (text(stmt, 3) ?? "Unknown")
            let reactor = resolveName(reactorRaw)

            var receiver: String? = nil
            for k in canonicalGuidKeys(assoc) {
                if let found = guidToSender[k] {
                    receiver = found
                    break
                }
            }
            guard let receiver else { continue }

            aggs.totalReactions += 1
            aggs.totalByKind[kind, default: 0] += 1

            aggs.givenByPerson[reactor, default: 0] += 1
            aggs.receivedByPerson[receiver, default: 0] += 1

            var inner = aggs.givenByPersonByKind[reactor] ?? [:]
            inner[kind, default: 0] += 1
            aggs.givenByPersonByKind[reactor] = inner
        }

        return aggs
    }

    // MARK: - DB helpers

    private static func openDB() throws -> OpaquePointer? {
        let dbPath = MessagesDBHealth.chatDBURL().path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            defer { if db != nil { sqlite3_close(db) } }
            let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            throw NSError(domain: "ReactStatLite", code: 9200, userInfo: [NSLocalizedDescriptionKey: msg])
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
            throw NSError(domain: "ReactStatLite", code: 9203, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
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
}
