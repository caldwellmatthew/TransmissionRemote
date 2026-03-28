import Testing
import Foundation
@testable import TransmissionRemote

@Suite("Completion Detection")
struct CompletionDetectionTests {

    @MainActor
    private func managerWithPrevious(_ percentDones: [Int: Double]) -> TorrentManager {
        let manager = TorrentManager(testing: true)
        manager.setPreviousPercentDone(percentDones)
        return manager
    }

    // MARK: - newlyCompleted

    @Test @MainActor func skipsFirstPoll() {
        let manager = TorrentManager(testing: true)
        let result = manager.newlyCompleted([makeTorrent(id: 1, percentDone: 1.0)])
        #expect(result.isEmpty)
    }

    @Test @MainActor func detectsNewCompletion() {
        let manager = managerWithPrevious([1: 0.5, 2: 0.3])
        let result = manager.newlyCompleted([
            makeTorrent(id: 1, percentDone: 1.0),
            makeTorrent(id: 2, percentDone: 0.6),
        ])
        #expect(result.map(\.id) == [1])
    }

    @Test @MainActor func doesNotRenotifyAlreadyCompleted() {
        let manager = managerWithPrevious([1: 1.0])
        let result = manager.newlyCompleted([makeTorrent(id: 1, percentDone: 1.0)])
        #expect(result.isEmpty)
    }

    @Test @MainActor func detectsMultipleCompletions() {
        let manager = managerWithPrevious([1: 0.9, 2: 0.8, 3: 0.5])
        let result = manager.newlyCompleted([
            makeTorrent(id: 1, percentDone: 1.0),
            makeTorrent(id: 2, percentDone: 1.0),
            makeTorrent(id: 3, percentDone: 0.7),
        ])
        #expect(result.map(\.id) == [1, 2])
    }

    @Test @MainActor func newTorrentAppearingComplete() {
        let manager = managerWithPrevious([1: 0.5])
        let result = manager.newlyCompleted([
            makeTorrent(id: 1, percentDone: 0.6),
            makeTorrent(id: 2, percentDone: 1.0),
        ])
        #expect(result.map(\.id) == [2])
    }

    @Test @MainActor func removedTorrentIgnored() {
        let manager = managerWithPrevious([1: 0.5, 2: 0.9])
        let result = manager.newlyCompleted([makeTorrent(id: 1, percentDone: 0.6)])
        #expect(result.isEmpty)
    }
}
