import SwiftUI

struct StatusView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            switch appState.status {
            case .idle:
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Open a .torrent file to send it to Transmission")
                    .foregroundStyle(.secondary)

            case .sending:
                ProgressView()
                    .controlSize(.large)
                Text("Sending \(appState.lastFileName)...")

            case .success(let name):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Added: \(name)")

            case .error(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(minWidth: 350, minHeight: 200)
    }
}
