import SwiftUI

struct ContactsPermissionHelpSheet: View {
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.top, 10)

            Text("Enable Contacts")
                .font(.title2.bold())

            Text("ReactStat can show real names instead of phone numbers.\nYour contacts never leave your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Steps")
                    .font(.headline)

                Text("1) Open System Settings")
                Text("2) Privacy & Security → Contacts")
                Text("3) Turn on ReactStat")
                Text("4) Return to ReactStat")
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 12)
        }
        .padding(20)
        .frame(width: 520)
    }
}
