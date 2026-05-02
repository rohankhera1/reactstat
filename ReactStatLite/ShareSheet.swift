import SwiftUI
import AppKit
import Foundation

// MARK: - Share payload

struct SharePackPayload {
    let chatTitle: String
    let totalMessages: Int
    let totalReactions: Int
    let messageShare: [ShareRow]
    let givenRatiosByKind: [ReactionKind: [RatioRow]]
    let receivedRatiosByKind: [ReactionKind: [RatioRow]]

    // Advanced stats (formerly “premium”)
    let premiumStats: [PremiumStat]

    // ✅ NEW: true when advanced computation finished (even if empty)
    let advancedStatsLoaded: Bool
}

// MARK: - Share sheet (macOS)

struct ShareSheet: View {
    let payload: SharePackPayload

    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var progressText: String?
    @State private var lastError: String?

    // Preview state
    @State private var previewImages: [NSImage] = []
    @State private var renderedURLs: [URL] = []
    @State private var selectedPage: Int = 0

    // Anchor for share picker
    @State private var shareButtonAnchorView: NSView?

    // Timeout safety (if advanced stalls)
    @State private var didStartTimeout = false
    @State private var advancedTimeoutFired = false

    private let storySize = CGSize(width: 1080, height: 1920)
    private let kinds: [ReactionKind] = [.laughed, .liked, .loved, .emphasized, .questioned, .disliked]

    // Free app: always include the Advanced page.
    private let advancedPageCount: Int = 1
    private var totalPageCount: Int { 1 + advancedPageCount + kinds.count }

    private var reactionsReady: Bool {
        guard !payload.messageShare.isEmpty else { return false }
        return kinds.allSatisfy { kind in
            payload.givenRatiosByKind[kind] != nil && payload.receivedRatiosByKind[kind] != nil
        }
    }

    private var advancedReady: Bool {
        payload.advancedStatsLoaded || advancedTimeoutFired
    }

    private var isDataReady: Bool {
        reactionsReady && advancedReady
    }

    private var canShareOrSave: Bool {
        isDataReady && !isExporting && !renderedURLs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            previewArea

            HStack(spacing: 10) {
                Button {
                    Task { await shareStoryPack() }
                } label: {
                    Label("Share Story Pack (\(totalPageCount) pages)", systemImage: "square.and.arrow.up")
                }
                .background(
                    AnchorView { v in
                        self.shareButtonAnchorView = v
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                )
                .disabled(!canShareOrSave)

                Button {
                    Task { await saveStoryPackToFolder() }
                } label: {
                    Label("Save PNGs…", systemImage: "folder")
                }
                .disabled(!canShareOrSave)

                Spacer()

                if isExporting {
                    ProgressView().controlSize(.small)
                }

                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            statusLine

            if let progressText {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 620)
        .task {
            // Start the timeout once.
            if !didStartTimeout {
                didStartTimeout = true
                Task.detached {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                    await MainActor.run { self.advancedTimeoutFired = true }
                }
            }

            // If already ready, auto-generate immediately.
            await maybeAutoRegenerate()
        }
        .onChange(of: reactionsReady) { _, _ in
            Task { await maybeAutoRegenerate() }
        }
        .onChange(of: payload.advancedStatsLoaded) { _, _ in
            Task { await maybeAutoRegenerate() }
        }
        .onChange(of: advancedTimeoutFired) { _, _ in
            Task { await maybeAutoRegenerate() }
        }
        // Optional: if user re-opens ShareSheet later and stats changed, this will refresh.
        .onChange(of: payload.totalMessages) { _, _ in Task { await maybeAutoRegenerate(force: false) } }
        .onChange(of: payload.totalReactions) { _, _ in Task { await maybeAutoRegenerate(force: false) } }
    }

    private var header: some View {
        HStack {
            Text("Share")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
    }

    private var statusLine: some View {
        Group {
            if !reactionsReady {
                Text("Still collecting stats…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !advancedReady {
                Text("Still collecting advanced stats…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isExporting || (isDataReady && previewImages.isEmpty) {
                Text("Generating story pack…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preview UI

    private var previewArea: some View {
        GroupBox {
            VStack(spacing: 10) {
                if !isDataReady {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(!reactionsReady ? "Still collecting stats…" : "Still collecting advanced stats…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 520)
                } else if isExporting || previewImages.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(progressText ?? "Rendering…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 520)
                } else {
                    TabView(selection: $selectedPage) {
                        ForEach(Array(previewImages.enumerated()), id: \.offset) { idx, img in
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.automatic)
                    .frame(maxWidth: .infinity, minHeight: 520)

                    HStack(spacing: 12) {
                        Button {
                            withAnimation { selectedPage = max(0, selectedPage - 1) }
                        } label: {
                            Label("Prev", systemImage: "chevron.left")
                        }
                        .disabled(selectedPage <= 0)

                        Text("Page \(selectedPage + 1) of \(previewImages.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Button {
                            withAnimation { selectedPage = min(previewImages.count - 1, selectedPage + 1) }
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                        }
                        .disabled(selectedPage >= previewImages.count - 1)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Auto-generation

    private func maybeAutoRegenerate(force: Bool = true) async {
        guard isDataReady else { return }
        guard !isExporting else { return }

        // If we already have a rendered pack and we’re not forcing, don’t re-render.
        if !force, !renderedURLs.isEmpty, !previewImages.isEmpty { return }

        // Only generate if we don’t have a preview yet.
        if previewImages.isEmpty || renderedURLs.isEmpty {
            await regenerate()
        }
    }

    // MARK: - Actions

    private func regenerate() async {
        guard isDataReady else {
            await MainActor.run { self.progressText = "Still collecting stats…" }
            return
        }

        await exportStoryPack { urls, images in
            self.renderedURLs = urls
            self.previewImages = images
            self.selectedPage = 0
        }
    }

    private func shareStoryPack() async {
        guard canShareOrSave else { return }

        await MainActor.run {
            if let anchor = shareButtonAnchorView {
                ShareTools.presentSharePicker(items: renderedURLs, relativeTo: anchor.bounds, of: anchor)
            } else if let window = NSApp.keyWindow, let content = window.contentView {
                ShareTools.presentSharePicker(items: renderedURLs, relativeTo: content.bounds, of: content)
            } else {
                lastError = "Couldn’t find a window to anchor the share picker."
            }
        }
    }

    private func saveStoryPackToFolder() async {
        guard canShareOrSave else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to save the story pack PNGs."

        let resp = panel.runModal()
        guard resp == .OK, let folder = panel.url else { return }

        do {
            for url in renderedURLs {
                let dest = folder.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: url, to: dest)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func exportStoryPack(_ onDone: @escaping ([URL], [NSImage]) -> Void) async {
        isExporting = true
        lastError = nil
        progressText = "Preparing pages…"

        do {
            let urls = try await ShareTools.renderStoryPackToTempURLs(
                payload: payload,
                kinds: kinds,
                size: storySize,
                onProgress: { msg in
                    await MainActor.run { self.progressText = msg }
                }
            )

            var images: [NSImage] = []
            images.reserveCapacity(urls.count)
            for u in urls {
                if let img = NSImage(contentsOf: u) {
                    images.append(img)
                }
            }

            await MainActor.run {
                self.isExporting = false
                self.progressText = "Ready."
                onDone(urls, images)
            }
        } catch {
            await MainActor.run {
                self.isExporting = false
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Rendering + share helpers

enum ShareTools {

    @MainActor
    static func renderPNGData<V: View>(_ view: V, size: CGSize) throws -> Data {
        let framed = view
            .frame(width: size.width, height: size.height)
            .clipped()

        let renderer = ImageRenderer(content: framed)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 1

        guard let nsImage = renderer.nsImage else {
            throw NSError(domain: "ReactStatLite", code: 9001, userInfo: [NSLocalizedDescriptionKey: "Failed to render image"])
        }
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ReactStatLite", code: 9002, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        return png
    }

    static func presentSharePicker(items: [Any], relativeTo rect: NSRect, of anchor: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
    }

    static func tempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ReactStatStoryPack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func renderStoryPackToTempURLs(
        payload: SharePackPayload,
        kinds: [ReactionKind],
        size: CGSize,
        onProgress: @escaping @Sendable (String) async -> Void
    ) async throws -> [URL] {

        // cover + advanced + each reaction kind
        let totalPages = 1 + 1 + kinds.count

        let dir = try tempDir()
        let slug = safeFileName(payload.chatTitle)
        let titleSlug = slug.isEmpty ? "Chat" : slug

        var urls: [URL] = []
        urls.reserveCapacity(totalPages)

        await onProgress("Rendering 1/\(totalPages): cover…")
        let coverView = StoryCoverPageView(
            chatTitle: payload.chatTitle,
            totalMessages: payload.totalMessages,
            totalReactions: payload.totalReactions,
            mainCharacter: payload.messageShare.first,
            messageShare: payload.messageShare
        )

        let coverData = try await MainActor.run {
            try renderPNGData(coverView, size: size)
        }

        let coverURL = dir.appendingPathComponent("\(titleSlug)-01-Cover.png")
        try coverData.write(to: coverURL, options: Data.WritingOptions.atomic)
        urls.append(coverURL)

        // Advanced page (page 2)
        await onProgress("Rendering 2/\(totalPages): Advanced…")

        let advancedView = StoryAdvancedPageView(
            chatTitle: payload.chatTitle,
            stats: payload.premiumStats
        )

        let advancedData = try await MainActor.run {
            try renderPNGData(advancedView, size: size)
        }

        let advancedURL = dir.appendingPathComponent("\(titleSlug)-02-Advanced.png")
        try advancedData.write(to: advancedURL, options: Data.WritingOptions.atomic)
        urls.append(advancedURL)

        let base = 3

        for (idx, kind) in kinds.enumerated() {
            let pageNum = idx + base
            await onProgress("Rendering \(pageNum)/\(totalPages): \(kind.emoji) \(kind.title)…")

            let given = payload.givenRatiosByKind[kind] ?? []
            let received = payload.receivedRatiosByKind[kind] ?? []

            let pageView = StoryReactionPageView(
                kind: kind,
                chatTitle: payload.chatTitle,
                given: Array(given.prefix(10)),
                received: Array(received.prefix(10))
            )

            let data = try await MainActor.run {
                try renderPNGData(pageView, size: size)
            }

            let file = dir.appendingPathComponent("\(titleSlug)-\(String(format: "%02d", pageNum))-\(kind.title).png")
            try data.write(to: file, options: Data.WritingOptions.atomic)
            urls.append(file)
        }

        await onProgress("Done.")
        return urls
    }
}

// MARK: - NSView anchor

private struct AnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView) }
    }
}

// MARK: - Advanced page (kept here to avoid redeclare conflicts)

private struct StoryAdvancedPageView: View {
    let chatTitle: String
    let stats: [PremiumStat]

    var body: some View {
        ZStack {
            Color.white

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("✨")
                        .font(.system(size: 52, weight: .bold))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Advanced")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.90))

                        Text(chatTitle)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.60))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Text("ReactStat.com")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Advanced insights")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.90))

                    if stats.isEmpty {
                        Text("Not enough data yet")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.60))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(stats.prefix(6).enumerated()), id: \.offset) { _, stat in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(stat.title)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(Color.black.opacity(0.90))

                                    Text(stat.subtitle)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.60))
                                        .lineLimit(2)
                                }
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(22)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.25), lineWidth: 2)
                )

                Spacer()

                Text("Made with ReactStat.com")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(72)
        }
    }
}
