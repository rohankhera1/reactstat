import Foundation

struct PremiumStat: Identifiable {
    enum Kind {
        case biggestGlazer
        case biggestMutualGlazer
        case reactionKing
        case mostIgnored
        case reactionPersonality
        case silentWatcher
    }


    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let score: Double
}
