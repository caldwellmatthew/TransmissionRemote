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
                .environment(appDelegate)
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
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Torrents handed to us by Finder or a magnet link, waiting for the main
    /// window to present them. Queued rather than posted as notifications: an
    /// event that launches the app arrives before any view exists to observe
    /// it, and several files can arrive in one event.
    var pendingAdds: [AddTorrentSheet.Source] = []

    // Intercept file-open and URL Apple Events ourselves rather than going
    // through SwiftUI's URL routing:
    // - With `application(_:open:)`, SwiftUI still routes the event to the
    //   main window and re-presents it: the window blanks to white and
    //   briefly shrinks before the sheet appears. Handling the events here
    //   leaves the window untouched.
    // - `.onOpenURL` receives only the first file of a multi-file open, both
    //   at launch and while running, and `handlesExternalEvents` doesn't
    //   change that; the rest are silently dropped.
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
                pendingAdds.append(.file(url))
            }
        }
    }

    @objc func handleGetURLAE(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        if let urlStr = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlStr), url.scheme == "magnet" {
            pendingAdds.append(.link(url.absoluteString))
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
