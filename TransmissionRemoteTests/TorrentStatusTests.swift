import Testing
import Foundation
@testable import TransmissionRemote

@Suite("TorrentStatus")
struct TorrentStatusTests {

    // MARK: - Decoding

    private struct StatusWrapper: Decodable {
        let status: TorrentStatus
    }

    @Test(arguments: [
        (0, TorrentStatus.stopped),
        (1, TorrentStatus.checkWait),
        (2, TorrentStatus.checking),
        (3, TorrentStatus.downloadWait),
        (4, TorrentStatus.downloading),
        (5, TorrentStatus.seedWait),
        (6, TorrentStatus.seeding),
    ])
    func decodesKnownValues(rawValue: Int, expected: TorrentStatus) throws {
        let json = #"{"status": \#(rawValue)}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StatusWrapper.self, from: json)
        #expect(decoded.status == expected)
    }

    @Test func decodesUnknownAsUnknown() throws {
        let json = #"{"status": 99}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StatusWrapper.self, from: json)
        #expect(decoded.status == .unknown)
    }

    // MARK: - isActive

    @Test func isActiveForDownloading() {
        #expect(TorrentStatus.downloading.isActive)
    }

    @Test func isActiveForSeeding() {
        #expect(TorrentStatus.seeding.isActive)
    }

    @Test(arguments: [
        TorrentStatus.stopped, .checkWait, .checking, .downloadWait, .seedWait, .unknown,
    ])
    func isNotActive(status: TorrentStatus) {
        #expect(!status.isActive)
    }
}
