import SwiftUI
import UserNotifications

@main
struct TransmissionOpenerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var torrentManager = TorrentManager()

    var body: some Scene {
        Window("Transmission Opener", id: "main") {
            TorrentListView()
                .environment(torrentManager)
        }
        .defaultSize(width: 800, height: 500)

        MenuBarExtra("Transmission Opener", systemImage: "arrow.up.doc") {
            if let stats = torrentManager.sessionStats {
                Text("\(stats.activeTorrentCount) active, \(stats.pausedTorrentCount) paused")
                if torrentManager.totalDownloadRate > 0 || torrentManager.totalUploadRate > 0 {
                    Text("↓ \(formatRate(torrentManager.totalDownloadRate))  ↑ \(formatRate(torrentManager.totalUploadRate))")
                }
                Divider()
            }
            SettingsLink {
                Text("Settings...")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleFile(url: url)
        }
    }

    private func handleFile(url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "torrent" else { return }
        let fileName = url.lastPathComponent

        Task {
            do {
                let client = TransmissionClient.fromDefaults()
                let name = try await client.addTorrent(fileURL: url)
                await postNotification(title: "Torrent Added", body: name)
            } catch {
                await postNotification(title: "Failed to Add \(fileName)", body: error.localizedDescription)
            }
        }
    }

    private func postNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
