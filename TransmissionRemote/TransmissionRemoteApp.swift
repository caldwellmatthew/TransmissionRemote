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

        MenuBarExtra("Transmission Remote", systemImage: "arrow.up.arrow.down.circle.fill", isInserted: $showMenuBarExtra) {
            MenuBarContent()
                .environment(torrentManager)
        }

        Settings {
            SettingsView()
                .environment(torrentManager)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(TorrentManager.self) private var manager

    var body: some View {
        if let stats = manager.sessionStats {
            Text("\(stats.activeTorrentCount) active, \(stats.pausedTorrentCount) paused")
            if manager.totalDownloadRate > 0 || manager.totalUploadRate > 0 {
                Text("↓ \(formatRate(manager.totalDownloadRate))  ↑ \(formatRate(manager.totalUploadRate))")
            }
            Divider()
        }
        Toggle("Turtle Mode", isOn: Binding(
            get: { manager.isTurtleModeEnabled },
            set: { _ in Task { await manager.toggleTurtleMode() } }
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
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    // Intercept file-open and URL Apple Events ourselves. SwiftUI's default
    // 'odoc' dispatch can tear down and re-create the Window scene to
    // "deliver" the URL, producing a visible flash before the add-torrent
    // sheet appears. Installing our own handlers bypasses SwiftUI's URL
    // routing entirely.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let aem = NSAppleEventManager.shared()
        aem.setEventHandler(
            self,
            andSelector: #selector(handleOpenDocsAE(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
        aem.setEventHandler(
            self,
            andSelector: #selector(handleGetURLAE(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleOpenDocsAE(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlList = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
        let count = urlList.numberOfItems
        guard count > 0 else { return }
        for i in 1...count {
            guard let item = urlList.atIndex(i),
                  let urlDesc = item.coerce(toDescriptorType: typeFileURL),
                  let url = URL(dataRepresentation: urlDesc.data, relativeTo: nil) else { continue }
            if url.isFileURL, url.pathExtension.lowercased() == "torrent" {
                NotificationCenter.default.post(name: .openTorrentFile, object: url)
            }
        }
    }

    @objc func handleGetURLAE(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        if let urlStr = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlStr), url.scheme == "magnet" {
            NotificationCenter.default.post(name: .addTorrentLink, object: url.absoluteString)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["notifyOnCompletion": true])
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
}
