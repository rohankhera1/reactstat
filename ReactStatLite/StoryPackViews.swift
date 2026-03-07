import SwiftUI

// MARK: - Shared styling

private enum ShareStyle {
    static let accent = Color.blue
    static let premiumGold = Color(red: 0.83, green: 0.67, blue: 0.22)

    // Softer tints (optional, but useful for tiny highlights)
    static let accentSoft = Color.blue.opacity(0.18)
    static let goldSoft = Color(red: 0.83, green: 0.67, blue: 0.22).opacity(0.22)

    static let background = Color.white
    static let cardFill = Color.black.opacity(0.04)

    // Slightly stronger stroke so it pops without gimmicks
    static let cardStroke = Color.blue.opacity(0.14)

    static let primaryText = Color.black.opacity(0.90)
    static let secondaryText = Color.black.opacity(0.60)

    static let cardCorner: CGFloat = 26

    // Leaderboard layout constants (keep name position stable)
    static let rankWidth: CGFloat = 36
    static let rankToNameSpacing: CGFloat = 12

    // Subtitle indent: should line up with the *start of the name*
    static let subtitleNudge: CGFloat = 0
    static var subtitleIndent: CGFloat { rankWidth + rankToNameSpacing + subtitleNudge }

    // Brand badge (subtle, doesn’t block stats)
    static let brandOpacity: CGFloat = 0.18
}

// MARK: - Brand badge overlay (bottom-right)

private struct BrandBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("ReactStat")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(ShareStyle.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.78))
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(ShareStyle.accent.opacity(0.25), lineWidth: 1)
        )
        .opacity(ShareStyle.brandOpacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Cover page (1080x1920)

struct StoryCoverPageView: View {
    let chatTitle: String
    let totalMessages: Int
    let totalReactions: Int
    let mainCharacter: ShareRow?
    var messageShare: [ShareRow] = []

    var body: some View {
        ZStack {
            ShareStyle.background

            VStack(alignment: .leading, spacing: 22) {
                header

                Text(chatTitle)
                    .font(.system(size: 68, weight: .bold))
                    .foregroundStyle(ShareStyle.primaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 18) {
                    bigMetric(title: "Messages", value: totalMessages.formatted())
                    bigMetric(title: "Reactions", value: totalReactions.formatted())
                }

                mainCharactersCard

                Spacer(minLength: 0)

                Text("Swipe → for reaction rankings")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ShareStyle.secondaryText)

                Text("Made with ReactStat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ShareStyle.accent)
            }
            .padding(64)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    BrandBadge()
                        .padding(.trailing, 28)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(ShareStyle.accent)
                    .font(.system(size: 26, weight: .bold))

                Text("ReactStat")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(ShareStyle.accent)
            }

            Spacer()

            Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ShareStyle.secondaryText)
        }
    }

    private var mainCharactersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Main Characters")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ShareStyle.primaryText)

            // ✅ Only show people with >= 1% share, then cap at 10
            let filtered = messageShare
                .filter { $0.share >= 0.01 }
                .prefix(10)

            if filtered.isEmpty {
                Text("Not enough data yet")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ShareStyle.secondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(filtered)) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(r.name)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(ShareStyle.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Text("\(Int((r.share * 100).rounded()))%")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(ShareStyle.accent)
                                    .monospacedDigit()
                            }

                            Text("\(r.messages) messages")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(ShareStyle.secondaryText)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(20)
        .background(ShareStyle.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: ShareStyle.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShareStyle.cardCorner, style: .continuous)
                .strokeBorder(ShareStyle.cardStroke, lineWidth: 1)
        )
    }

    private func bigMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(ShareStyle.secondaryText)

            Text(value)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(ShareStyle.primaryText)
                .monospacedDigit()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShareStyle.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: ShareStyle.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShareStyle.cardCorner, style: .continuous)
                .strokeBorder(ShareStyle.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Reaction page (1080x1920)

struct StoryReactionPageView: View {
    let kind: ReactionKind
    let chatTitle: String
    let given: [RatioRow]
    let received: [RatioRow]

    var body: some View {
        ZStack {
            ShareStyle.background

            VStack(alignment: .leading, spacing: 18) {
                header

                rankingsCard(
                    title: "\(kind.emoji) Given per message",
                    rows: given
                )

                rankingsCard(
                    title: "\(kind.emoji) Received per message",
                    rows: received
                )

                Spacer(minLength: 0)

                Text("Made with ReactStat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ShareStyle.accent)
            }
            .padding(60)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    BrandBadge()
                        .padding(.trailing, 28)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kind.emoji)
                .font(.system(size: 58, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text(kind.title)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(ShareStyle.primaryText)

                Text(chatTitle)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ShareStyle.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("ReactStat")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ShareStyle.accent)
        }
    }

    private func rankingsCard(title: String, rows: [RatioRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(ShareStyle.primaryText)

            if rows.isEmpty {
                Text("No data yet")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(ShareStyle.secondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { idx, row in
                        leaderboardRow(idx: idx, row: row)
                    }
                }
            }
        }
        .padding(20)
        .background(ShareStyle.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: ShareStyle.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShareStyle.cardCorner, style: .continuous)
                .strokeBorder(ShareStyle.cardStroke, lineWidth: 1)
        )
    }

    private func leaderboardRow(idx: Int, row: RatioRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack(alignment: .firstTextBaseline, spacing: ShareStyle.rankToNameSpacing) {
                Text("\(idx + 1).")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ShareStyle.secondaryText)
                    .frame(width: ShareStyle.rankWidth, alignment: .leading)

                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 26, weight: idx == 0 ? .bold : .semibold))
                        .foregroundStyle(ShareStyle.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if idx == 0 {
                        Text("👑")
                            .font(.system(size: 18))
                            .offset(y: -1)
                            .shadow(color: ShareStyle.goldSoft, radius: 6)
                    }
                }

                Spacer()

                Text(String(format: "%.2f", row.ratio))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(idx == 0 ? ShareStyle.accent : ShareStyle.secondaryText)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Text("\(row.numerator) \(row.numeratorLabel)")
                Text("•")
                Text("\(row.denominator) \(row.denominatorLabel)")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(ShareStyle.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, ShareStyle.subtitleIndent)
        }
        .padding(.vertical, 2)
    }
}
