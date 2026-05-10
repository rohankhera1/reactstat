import Foundation

// MARK: - Codable cache models

struct CachedLifeAnalysis: Codable {
    let messageCountAtCache: Int
    let archetype: String
    let personality: String
    let timeline: String
    let foresight: String
    let patterns: String
    let dateRange: String
    let warmth, expressiveness, verbosity, curiosity, enthusiasm, lexicalRichness: Double
}

struct CachedRelationship: Codable {
    let dmCountAtCache: Int
    let contactName: String
    let userSent: Int
    let contactSent: Int
    let userAvgWords: Double
    let contactAvgWords: Double
    let userInitiationPct: Double
    let dateRange: String
    let dynamic: String
    let investment: String
}

struct CachedChatAnalysis: Codable {
    let messageCountAtCache: Int
    let profiles: [CachedProfile]
}

struct CachedProfile: Codable {
    let name: String
    let messageCount: Int
    let warmth, expressiveness, verbosity, curiosity, enthusiasm, lexicalRichness: Double
    let descriptor: String
}

// MARK: - Cache engine

enum AnalysisCache {

    private static var cacheDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ReactStatLite/cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).json")
    }

    private static func store<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url(for: key), options: .atomic)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // 5% drift or 50 messages (whichever is larger) invalidates the cache.
    private static func isStale(cached: Int, current: Int) -> Bool {
        abs(cached - current) > max(current / 20, 50)
    }

    // MARK: - Life Analysis

    static func storeLifeAnalysis(_ a: LifeAnalysis, messageCount: Int) {
        store(CachedLifeAnalysis(
            messageCountAtCache: messageCount,
            archetype: a.archetype, personality: a.personality,
            timeline: a.timeline, foresight: a.foresight, patterns: a.patterns,
            dateRange: a.dateRange,
            warmth: a.warmth, expressiveness: a.expressiveness, verbosity: a.verbosity,
            curiosity: a.curiosity, enthusiasm: a.enthusiasm, lexicalRichness: a.lexicalRichness
        ), key: "v1_life_analysis")
    }

    static func loadLifeAnalysis(currentMessageCount: Int) -> CachedLifeAnalysis? {
        guard let cached = load(CachedLifeAnalysis.self, key: "v1_life_analysis"),
              !isStale(cached: cached.messageCountAtCache, current: currentMessageCount)
        else { return nil }
        return cached
    }

    static func clearLifeAnalysis() {
        try? FileManager.default.removeItem(at: url(for: "v1_life_analysis"))
    }

    // MARK: - Relationship Analyses

    private static func relKey(_ name: String) -> String {
        let safe = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
        return "v1_rel_\(safe)"
    }

    static func storeRelationship(_ r: RelationshipAnalysis, dmCount: Int) {
        store(CachedRelationship(
            dmCountAtCache: dmCount,
            contactName: r.contactName,
            userSent: r.userSent, contactSent: r.contactSent,
            userAvgWords: r.userAvgWords, contactAvgWords: r.contactAvgWords,
            userInitiationPct: r.userInitiationPct,
            dateRange: r.dateRange,
            dynamic: r.dynamic, investment: r.investment
        ), key: relKey(r.contactName))
    }

    static func loadRelationship(name: String, currentDMCount: Int) -> RelationshipAnalysis? {
        guard let cached = load(CachedRelationship.self, key: relKey(name)),
              !isStale(cached: cached.dmCountAtCache, current: currentDMCount)
        else { return nil }
        return RelationshipAnalysis(
            contactName: cached.contactName,
            userSent: cached.userSent, contactSent: cached.contactSent,
            userAvgWords: cached.userAvgWords, contactAvgWords: cached.contactAvgWords,
            userInitiationPct: cached.userInitiationPct,
            dateRange: cached.dateRange,
            dynamic: cached.dynamic, investment: cached.investment
        )
    }

    static func clearRelationships() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("v1_rel_") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Chat Personality Profiles

    static func storeChatProfiles(_ profiles: [PersonalityProfile], chatRowId: Int64, messageCount: Int) {
        store(CachedChatAnalysis(
            messageCountAtCache: messageCount,
            profiles: profiles.map {
                CachedProfile(
                    name: $0.name, messageCount: $0.messageCount,
                    warmth: $0.warmth, expressiveness: $0.expressiveness,
                    verbosity: $0.verbosity, curiosity: $0.curiosity,
                    enthusiasm: $0.enthusiasm, lexicalRichness: $0.lexicalRichness,
                    descriptor: $0.descriptor
                )
            }
        ), key: "v1_chat_\(chatRowId)")
    }

    static func loadChatProfiles(chatRowId: Int64, currentMessageCount: Int) -> [PersonalityProfile]? {
        guard let cached = load(CachedChatAnalysis.self, key: "v1_chat_\(chatRowId)"),
              !isStale(cached: cached.messageCountAtCache, current: currentMessageCount)
        else { return nil }
        return cached.profiles.map {
            PersonalityProfile(
                name: $0.name, messageCount: $0.messageCount,
                warmth: $0.warmth, expressiveness: $0.expressiveness,
                verbosity: $0.verbosity, curiosity: $0.curiosity,
                enthusiasm: $0.enthusiasm, lexicalRichness: $0.lexicalRichness,
                descriptor: $0.descriptor
            )
        }
    }

    static func clearChatProfiles(chatRowId: Int64) {
        try? FileManager.default.removeItem(at: url(for: "v1_chat_\(chatRowId)"))
    }

    // MARK: - Clear everything

    static func clearAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        ) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}
