import SwiftUI
import Contacts
import AppKit

struct ContactsNudgeBanner: View {
    let onOpenContactsSettings: () -> Void
    let onRequestContacts: () -> Void
    let onNotNow: () -> Void

    private var status: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Show real names in this chat")
                    .font(.headline)

                Text("Enable Contacts to replace phone numbers with names.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(primaryCTATitle) {
                        handlePrimaryCTA()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Not now") {
                        onNotNow()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.14), lineWidth: 1)
        )
    }

    private var primaryCTATitle: String {
        switch status {
        case .notDetermined:
            return "Enable"
        case .denied, .restricted:
            return "Open Contacts Settings"
        case .authorized:
            return "Enabled"
        @unknown default:
            return "Open Contacts Settings"
        }
    }

    private func handlePrimaryCTA() {
        switch status {
        case .notDetermined:
            onRequestContacts()
        case .denied, .restricted:
            onOpenContactsSettings()
        case .authorized:
            break
        @unknown default:
            onOpenContactsSettings()
        }
    }
}
