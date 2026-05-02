import SwiftUI

// MARK: - Section (used inside ChatDetailView)

struct PersonalityProfilesSection: View {
    let profiles: [PersonalityProfile]
    let isLoading: Bool
    var error: String? = nil
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""

    var body: some View {
        GroupBox("Personality Profiles") {
            if apiKey.isEmpty {
                APIKeySetupCard()
                    .padding(.vertical, 6)
            } else if isLoading {
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
                    Button("Clear API key and re-enter") { apiKey = "" }
                        .font(.caption)
                        .buttonStyle(.bordered)
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

// MARK: - API key setup card

struct APIKeySetupCard: View {
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @State private var draft = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Personality Analysis", systemImage: "sparkles")
                .font(.headline)

            Text("Paste your Anthropic API key to generate unique, AI-written personality profiles for everyone in the chat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SecureField("sk-ant-…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit { save() }

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Link("Get a free API key at console.anthropic.com",
                 destination: URL(string: "https://console.anthropic.com")!)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKey = trimmed
        draft = ""
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

// MARK: - Cross-chat "Your Profile" sheet

struct YourPersonalitySheet: View {
    let profile: PersonalityProfile?
    let isLoading: Bool
    let error: String?
    let onRegenerate: () -> Void
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Personality Profile")
                    .font(.title.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Built from your messages across all chats.")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            if apiKey.isEmpty {
                APIKeySetupCard()
            } else if isLoading {
                PersonalityLoadingCard()
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
                    Button("Clear API key and re-enter") { apiKey = "" }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            } else if let profile {
                PersonalityCardView(profile: profile)
                Button("Regenerate") { onRegenerate() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            } else {
                Text("Not enough messages found to build a profile.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 380, minHeight: 420)
    }
}
