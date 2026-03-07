import Foundation

struct ChatThread: Identifiable, Hashable {
    let id: Int64
    let chatIdentifier: String
    let displayName: String?
    let messageCount: Int
    let participantCount: Int

    /// Raw participant handles (phone/email). Used for fallback title when displayName is empty.
    let participantHandles: [String]

    /// Precomputed normalized search blob (order-independent token search uses this)
    let searchIndex: String

    init(
        id: Int64,
        chatIdentifier: String,
        displayName: String?,
        messageCount: Int,
        participantCount: Int,
        participantHandles: [String]
    ) {
        self.id = id
        self.chatIdentifier = chatIdentifier
        self.displayName = displayName
        self.messageCount = messageCount
        self.participantCount = participantCount
        self.participantHandles = participantHandles

        // Build a stable search index once.
        // Include: display name, computed title fallback (resolved names), raw handles, chatIdentifier.
        let rawDisplayName = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dn = Self.isMeaningfulDisplayName(rawDisplayName) ? rawDisplayName : ""

        let resolvedNames = participantHandles
            .map { ContactNameCache.shared.resolve($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Unknown" }

        let fallbackTitle: String = {
            if !dn.isEmpty { return dn }
            if resolvedNames.isEmpty { return "Chat" }
            if resolvedNames.count <= 4 { return resolvedNames.joined(separator: ", ") }
            let head = resolvedNames.prefix(4).joined(separator: ", ")
            return "\(head), +\(resolvedNames.count - 4)"
        }()

        let blob = [
            dn,
            fallbackTitle,
            chatIdentifier,
            participantHandles.joined(separator: " "),
            resolvedNames.joined(separator: " ")
        ]
        .joined(separator: " | ")

        self.searchIndex = Self.normalize(blob)
    }

    var title: String {
        let rawDisplayName = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dn = Self.isMeaningfulDisplayName(rawDisplayName) ? rawDisplayName : ""
        if !dn.isEmpty { return dn }

        // Resolve to contact names when possible; otherwise keep raw handle.
        let resolved = participantHandles
            .map { ContactNameCache.shared.resolve($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Unknown" }

        if resolved.isEmpty { return "Chat" }

        // Keep it readable in the sidebar/list.
        if resolved.count <= 4 {
            return resolved.joined(separator: ", ")
        } else {
            let head = resolved.prefix(4).joined(separator: ", ")
            return "\(head), +\(resolved.count - 4)"
        }
    }

    // MARK: - Normalize (must match ChatRepository’s approach)

    private static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let lowered = folded.lowercased()

        let cleaned = lowered.replacingOccurrences(
            of: #"[^a-z0-9\s,]"#,
            with: " ",
            options: .regularExpression
        )

        let collapsed = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMeaningfulDisplayName(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        if hasLetters { return true }

        let hasDigits = trimmed.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
        // If it has digits but no letters, it's usually a phone-number list like "+1555…, +1444…".
        // In that case we prefer falling back to resolved participant handles.
        return !hasDigits
    }

    // Hash/eq by id only (stable, avoids hashability issues if arrays change)
    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
