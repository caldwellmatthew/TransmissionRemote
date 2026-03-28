import Foundation
import UserNotifications

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

@MainActor
@Observable
final class TorrentManager {
    private(set) var torrents: [Torrent] = []
    private(set) var sessionStats: SessionStats?
    private(set) var sessionSettings: SessionSettings?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var errorMessage: String?
    var actionError: String?

    var selectedTorrentIDs: Set<Int> = []
    var searchText: String = ""
    var statusFilter: StatusFilter = .all

    private var client: TransmissionClient
    private var pollTask: Task<Void, Never>?
    private var previousPercentDone: [Int: Double] = [:]

    private var pollInterval: TimeInterval {
        UserDefaults.standard.double(forKey: "pollInterval").nonZero ?? 5.0
    }

    enum ConnectionState {
        case disconnected, connecting, connected, error
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, active, downloading, seeding, stopped, error

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:         "All"
            case .active:      "Active"
            case .downloading: "Downloading"
            case .seeding:     "Seeding"
            case .stopped:     "Paused"
            case .error:       "Errors"
            }
        }

        var systemImage: String {
            switch self {
            case .all:         "tray.full"
            case .active:      "bolt.circle"
            case .downloading: "arrow.down.circle"
            case .seeding:     "arrow.up.circle"
            case .stopped:     "pause.circle"
            case .error:       "exclamationmark.triangle"
            }
        }
    }

    var filteredTorrents: [Torrent] {
        var result = torrents

        switch statusFilter {
        case .all:
            break
        case .active:
            result = result.filter { $0.rateDownload > 0 || $0.rateUpload > 0 }
        case .downloading:
            result = result.filter { $0.status == .downloading || $0.status == .downloadWait }
        case .seeding:
            result = result.filter { $0.status == .seeding || $0.status == .seedWait }
        case .stopped:
            result = result.filter { $0.status == .stopped }
        case .error:
            result = result.filter { $0.error != 0 }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    var isTurtleModeEnabled: Bool {
        sessionSettings?.altSpeedEnabled ?? false
    }

    var totalDownloadRate: Int {
        torrents.reduce(0) { $0 + $1.rateDownload }
    }

    var totalUploadRate: Int {
        torrents.reduce(0) { $0 + $1.rateUpload }
    }

    init() {
        client = TransmissionClient.fromDefaults()
        startPolling()
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        if connectionState == .disconnected {
            connectionState = .connecting
        }

        do {
            async let fetchedTorrents = client.getTorrents()
            async let fetchedStats = client.getSessionStats()
            async let fetchedSettings = client.getSessionSettings()
            let newTorrents = try await fetchedTorrents
            sessionStats = try await fetchedStats
            sessionSettings = try await fetchedSettings

            if UserDefaults.standard.bool(forKey: "notifyOnCompletion") {
                checkForCompletions(newTorrents)
            }

            // Update tracking state for next poll
            previousPercentDone = Dictionary(uniqueKeysWithValues: newTorrents.map { ($0.id, $0.percentDone) })
            torrents = newTorrents
            connectionState = .connected
            errorMessage = nil
        } catch {
            connectionState = .error
            errorMessage = error.localizedDescription
        }
    }

    private func checkForCompletions(_ newTorrents: [Torrent]) {
        // Only check if we have previous state (skip first poll)
        guard !previousPercentDone.isEmpty else { return }

        for torrent in newTorrents {
            let wasDone = previousPercentDone[torrent.id].map { $0 >= 1.0 } ?? false
            if torrent.percentDone >= 1.0 && !wasDone {
                postCompletionNotification(for: torrent)
            }
        }
    }

    private nonisolated func postCompletionNotification(for torrent: Torrent) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = torrent.name
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "torrent-complete-\(torrent.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func reconnect() {
        stopPolling()
        client = TransmissionClient.fromDefaults()
        connectionState = .disconnected
        startPolling()
    }

    func getTorrentDetail(id: Int) async -> Torrent? {
        try? await client.getTorrentDetail(id: id)
    }

    // MARK: - Session

    func getDefaultDownloadDir() async -> String {
        do {
            return try await client.getSession().downloadDir
        } catch is CancellationError {
            return ""
        } catch let error as URLError where error.code == .cancelled {
            return ""
        } catch {
            actionError = error.localizedDescription
            return ""
        }
    }

    // MARK: - Actions

    func addTorrent(fileURL: URL, options: TorrentAddOptions = TorrentAddOptions()) async throws -> String {
        let name = try await client.addTorrent(fileURL: fileURL, options: options)
        await refresh()
        return name
    }

    func addTorrent(url: String, options: TorrentAddOptions = TorrentAddOptions()) async throws -> String {
        let name = try await client.addTorrent(url: url, options: options)
        await refresh()
        return name
    }

    func startSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.startTorrents(ids: ids) }
        await refresh()
    }

    func stopSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.stopTorrents(ids: ids) }
        await refresh()
    }

    func removeSelected(deleteData: Bool) async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.removeTorrents(ids: ids, deleteLocalData: deleteData) }
        selectedTorrentIDs.removeAll()
        await refresh()
    }

    func verifySelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.verifyTorrents(ids: ids) }
        await refresh()
    }

    func reannounceSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.reannounceTorrents(ids: ids) }
    }

    func queueMoveTopSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.queueMoveTop(ids: ids) }
        await refresh()
    }

    func queueMoveUpSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.queueMoveUp(ids: ids) }
        await refresh()
    }

    func queueMoveDownSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.queueMoveDown(ids: ids) }
        await refresh()
    }

    func queueMoveBottomSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.queueMoveBottom(ids: ids) }
        await refresh()
    }

    func setBandwidthPrioritySelected(priority: Int) async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        await performAction { try await self.client.setBandwidthPriority(ids: ids, priority: priority) }
        await refresh()
    }

    func setFileWanted(torrentID: Int, fileIndex: Int, wanted: Bool) async throws {
        if wanted {
            try await client.setFilesWanted(id: torrentID, fileIndices: [fileIndex])
        } else {
            try await client.setFilesUnwanted(id: torrentID, fileIndices: [fileIndex])
        }
    }

    func setFilePriority(torrentID: Int, fileIndex: Int, priority: Int) async throws {
        try await client.setFilePriority(id: torrentID, fileIndices: [fileIndex], priority: priority)
    }

    func toggleTurtleMode() async {
        guard let current = sessionSettings?.altSpeedEnabled else { return }
        var args = SessionSetArgs()
        args.altSpeedEnabled = !current
        await performAction { try await self.client.setSession(args) }
        await refresh()
    }

    func updateSessionSettings(_ args: SessionSetArgs) async {
        await performAction { try await self.client.setSession(args) }
        await refresh()
    }

    func setTorrentSpeedLimits(id: Int, downloadLimit: Int?, downloadLimited: Bool?,
                               uploadLimit: Int?, uploadLimited: Bool?) async {
        await performAction {
            try await self.client.setTorrentSpeedLimits(
                id: id, downloadLimit: downloadLimit, downloadLimited: downloadLimited,
                uploadLimit: uploadLimit, uploadLimited: uploadLimited)
        }
    }

    func setLocation(ids: [Int], location: String, move: Bool) async {
        await performAction { try await self.client.setLocation(ids: ids, location: location, move: move) }
        await refresh()
    }

    // MARK: - Private

    private func performAction(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            actionError = error.localizedDescription
        }
    }
}
