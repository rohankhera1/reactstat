import Foundation

enum ReactionType: String, CaseIterable {
    case laugh = "Haha"
    case love = "Love"
    case like = "Like"
    case dislike = "Dislike"
    case emphasize = "Emphasize"
    case question = "Question"
}

struct ReactionStat: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}
