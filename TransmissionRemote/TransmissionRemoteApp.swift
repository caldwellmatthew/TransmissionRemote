import SwiftUI
import UserNotifications

extension Notification.Name {
    static let openTorrentFile = Notification.Name("openTorrentFile")
    static let addTorrentLink = Notification.Name("addTorrentLink")
    static let showTorrentInfo = Notification.Name("showTorrentInfo")
    static let resetColumns = Notification.Name("resetColumns")
}

@main
struct TransmissionRemoteApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var torrentManager = TorrentManager()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        UserDefaults.standard.register(defaults: ["notifyOnCompletion": true])
    }

    var body: some Scene {
        Window("Transmission Remote", id: "main") {
            TorrentListView()
                .environment(torrentManager)
        }
        .defaultSize(width: 800, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Torrent File...") {
                    NotificationCenter.default.post(name: .openTorrentFile, object: nil)
                }
                .keyboardShortcut("o")

                Button("Add Magnet or URL...") {
                    NotificationCenter.default.post(name: .addTorrentLink, object: nil)
                }
                .keyboardShortcut("l")
            }
            CommandGroup(after: .toolbar) {
                Button("Reset Columns to Default") {
                    UserDefaults.standard.removeObject(forKey: "torrentTableColumns")
                    UserDefaults.standard.removeObject(forKey: "torrentTableColumnWidths")
                    NotificationCenter.default.post(name: .resetColumns, object: nil)
                }
            }
            CommandGroup(after: .sidebar) {
                Button("Get Info") {
                    NotificationCenter.default.post(name: .showTorrentInfo, object: nil)
                }
                .keyboardShortcut("i")
            }
        }

        WindowGroup("Torrent Info", id: "torrent-detail", for: Int.self) { $torrentID in
            if let torrentID {
                TorrentDetailView(torrentID: torrentID)
                    .environment(torrentManager)
            }
        }
        .defaultSize(width: 750, height: 550)

        MenuBarExtra("Transmission Remote", systemImage: "arrow.up.doc", isInserted: $showMenuBarExtra) {
            if let stats = torrentManager.sessionStats {
                Text("\(stats.activeTorrentCount) active, \(stats.pausedTorrentCount) paused")
                if torrentManager.totalDownloadRate > 0 || torrentManager.totalUploadRate > 0 {
                    Text("↓ \(formatRate(torrentManager.totalDownloadRate))  ↑ \(formatRate(torrentManager.totalUploadRate))")
                }
                Divider()
            }
            Toggle("Turtle Mode", isOn: Binding(
                get: { torrentManager.isTurtleModeEnabled },
                set: { _ in Task { await torrentManager.toggleTurtleMode() } }
            ))
            Divider()
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
                .environment(torrentManager)
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
            if url.scheme == "magnet" {
                NotificationCenter.default.post(name: .addTorrentLink, object: url.absoluteString)
            } else if url.isFileURL, url.pathExtension.lowercased() == "torrent" {
                NotificationCenter.default.post(name: .openTorrentFile, object: url)
            }
        }
    }
}
