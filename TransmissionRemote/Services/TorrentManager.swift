import Foundation

@MainActor
@Observable
final class TorrentManager {
    private(set) var torrents: [Torrent] = []
    private(set) var sessionStats: SessionStats?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var errorMessage: String?

    var selectedTorrentIDs: Set<Int> = []
    var searchText: String = ""
    var statusFilter: StatusFilter = .all

    private var client: TransmissionClient
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5.0

    enum ConnectionState {
        case disconnected, connecting, connected, error
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, downloading, seeding, stopped, error

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:         "All"
            case .downloading: "Downloading"
            case .seeding:     "Seeding"
            case .stopped:     "Stopped"
            case .error:       "Errors"
            }
        }

        var systemImage: String {
            switch self {
            case .all:         "tray.full"
            case .downloading: "arrow.down.circle"
            case .seeding:     "arrow.up.circle"
            case .stopped:     "stop.circle"
            case .error:       "exclamationmark.triangle"
            }
        }
    }

    var filteredTorrents: [Torrent] {
        var result = torrents

        switch statusFilter {
        case .all:
            break
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
            torrents = try await fetchedTorrents
            sessionStats = try await fetchedStats
            connectionState = .connected
            errorMessage = nil
        } catch {
            connectionState = .error
            errorMessage = error.localizedDescription
        }
    }

    func reconnect() {
        stopPolling()
        client = TransmissionClient.fromDefaults()
        connectionState = .disconnected
        startPolling()
    }

    // MARK: - Actions

    func addTorrent(fileURL: URL) async throws -> String {
        let name = try await client.addTorrent(fileURL: fileURL)
        await refresh()
        return name
    }

    func addTorrent(url: String) async throws -> String {
        let name = try await client.addTorrent(url: url)
        await refresh()
        return name
    }

    func startSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        try? await client.startTorrents(ids: ids)
        await refresh()
    }

    func stopSelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        try? await client.stopTorrents(ids: ids)
        await refresh()
    }

    func removeSelected(deleteData: Bool) async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        try? await client.removeTorrents(ids: ids, deleteLocalData: deleteData)
        selectedTorrentIDs.removeAll()
        await refresh()
    }

    func verifySelected() async {
        let ids = Array(selectedTorrentIDs)
        guard !ids.isEmpty else { return }
        try? await client.verifyTorrents(ids: ids)
        await refresh()
    }
}
