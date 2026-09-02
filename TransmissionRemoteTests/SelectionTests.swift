import Testing
import Foundation
@testable import TransmissionRemote

@Suite("Selection")
struct SelectionTests {

    @MainActor
    private func managerWith(_ torrents: [Torrent]) -> TorrentManager {
        let manager = TorrentManager(testing: true)
        manager.setTorrents(torrents)
        return manager
    }

    /// IDs are deliberately not 0/1/2 so a lookup that indexes into the array
    /// instead of matching on `id` fails these tests.
    private let sampleTorrents: [Torrent] = [
        makeTorrent(id: 41, name: "First"),
        makeTorrent(id: 17, name: "Second"),
        makeTorrent(id: 88, name: "Third"),
    ]

    @Test @MainActor func singleSelectionResolvesByIDNotPosition() {
        let manager = managerWith(sampleTorrents)
        manager.selectedTorrentIDs = [88]
        #expect(manager.singleSelectedTorrent?.name == "Third")
    }

    @Test @MainActor func staleSelectionHasNoSingleTorrent() {
        let manager = managerWith(sampleTorrents)
        manager.selectedTorrentIDs = [99]
        #expect(manager.singleSelectedTorrent == nil)
    }
}
