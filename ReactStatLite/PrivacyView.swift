import SwiftUI

struct PrivacyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Privacy")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("• All processing happens locally on your Mac.")
                Text("• Your messages are never uploaded.")
                Text("• No accounts, analytics, or tracking.")
                Text("• No data leaves your device.")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(width: 360)
    }
}
