import SwiftUI

// MARK: - Section (used inside ChatDetailView)

struct PersonalityProfilesSection: View {
    let profiles: [PersonalityProfile]
    let isLoading: Bool
    var error: String? = nil

    var body: some View {
        GroupBox("Personality Profiles") {
            if isLoading {
                PersonalityLoadingCard()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Generation failed", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            } else if profiles.isEmpty {
                Text("Not enough messages to build profiles yet. (Need at least 5 messages per person.)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(profiles) { profile in
                        PersonalityCardView(profile: profile)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Individual card

struct PersonalityCardView: View {
    let profile: PersonalityProfile
    @State private var showBars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name + message count
            HStack(alignment: .firstTextBaseline) {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                Text("\(profile.messageCount) msgs")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // AI-generated descriptor — the main event
            Text(profile.descriptor)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Expandable trait bars
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showBars.toggle() }
            } label: {
                Label(showBars ? "Hide signals" : "Show signals",
                      systemImage: showBars ? "chevron.up" : "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showBars {
                VStack(spacing: 5) {
                    TraitBar(label: "Warmth",         value: profile.warmth,         color: .orange)
                    TraitBar(label: "Expressiveness", value: profile.expressiveness, color: .pink)
                    TraitBar(label: "Verbosity",      value: profile.verbosity,      color: .blue)
                    TraitBar(label: "Curiosity",      value: profile.curiosity,      color: .purple)
                    TraitBar(label: "Enthusiasm",     value: profile.enthusiasm,     color: .yellow)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Trait bar

private struct TraitBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * min(1.0, max(0.0, value)))
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: - Loading card

struct PersonalityLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text("Writing personality profiles…")
                    .font(.headline)
                Text("Claude is reading the chat history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Cross-chat "Your Life Analysis" sheet

struct YourPersonalitySheet: View {
    let analysis: LifeAnalysis?
    let isLoading: Bool
    let error: String?
    let onRegenerate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Life Analysis")
                            .font(.title.bold())
                        if let analysis {
                            Text("\(analysis.messageCount) messages · \(analysis.dateRange)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Built from your messages across all chats and DMs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isLoading {
                    LifeAnalysisLoadingCard()
                } else if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Generation failed", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let analysis {
                    LifeSectionCard(
                        icon: "person.fill",
                        title: "Who You Are",
                        color: .blue,
                        archetype: analysis.archetype,
                        content: analysis.personality
                    )

                    LifeSectionCard(
                        icon: "calendar",
                        title: "Your Story So Far",
                        color: .purple,
                        content: analysis.timeline
                    )

                    LifeSectionCard(
                        icon: "sparkles",
                        title: "Where You're Headed",
                        color: .orange,
                        content: analysis.foresight
                    )

                    LifeTraitBars(analysis: analysis)

                    Button("Regenerate") { onRegenerate() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                } else {
                    Text("Not enough messages found to build an analysis.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 700, maxWidth: 900, minHeight: 680, idealHeight: 820, maxHeight: .infinity)
    }
}

// MARK: - Section card

private struct LifeSectionCard: View {
    let icon: String
    let title: String
    let color: Color
    var archetype: String = ""
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            if !archetype.isEmpty {
                Text(archetype)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Trait bars for life analysis

private struct LifeTraitBars: View {
    let analysis: LifeAnalysis
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Label(expanded ? "Hide signals" : "Show underlying signals",
                      systemImage: expanded ? "chevron.up" : "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 5) {
                    TraitBar(label: "Warmth",         value: analysis.warmth,         color: .orange)
                    TraitBar(label: "Expressiveness", value: analysis.expressiveness, color: .pink)
                    TraitBar(label: "Verbosity",      value: analysis.verbosity,      color: .blue)
                    TraitBar(label: "Curiosity",      value: analysis.curiosity,      color: .purple)
                    TraitBar(label: "Enthusiasm",     value: analysis.enthusiasm,     color: .yellow)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Life analysis loading card

struct LifeAnalysisLoadingCard: View {
    @State private var elapsed: Int = 0

    // Approximate which stage we're in based on elapsed time.
    private var stageText: String {
        switch elapsed {
        case 0..<3:  return "Reading your full message history…"
        case 3..<7:  return "Grouping messages by time period…"
        default:     return "Claude Sonnet is writing your analysis…"
        }
    }

    // Count down from an estimated 120-second Sonnet call that starts around 7s in.
    private var timeRemainingText: String {
        guard elapsed >= 7 else { return "" }
        let claudeElapsed = elapsed - 7
        let remaining = 120 - claudeElapsed
        if remaining > 0 { return "~\(remaining)s remaining" }
        return "finishing up…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.large)
                VStack(alignment: .leading, spacing: 5) {
                    Text(stageText)
                        .font(.headline)
                        .animation(.default, value: stageText)
                    HStack(spacing: 8) {
                        Text("\(elapsed)s elapsed")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        if !timeRemainingText.isEmpty {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                            Text(timeRemainingText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
            }
        }
    }
}
