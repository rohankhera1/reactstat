import SwiftUI
import Contacts
import AppKit

struct ContentView: View {
    @State private var hasMessagesAccess: Bool = MessagesDBHealth.hasAccess()
    @State private var chats: [ChatThread] = []
    @State private var isLoadingChats = false
    @State private var chatLoadError: String?

    @State private var contactsRevision: Int = 0

    @State private var contactsStatus: CNAuthorizationStatus =
        CNContactStore.authorizationStatus(for: .contacts)

    @AppStorage("contactsNudgeDismissedUntilEpoch") private var contactsNudgeDismissedUntilEpoch: Double = 0
    private var now: Double { Date().timeIntervalSince1970 }
    private var contactsNudgeGloballyDismissed: Bool { contactsNudgeDismissedUntilEpoch > now }

    @State private var searchText: String = ""

    @State private var showingYourProfile = false
    @State private var yourProfile: PersonalityProfile?
    @State private var loadingYourProfile = false
    @State private var yourProfileError: String?
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""

    var body: some View {
        Group {
            if !hasMessagesAccess {
                AccessGateView {
                    refreshAccessAndReload()
                }
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if shouldShowContactsNudge {
                                ContactsNudgeBanner(
                                    onOpenContactsSettings: { openContactsPrivacySettingsForce() },
                                    onRequestContacts: { requestContacts() },
                                    onNotNow: {
                                        contactsNudgeDismissedUntilEpoch = now + (7 * 24 * 60 * 60)
                                    }
                                )
                                .padding(.vertical, 6)
                            }

                            if isLoadingChats {
                                ProgressView("Loading chats…")
                                    .padding(.vertical, 20)
                            }

                            if let chatLoadError {
                                Text("Error: \(chatLoadError)")
                                    .foregroundStyle(.red)
                                    .padding(.vertical, 8)
                            }

                            if filteredChats.isEmpty && !isLoadingChats && chatLoadError == nil {
                                VStack(spacing: 16) {
                                    Text("No chats found.")
                                        .font(.headline)

                                    Text("If this seems wrong, double-check Full Disk Access and click Retry.")
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                    
                                    Button("🎬 Load Demo for Ad") {
                                        loadDemoData()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .help("Load demo data with world leaders for recording ads")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                            } else {
                                let chatsToShow = filteredChats

                                LazyVStack(spacing: 0) {
                                    ForEach(Array(chatsToShow.enumerated()), id: \.element.id) { idx, chat in
                                        NavigationLink(value: chat) {
                                            ChatRow(chat: chat)
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if idx != chatsToShow.count - 1 {
                                            Rectangle()
                                                .fill(Color.primary.opacity(0.12))
                                                .frame(height: 1)
                                                .padding(.leading, 16)
                                                .padding(.trailing, 16)
                                        }
                                    }
                                }
                                .id(contactsRevision)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black.opacity(0.03))
                    .navigationTitle("ReactStat")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            HStack {
                                Button("👤 Your Profile") {
                                    showingYourProfile = true
                                    loadYourProfile()
                                }
                                .help("See your personality profile across all chats")

                                Button("🎬 Demo") {
                                    loadDemoData()
                                }
                                .help("Load demo data with world leaders")

                                Button("Retry") {
                                    refreshAccessAndReload()
                                }
                                .help("Re-check permissions and reload")
                            }
                        }

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
                    .navigationDestination(for: ChatThread.self) { chat in
                        ChatDetailView(chat: chat)
                    }
                    .searchable(text: $searchText,
                                placement: .toolbar,
                                prompt: "Search chats")
                    .task {
                        refreshAccessAndReload()
                    }
                    .sheet(isPresented: $showingYourProfile) {
                        YourPersonalitySheet(
                            profile: yourProfile,
                            isLoading: loadingYourProfile,
                            error: yourProfileError,
                            onRegenerate: { loadYourProfile() }
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessAndReload()
        }
    }

    private var filteredChats: [ChatThread] {
        let base = chats.filter { $0.participantCount >= 3 }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.chatIdentifier.localizedCaseInsensitiveContains(trimmed)
        }
    }

    @MainActor
    private func refreshAccessAndReload() {
        let oldContacts = contactsStatus
        hasMessagesAccess = MessagesDBHealth.hasAccess()
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)

        if oldContacts != contactsStatus {
            ContactNameCache.shared.resetWarmState()
            contactsRevision &+= 1
        }

        warmContactsAndRefreshTitlesIfNeeded()

        guard hasMessagesAccess else { return }
        loadChats()
    }

    private var shouldShowContactsNudge: Bool {
        !contactsNudgeGloballyDismissed && contactsStatus != .authorized
    }

    private func requestContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async {
                refreshAccessAndReload()
            }
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

    @MainActor
    private func warmContactsAndRefreshTitlesIfNeeded() {
        guard contactsStatus == .authorized else { return }

        Task.detached(priority: .utility) {
            ContactNameCache.shared.warmIfNeeded()

            await MainActor.run {
                // Rebuild the threads so the fallback titles + search index incorporate resolved contact names.
                self.chats = self.chats.map { t in
                    ChatThread(
                        id: t.id,
                        chatIdentifier: t.chatIdentifier,
                        displayName: t.displayName,
                        messageCount: t.messageCount,
                        participantCount: t.participantCount,
                        participantHandles: t.participantHandles
                    )
                }

                // Force row labels to re-render even though ContactNameCache isn't observable.
                self.contactsRevision &+= 1
            }
        }
    }

    private func openContactsPrivacySettingsForce() {
        let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!

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

    @MainActor
    private func loadChats() {
        chatLoadError = nil
        isLoadingChats = true

        Task.detached(priority: .userInitiated) {
            do {
                let threads = try ChatRepository.fetchChats(limit: 200)
                await MainActor.run {
                    self.chats = threads
                    self.isLoadingChats = false
                    self.warmContactsAndRefreshTitlesIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self.chatLoadError = error.localizedDescription
                    self.isLoadingChats = false
                }
            }
        }
    }
    
    @MainActor
    private func loadYourProfile() {
        yourProfile = nil
        yourProfileError = nil
        loadingYourProfile = true

        let capturedKey = apiKey
        Task.detached(priority: .utility) {
            do {
                let profile = try await PersonalityStatsRepository.yourCrossGroupProfile(apiKey: capturedKey)
                await MainActor.run {
                    self.yourProfile = profile
                    self.loadingYourProfile = false
                }
            } catch {
                await MainActor.run {
                    self.yourProfileError = error.localizedDescription
                    self.loadingYourProfile = false
                }
            }
        }
    }

    @MainActor
    private func loadDemoData() {
        let demoChat = DemoData.createDemoChat()
        self.chats = [demoChat]
        self.chatLoadError = nil
        self.isLoadingChats = false
    }
}

private struct ChatRow: View {
    let chat: ChatThread

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "message.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.blue.opacity(0.55))
                .frame(width: 28)

            Text(chat.title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
