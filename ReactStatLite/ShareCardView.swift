import SwiftUI

struct ShareCardModel {
    let chatTitle: String
    let totalMessages: Int
    let totalReactions: Int

    /// (name, share 0..1, messages)
    let mainCharacter: (String, Double, Int)?

    /// (name, ratio, numerator, denominator)
    let topHahaGiven: (String, Double, Int, Int)?
    let topHahaReceived: (String, Double, Int, Int)?
}

struct ShareCardView: View {
    let model: ShareCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ReactStat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(model.chatTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                }
                Spacer()
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                metricCard("Messages", model.totalMessages.formatted())
                metricCard("Reactions", model.totalReactions.formatted())
            }

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 10) {
                Text("Highlights")
                    .font(.headline)

                if let mc = model.mainCharacter {
                    highlightRow(
                        title: "Main character",
                        value: "\(Int((mc.1 * 100).rounded()))%",
                        subtitle: "\(mc.0) • \(mc.2) msgs"
                    )
                } else {
                    highlightRow(title: "Main character", value: "—", subtitle: "Not enough data")
                }

                if let top = model.topHahaReceived {
                    highlightRow(
                        title: "😂 received / msg",
                        value: String(format: "%.2f", top.1),
                        subtitle: "\(top.0) • \(top.2) received • \(top.3) msgs"
                    )
                } else {
                    highlightRow(title: "😂 received / msg", value: "—", subtitle: "Not enough data")
                }

                if let top = model.topHahaGiven {
                    highlightRow(
                        title: "😂 given / msg",
                        value: String(format: "%.2f", top.1),
                        subtitle: "\(top.0) • \(top.2) given • \(top.3) msgs"
                    )
                } else {
                    highlightRow(title: "😂 given / msg", value: "—", subtitle: "Not enough data")
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Made with ReactStat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 520, height: 520, alignment: .topLeading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func highlightRow(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
