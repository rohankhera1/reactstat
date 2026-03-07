import SwiftUI
import AppKit

struct AccessGateView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(spacing: 10) {
                Text("ReactStat Needs Access")
                    .font(.title.bold())

                Text("To analyze your group chats, ReactStat needs Full Disk Access to read your Messages database.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                Text("Your messages never leave your Mac. Everything runs locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            VStack(spacing: 12) {
                Button("Open System Settings") {
                    // Prefer direct deep link; if it fails, user can still follow the instructions below.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("I've Enabled Access — Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            Text("System Settings → Privacy & Security → Full Disk Access → Enable ReactStat")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
