// ChatDetailView.swift
import SwiftUI
import Contacts
import AppKit

struct ChatDetailView: View {
    let chat: ChatThread

    @State private var loadingSummary = true
    @State private var loadingGiven = true
    @State private var loadingReceived = true
    @State private var error: String?

    @State private var totalReactions: Int = 0
    @State private var totalMessages: Int = 0

    @State private var messageShare: [ShareRow] = []
    @State private var givenRatiosByKind: [ReactionKind: [RatioRow]] = [:]
    @State private var receivedRatiosByKind: [ReactionKind: [RatioRow]] = [:]

    @State private var premiumStats: [PremiumStat] = []
    @State private var loadingPremium = false

    @State private var showingShare = false

    @State private var contactsStatus: CNAuthorizationStatus =
        CNContactStore.authorizationStatus(for: .contacts)

    // Global “don’t nag me” cooldown (shared across app)
    // IMPORTANT FIX: we will clear this automatically if Contacts is not authorized,
    // so tccutil reset makes the banner show again.
    @AppStorage("contactsNudgeDismissedUntilEpoch") private var contactsNudgeDismissedUntilEpoch: Double = 0
    private var now: Double { Date().timeIntervalSince1970 }
    private var contactsNudgeGloballyDismissed: Bool { contactsNudgeDismissedUntilEpoch > now }

    private let kindsToShow: [ReactionKind] = [.laughed, .liked, .loved, .emphasized, .questioned, .disliked]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if shouldShowContactsNudge {
                    ContactsNudgeBanner(
                        onOpenContactsSettings: { openContactsPrivacySettingsForce() },
                        onRequestContacts: { requestContacts() },
                        onNotNow: {
                            // dismiss for 7 days (your original behavior)
                            contactsNudgeDismissedUntilEpoch = now + (7 * 24 * 60 * 60)
                        }
                    )
                }

                if loadingSummary {
                    ProgressView("Loading summary…")
                        .padding(.vertical, 6)
                }

                if let error {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    StatCard(title: "Total messages", value: totalMessages.formatted())

                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Share")
                    .disabled(loadingSummary)

                    StatCard(title: "Total reactions", value: totalReactions.formatted())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Message dynamics") {
                    if messageShare.isEmpty {
                        Text("No data yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Main character (share of messages)")
                                .font(.headline)

                            ForEach(messageShare) { row in
                                HStack {
                                    Text(row.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text("\(Int((row.share * 100).rounded()))%")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)

                                Text("\(row.messages) msgs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Advanced (adjusted for message volume)") {
                    if loadingPremium {
                        PremiumLoadingCard()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else if premiumStats.isEmpty {
                        Text("Not enough data yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(premiumStats) { stat in
                                PremiumStatRowView(stat: stat)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    LoadingPill(title: "Given", isLoading: loadingGiven)
                    LoadingPill(title: "Received", isLoading: loadingReceived)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(kindsToShow) { kind in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(kind.emoji)
                                    .font(.title3)
                                Text(kind.title)
                                    .font(.headline)
                                Spacer()
                            }

                            RatioList(
                                title: "\(kind.emoji) Given per message",
                                rows: givenRatiosByKind[kind] ?? []
                            )

                            Divider().opacity(0.35)

                            RatioList(
                                title: "\(kind.emoji) Received per message",
                                rows: receivedRatiosByKind[kind] ?? []
                            )
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Removed: internal chatIdentifier debug line
                // (Users never need this)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("ReactStat")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")
                .disabled(loadingSummary)
            }

            // ✅ Always available way to fix Contacts (brings back what you had)
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    handleContactsToolbarAction()
                } label: {
                    Image(systemName: "person.text.rectangle")
                }
                .help(contactsStatus == .authorized ? "Contacts enabled" : "Enable Contacts")
                .disabled(contactsStatus == .authorized)
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(payload: SharePackPayload(
                chatTitle: chat.title,
                totalMessages: totalMessages,
                totalReactions: totalReactions,
                messageShare: messageShare,
                givenRatiosByKind: givenRatiosByKind,
                receivedRatiosByKind: receivedRatiosByKind,
                premiumStats: premiumStats,
                advancedStatsLoaded: !loadingPremium
            ))
        }
        .task {
            refreshContactsStatus()
            await loadIncremental()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshContactsStatus()
        }
    }

    private var shouldShowContactsNudge: Bool {
        // show banner when not authorized AND not dismissed
        !contactsNudgeGloballyDismissed && contactsStatus != .authorized
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chat.title)
                .font(.title.bold())
            Text("Chat ROWID: \(chat.id)")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Contacts handling

    private func refreshContactsStatus() {
        let newStatus = CNContactStore.authorizationStatus(for: .contacts)
        contactsStatus = newStatus

        // ✅ Critical fix for tccutil reset: if Contacts is not authorized,
        // clear any old "Not now" dismissal so the banner shows again.
        if newStatus != .authorized {
            contactsNudgeDismissedUntilEpoch = 0
        }
    }

    private func handleContactsToolbarAction() {
        switch contactsStatus {
        case .notDetermined:
            requestContacts()
        case .denied, .restricted:
            openContactsPrivacySettingsForce()
        case .authorized:
            break
        @unknown default:
            openContactsPrivacySettingsForce()
        }
    }

    private func requestContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async {
                refreshContactsStatus()
            }
        }
    }

    /// Deep link to Privacy & Security → Contacts.
    /// If System Settings is already open, it can ignore pane changes.
    /// We force-terminate it first, then open the deep link.
    private func openContactsPrivacySettingsForce() {
        let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!

        // Force quit System Settings so the deep link reliably navigates.
        let bundleID = "com.apple.systempreferences"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running {
            app.terminate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(deepLink, configuration: config)
        }
    }

    // MARK: - Data loading (unchanged)

    @MainActor
    private func loadIncremental() async {
        error = nil

        loadingSummary = true
        loadingGiven = true
        loadingReceived = true
        loadingPremium = true

        totalMessages = 0
        totalReactions = 0
        messageShare = []
        givenRatiosByKind = [:]
        receivedRatiosByKind = [:]
        premiumStats = []

        Task.detached(priority: .utility) {
            ContactNameCache.shared.warmIfNeeded()
        }

        do {
            let summary = try await Task.detached(priority: .userInitiated) { () throws -> (Int, Int, [ShareRow]) in
                let totalMessages = try ReactionStatsRepository.totalMessagesInChat(chatRowId: chat.id)
                let totalReactions = try ReactionStatsRepository.totalReactionsInChat(chatRowId: chat.id)

                let share = try ReactionStatsRepository.messageShareLeaderboard(
                    chatRowId: chat.id,
                    limit: 50,
                    minMessages: 5
                )

                return (totalMessages, totalReactions, share)
            }.value

            totalMessages = summary.0
            totalReactions = summary.1
            messageShare = summary.2
            loadingSummary = false
        } catch {
            self.error = error.localizedDescription
            loadingSummary = false
            loadingGiven = false
            loadingReceived = false
            loadingPremium = false
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                let given = try ReactionStatsRepository.givenPerMessageLeaderboardsAllKinds(
                    chatRowId: chat.id,
                    kinds: kindsToShow,
                    limit: 10,
                    minMessages: 30
                )
                await MainActor.run {
                    self.givenRatiosByKind = given
                    self.loadingGiven = false
                }
            } catch {
                await MainActor.run { self.loadingGiven = false }
            }
        }

        Task.detached(priority: .userInitiated) {
            do {
                let received = try ReactionStatsRepository.receivedPerMessageLeaderboardsAllKinds(
                    chatRowId: chat.id,
                    kinds: kindsToShow,
                    limit: 10,
                    minMessages: 30,
                    reactionScanLimit: 50_000,
                    messageScanLimit: 50_000
                )
                await MainActor.run {
                    self.receivedRatiosByKind = received
                    self.loadingReceived = false
                }
            } catch {
                await MainActor.run { self.loadingReceived = false }
            }
        }

        Task.detached(priority: .userInitiated) {
            do {
                let stats = try PremiumStatsRepository.premiumStats(chatRowId: chat.id)
                await MainActor.run {
                    self.premiumStats = stats
                    self.loadingPremium = false
                }
            } catch {
                await MainActor.run { self.loadingPremium = false }
            }
        }
    }
}

// MARK: - “Advanced” Stat Row (clean UI)

private struct PremiumStatRowView: View {
    let stat: PremiumStat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stat.title)
                .font(.headline)

            let parts = ParsedPremiumSubtitle.parse(stat.subtitle)

            if let line1 = parts.line1 {
                Text(line1)
                    .foregroundStyle(.secondary)
            }

            if let line2 = parts.line2 {
                Text(line2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

private enum ParsedPremiumSubtitle {
    struct Parts {
        let line1: String?
        let line2: String?
    }

    static func parse(_ s: String) -> Parts {
        let comps = s.components(separatedBy: ", adj ")
        if comps.count == 2 {
            return Parts(line1: comps[0], line2: "Adj: \(comps[1])")
        }
        return Parts(line1: s, line2: nil)
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(2)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LoadingPill: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }
}

private struct RatioList: View {
    let title: String
    let rows: [RatioRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if rows.isEmpty {
                Text("No data yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(rows) { row in
                    VStack(spacing: 4) {
                        HStack {
                            Text(row.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.2f", row.ratio))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack(spacing: 6) {
                            Text("\(row.numerator) \(row.numeratorLabel)")
                            Text("•")
                            Text("\(row.denominator) \(row.denominatorLabel)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct PremiumLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text("Loading advanced…")
                    .font(.headline)

                Text("Crunching the spicy stats")
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
