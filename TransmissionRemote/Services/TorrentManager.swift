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
    private(set) var pendingAddCount: Int = 0
    var actionError: String?

    var selectedTorrentIDs: Set<Int> = []
    var searchText: String = ""
    var statusFilter: StatusFilter = .all

    private var client: TransmissionClient
    private var pollTask: Task<Void, Never>?
    private(set) var previousPercentDone: [String: Double] = [:]
    private var refreshTask: Task<Void, Never>?

    private var pollInterval: TimeInterval {
        max(1, UserDefaults.standard.double(forKey: "pollInterval").nonZero ?? 5.0)
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

    private static let invalidServerURLMessage =
        "Invalid server URL. Check the address in Settings."

    init() {
        if let configured = TransmissionClient.fromDefaults() {
            client = configured
            startPolling()
        } else {
            client = TransmissionClient(endpoint: TransmissionClient.defaultEndpoint,
                                        username: nil, password: nil)
            connectionState = .error
            errorMessage = Self.invalidServerURLMessage
        }
    }

    /// Test-only initializer that skips network setup
    init(testing: Bool) {
        client = TransmissionClient.fromDefaults()
            ?? TransmissionClient(endpoint: TransmissionClient.defaultEndpoint,
                                  username: nil, password: nil)
        // Don't start polling in tests
    }

    /// Test-only: set torrents directly
    func setTorrents(_ newTorrents: [Torrent]) {
        torrents = newTorrents
    }

    /// Test-only: set previous percent done for completion detection tests
    func setPreviousPercentDone(_ values: [String: Double]) {
        previousPercentDone = values
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
        let previous = refreshTask
        let task = Task { @MainActor in
            _ = await previous?.value
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        if connectionState == .disconnected {
            connectionState = .connecting
        }

        let client = self.client
        do {
            async let fetchedTorrents = client.getTorrents()
            async let fetchedStats = client.getSessionStats()
            async let fetchedSettings = client.getSessionSettings()
            let newTorrents = try await fetchedTorrents
            let newStats = try await fetchedStats
            let newSettings = try await fetchedSettings

            // Drop results that arrive after reconnect() swapped the client,
            // so old-server state can't leak into the new connection.
            guard client === self.client else { return }
            sessionStats = newStats
            sessionSettings = newSettings

            if UserDefaults.standard.bool(forKey: "notifyOnCompletion") {
                checkForCompletions(newTorrents)
            }

            // Update tracking state for next poll. Key by hashString (stable across
            // server restarts) rather than id (renumbered on daemon restart).
            previousPercentDone = Dictionary(
                uniqueKeysWithValues: newTorrents.compactMap { t in
                    t.hashString.map { ($0, t.percentDone) }
                }
            )
            torrents = newTorrents
            connectionState = .connected
            errorMessage = nil
        } catch {
            guard client === self.client else { return }
            connectionState = .error
            errorMessage = error.localizedDescription
        }
    }

    func checkForCompletions(_ newTorrents: [Torrent]) {
        for torrent in newlyCompleted(newTorrents) {
            postCompletionNotification(for: torrent)
        }
    }

    func newlyCompleted(_ newTorrents: [Torrent]) -> [Torrent] {
        // Only check if we have previous state (skip first poll)
        guard !previousPercentDone.isEmpty else { return [] }

        return newTorrents.filter { torrent in
            guard let hash = torrent.hashString else { return false }
            let wasDone = previousPercentDone[hash].map { $0 >= 1.0 } ?? false
            return torrent.percentDone >= 1.0 && !wasDone
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
        guard let newClient = TransmissionClient.fromDefaults() else {
            connectionState = .error
            errorMessage = Self.invalidServerURLMessage
            return
        }
        client = newClient
        // Hashes from the previous server must not seed completion detection,
        // or every finished torrent on the new server would notify at once.
        previousPercentDone = [:]
        connectionState = .disconnected
        startPolling()
    }

    func getTorrentDetail(id: Int) async -> Torrent? {
        try? await client.getTorrentDetail(id: id)
    }

    // MARK: - Session

    /// Returns the server's default download directory. Failures return an
    /// empty string (which already means "use the server default"). When
    /// `reportErrors` is false, errors are swallowed silently rather than
    /// surfaced via `actionError` — the Add sheet uses this so a failed lookup
    /// doesn't pop the main window's error alert underneath the sheet.
    func getDefaultDownloadDir(reportErrors: Bool = true) async -> String {
        do {
            return try await client.getSession().downloadDir
        } catch is CancellationError {
            return ""
        } catch let error as URLError where error.code == .cancelled {
            return ""
        } catch {
            if reportErrors { actionError = error.localizedDescription }
            return ""
        }
    }

    // MARK: - Actions

    func addTorrentInBackground(fileURL: URL, options: TorrentAddOptions = TorrentAddOptions()) {
        pendingAddCount += 1
        Task {
            do {
                _ = try await client.addTorrent(fileURL: fileURL, options: options)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                actionError = error.localizedDescription
            }
            pendingAddCount -= 1
            await refresh()
        }
    }

    func addTorrentInBackground(url: String, options: TorrentAddOptions = TorrentAddOptions()) {
        pendingAddCount += 1
        Task {
            do {
                _ = try await client.addTorrent(url: url, options: options)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                actionError = error.localizedDescription
            }
            pendingAddCount -= 1
            await refresh()
        }
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

    /// Labels in use across all torrents, sorted case-insensitively.
    var allLabels: [String] {
        let set = Set(torrents.flatMap(\.labels))
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Labels present on at least one currently-selected torrent.
    var labelsOnSelection: [String] {
        let selected = torrents.filter { selectedTorrentIDs.contains($0.id) }
        let set = Set(selected.flatMap(\.labels))
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func addLabelToSelected(_ label: String) async {
        await applyLabelChangeToSelected { current in
            current.contains(label) ? current : current + [label]
        }
    }

    func removeLabelFromSelected(_ label: String) async {
        await applyLabelChangeToSelected { current in
            current.filter { $0 != label }
        }
    }

    /// Apply a per-torrent label transform to the current selection. Torrents
    /// whose resulting labels are identical are batched into one RPC call.
    private func applyLabelChangeToSelected(_ transform: ([String]) -> [String]) async {
        let selected = torrents.filter { selectedTorrentIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        var groups: [[String]: [Int]] = [:]
        for torrent in selected {
            let next = transform(torrent.labels)
            if next != torrent.labels {
                groups[next, default: []].append(torrent.id)
            }
        }
        guard !groups.isEmpty else { return }

        for (newLabels, ids) in groups {
            await performAction { try await self.client.setLabels(ids: ids, labels: newLabels) }
        }
        await refresh()
    }

    func setFilesWanted(torrentID: Int, fileIndices: [Int], wanted: Bool) async throws {
        if wanted {
            try await client.setFilesWanted(id: torrentID, fileIndices: fileIndices)
        } else {
            try await client.setFilesUnwanted(id: torrentID, fileIndices: fileIndices)
        }
    }

    func setFilePriority(torrentID: Int, fileIndices: [Int], priority: Int) async throws {
        try await client.setFilePriority(id: torrentID, fileIndices: fileIndices, priority: priority)
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

    func testPort() async -> Bool? {
        try? await client.testPort()
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
