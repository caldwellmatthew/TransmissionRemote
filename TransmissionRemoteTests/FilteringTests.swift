import Testing
import Foundation
@testable import TransmissionRemote

@Suite("Filtering")
struct FilteringTests {

    // MARK: - Helpers

    @MainActor
    private func managerWith(_ torrents: [Torrent]) -> TorrentManager {
        let manager = TorrentManager(testing: true)
        manager.setTorrents(torrents)
        return manager
    }

    private let sampleTorrents: [Torrent] = [
        makeTorrent(id: 1, name: "Downloading Active", status: .downloading, rateDownload: 1000),
        makeTorrent(id: 2, name: "Seeding Active", status: .seeding, rateUpload: 500),
        makeTorrent(id: 3, name: "Stopped", status: .stopped),
        makeTorrent(id: 4, name: "Queued", status: .downloadWait),
        makeTorrent(id: 5, name: "Seed Queued", status: .seedWait),
        makeTorrent(id: 6, name: "Error Torrent", status: .downloading, error: 1),
        makeTorrent(id: 7, name: "Idle Download", status: .downloading, rateDownload: 0),
    ]

    // MARK: - filteredTorrents

    @Test @MainActor func filterAll() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .all
        #expect(manager.filteredTorrents.count == 7)
    }

    @Test @MainActor func filterActive() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .active
        let ids = manager.filteredTorrents.map(\.id)
        #expect(ids.contains(1))
        #expect(ids.contains(2))
        #expect(!ids.contains(3))
        #expect(!ids.contains(7))
    }

    @Test @MainActor func filterDownloading() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .downloading
        let ids = manager.filteredTorrents.map(\.id)
        #expect(ids.contains(1))
        #expect(ids.contains(4))
        #expect(ids.contains(6))
        #expect(ids.contains(7))
        #expect(!ids.contains(2))
    }

    @Test @MainActor func filterSeeding() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .seeding
        let ids = manager.filteredTorrents.map(\.id)
        #expect(ids.contains(2))
        #expect(ids.contains(5))
        #expect(ids.count == 2)
    }

    @Test @MainActor func filterStopped() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .stopped
        #expect(manager.filteredTorrents.map(\.id) == [3])
    }

    @Test @MainActor func filterError() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .error
        #expect(manager.filteredTorrents.map(\.id) == [6])
    }

    @Test @MainActor func filterWithSearchText() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .all
        manager.searchText = "queued"
        let ids = manager.filteredTorrents.map(\.id)
        #expect(ids.contains(4))
        #expect(ids.contains(5))
        #expect(ids.count == 2)
    }

    @Test @MainActor func filterCombinesStatusAndSearch() {
        let manager = managerWith(sampleTorrents)
        manager.statusFilter = .downloading
        manager.searchText = "active"
        #expect(manager.filteredTorrents.map(\.id) == [1])
    }

    // MARK: - Rate totals

    @Test @MainActor func totalDownloadRate() {
        let manager = managerWith([
            makeTorrent(id: 1, rateDownload: 1000),
            makeTorrent(id: 2, rateDownload: 2000),
            makeTorrent(id: 3, rateDownload: 0),
        ])
        #expect(manager.totalDownloadRate == 3000)
    }

    @Test @MainActor func totalUploadRate() {
        let manager = managerWith([
            makeTorrent(id: 1, rateUpload: 500),
            makeTorrent(id: 2, rateUpload: 1500),
        ])
        #expect(manager.totalUploadRate == 2000)
    }

    @Test @MainActor func totalRateEmpty() {
        let manager = managerWith([])
        #expect(manager.totalDownloadRate == 0)
        #expect(manager.totalUploadRate == 0)
    }
}
