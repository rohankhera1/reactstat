import Foundation
import SQLite3

@MainActor
final class ChatRepository: ObservableObject {
    @Published var allChats: [ChatThread] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var searchText: String = ""

    /// Group-only view + smarter search (names separated by commas/spaces; any order)
    var filteredChats: [ChatThread] {
        let base = allChats.filter { $0.participantCount >= 3 } // ✅ real group detection

        let tokens = Self.queryTokens(searchText)
        guard !tokens.isEmpty else { return base }

        return base.filter { chat in
            // AND semantics: all tokens must appear somewhere
            tokens.allSatisfy { chat.searchIndex.contains($0) }
        }
    }

    func loadChats(limit: Int = 800) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let chats = try await Task.detached(priority: .userInitiated) { () throws -> [ChatThread] in
                try Self.fetchChats(limit: limit)
            }.value

            self.allChats = chats
            self.errorMessage = nil
        } catch {
            self.allChats = []
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Search helpers

    private static func normalize(_ s: String) -> String {
        // Lowercase + remove diacritics + keep alphanumerics, commas, spaces
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let lowered = folded.lowercased()

        // Replace anything not [a-z0-9 space comma] with space
        let cleaned = lowered.replacingOccurrences(
            of: #"[^a-z0-9\s,]"#,
            with: " ",
            options: .regularExpression
        )

        // Collapse whitespace
        let collapsed = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func queryTokens(_ q: String) -> [String] {
        let n = normalize(q)
        // Split on commas OR whitespace; ignore empties
        return n.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - DB

    static nonisolated func fetchChats(limit: Int) throws -> [ChatThread] {
        let path = MessagesDBHealth.chatDBURL().path

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            defer { if db != nil { sqlite3_close(db) } }
            let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            throw NSError(domain: "ReactStatLite", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)

        func colText(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }

        // Pull chats + message count + participant count
        let chatsSQL = """
        SELECT
          c.ROWID AS id,
          c.chat_identifier,
          c.display_name,
          (SELECT COUNT(*) FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID) AS msg_count,
          (SELECT COUNT(*) FROM chat_handle_join chj WHERE chj.chat_id = c.ROWID) AS participant_count
        FROM chat c
        WHERE EXISTS (SELECT 1 FROM chat_message_join cmj2 WHERE cmj2.chat_id = c.ROWID)
        ORDER BY msg_count DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, chatsSQL, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ReactStatLite", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        // Dedupe: keep the chat with highest msg_count per chat_identifier
        var bestByIdentifier: [String: (id: Int64, chatIdentifier: String, displayName: String?, msgCount: Int, participantCount: Int)] = [:]
        bestByIdentifier.reserveCapacity(limit)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let chatIdentifier = colText(stmt, 1) ?? ""
            let displayName = colText(stmt, 2)
            let msgCount = Int(sqlite3_column_int(stmt, 3))
            let participantCount = Int(sqlite3_column_int(stmt, 4))

            if let existing = bestByIdentifier[chatIdentifier] {
                if msgCount > existing.msgCount {
                    bestByIdentifier[chatIdentifier] = (id, chatIdentifier, displayName, msgCount, participantCount)
                }
            } else {
                bestByIdentifier[chatIdentifier] = (id, chatIdentifier, displayName, msgCount, participantCount)
            }
        }

        let selectedChatIDs = bestByIdentifier.values.map { $0.id }

        // Fetch participant handles for all selected chats in one query
        let handlesByChatID = try fetchParticipantHandlesByChatID(db: db, chatIDs: selectedChatIDs)

        // Build ChatThread objects
        var out: [ChatThread] = []
        out.reserveCapacity(bestByIdentifier.count)

        for v in bestByIdentifier.values {
            let handles = handlesByChatID[v.id] ?? []
            out.append(ChatThread(
                id: v.id,
                chatIdentifier: v.chatIdentifier,
                displayName: v.displayName,
                messageCount: v.msgCount,
                participantCount: v.participantCount,
                participantHandles: handles
            ))
        }

        // Sort by most messages first, tie-break by title
        out.sort {
            if $0.messageCount != $1.messageCount {
                return $0.messageCount > $1.messageCount
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        return out
    }

    /// Returns map: chat_id -> [handle.id]
    private static nonisolated func fetchParticipantHandlesByChatID(db: OpaquePointer?, chatIDs: [Int64]) throws -> [Int64: [String]] {
        guard !chatIDs.isEmpty else { return [:] }

        func colText(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }

        let placeholders = Array(repeating: "?", count: chatIDs.count).joined(separator: ",")

        let sql = """
        SELECT
          chj.chat_id,
          COALESCE(h.id, 'Unknown') AS handle_id
        FROM chat_handle_join chj
        JOIN handle h ON h.ROWID = chj.handle_id
        WHERE chj.chat_id IN (\(placeholders))
        ORDER BY chj.chat_id;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "ReactStatLite", code: 3, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
        }
        defer { sqlite3_finalize(stmt) }

        for (idx, id) in chatIDs.enumerated() {
            sqlite3_bind_int64(stmt, Int32(idx + 1), id)
        }

        var out: [Int64: [String]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chatID = sqlite3_column_int64(stmt, 0)
            let raw = colText(stmt, 1) ?? "Unknown"
            out[chatID, default: []].append(raw)
        }

        // Dedupe within each chat
        for (k, arr) in out {
            var seen = Set<String>()
            out[k] = arr.filter { seen.insert($0).inserted }
        }

        return out
    }
}
