import Foundation

struct LifeAnalysis {
    let archetype: String
    let personality: String
    let timeline: String
    let foresight: String
    let patterns: String
    let messageCount: Int
    let dateRange: String
    let warmth: Double
    let expressiveness: Double
    let verbosity: Double
    let curiosity: Double
    let enthusiasm: Double
    let lexicalRichness: Double
    let relationships: [RelationshipAnalysis]
}

struct RelationshipAnalysis {
    let contactName: String
    let userSent: Int
    let contactSent: Int
    let userAvgWords: Double
    let contactAvgWords: Double
    let userInitiationPct: Double   // 0.0 – 1.0
    let dateRange: String
    let dynamic: String             // Claude-generated
    let investment: String          // Claude-generated, 1 sentence
}

struct TimePeriod {
    let label: String
    let samples: [String]
}

struct ContactSummary {
    let name: String
    let messageCount: Int
    let dmMessageCount: Int
    let firstSeen: String
    let lastSeen: String
    let sharedGroupChats: Int
}
