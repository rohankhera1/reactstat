import Foundation

struct LifeAnalysis {
    let archetype: String
    let personality: String
    let timeline: String
    let foresight: String
    let messageCount: Int
    let dateRange: String
    let warmth: Double
    let expressiveness: Double
    let verbosity: Double
    let curiosity: Double
    let enthusiasm: Double
    let lexicalRichness: Double
}

struct TimePeriod {
    let label: String
    let samples: [String]
}

struct ContactSummary {
    let name: String
    let messageCount: Int     // total (DM + group)
    let dmMessageCount: Int   // 1:1 messages only — strongest closeness signal
    let firstSeen: String     // e.g. "Q3 2021"
    let lastSeen: String      // e.g. "Q1 2024" or "present"
    let sharedGroupChats: Int
}
