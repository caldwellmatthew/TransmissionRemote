import Testing
import Foundation
@testable import TransmissionRemote

@Suite("Model Decoding")
struct ModelDecodingTests {

    // MARK: - Torrent

    @Test func torrentCoreFields() throws {
        let json: [String: Any] = [
            "id": 42,
            "name": "ubuntu-24.04.iso",
            "status": 4,
            "percentDone": 0.75,
            "rateDownload": 1_500_000,
            "rateUpload": 250_000,
            "totalSize": 4_700_000_000,
            "eta": 1800,
            "error": 0,
            "errorString": "",
            "downloadDir": "/home/user/Downloads",
            "addedDate": 1_700_000_000,
            "doneDate": 0,
            "uploadRatio": 1.5,
            "peersConnected": 12,
            "labels": ["linux", "iso"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let torrent = try JSONDecoder().decode(Torrent.self, from: data)

        #expect(torrent.id == 42)
        #expect(torrent.name == "ubuntu-24.04.iso")
        #expect(torrent.status == .downloading)
        #expect(torrent.percentDone == 0.75)
        #expect(torrent.rateDownload == 1_500_000)
        #expect(torrent.rateUpload == 250_000)
        #expect(torrent.totalSize == 4_700_000_000)
        #expect(torrent.eta == 1800)
        #expect(torrent.error == 0)
        #expect(torrent.errorString == "")
        #expect(torrent.downloadDir == "/home/user/Downloads")
        #expect(torrent.addedDate == 1_700_000_000)
        #expect(torrent.doneDate == 0)
        #expect(torrent.uploadRatio == 1.5)
        #expect(torrent.peersConnected == 12)
        #expect(torrent.labels == ["linux", "iso"])
    }

    @Test func torrentOptionalFieldsNilWhenAbsent() {
        let torrent = makeTorrent()
        #expect(torrent.files == nil)
        #expect(torrent.fileStats == nil)
        #expect(torrent.trackers == nil)
        #expect(torrent.trackerStats == nil)
        #expect(torrent.peers == nil)
        #expect(torrent.hashString == nil)
        #expect(torrent.comment == nil)
    }

    @Test func torrentWithFiles() throws {
        let json: [String: Any] = [
            "id": 1, "name": "test", "status": 4, "percentDone": 0.5,
            "rateDownload": 0, "rateUpload": 0, "totalSize": 1000,
            "eta": -1, "error": 0, "errorString": "", "downloadDir": "/tmp",
            "addedDate": 0, "doneDate": 0, "uploadRatio": 0.0,
            "peersConnected": 0, "labels": [] as [String],
            "files": [
                ["name": "file1.txt", "length": 500, "bytesCompleted": 250],
                ["name": "file2.txt", "length": 500, "bytesCompleted": 500],
            ],
            "fileStats": [
                ["wanted": true, "priority": 0],
                ["wanted": false, "priority": 1],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let torrent = try JSONDecoder().decode(Torrent.self, from: data)

        #expect(torrent.files?.count == 2)
        #expect(torrent.files?[0].name == "file1.txt")
        #expect(torrent.files?[0].length == 500)
        #expect(torrent.files?[0].bytesCompleted == 250)
        #expect(torrent.fileStats?.count == 2)
        #expect(torrent.fileStats?[0].wanted == true)
        #expect(torrent.fileStats?[1].priority == 1)
    }

    // MARK: - SessionStats

    @Test func sessionStats() throws {
        let json: [String: Any] = [
            "activeTorrentCount": 5,
            "pausedTorrentCount": 3,
            "torrentCount": 8,
            "downloadSpeed": 1_500_000,
            "uploadSpeed": 250_000,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let stats = try JSONDecoder().decode(SessionStats.self, from: data)

        #expect(stats.activeTorrentCount == 5)
        #expect(stats.pausedTorrentCount == 3)
        #expect(stats.torrentCount == 8)
        #expect(stats.downloadSpeed == 1_500_000)
        #expect(stats.uploadSpeed == 250_000)
    }

    // MARK: - SessionSettings

    @Test func sessionSettingsHyphenatedKeys() throws {
        let json: [String: Any] = [
            "speed-limit-down": 1000,
            "speed-limit-down-enabled": true,
            "speed-limit-up": 500,
            "speed-limit-up-enabled": false,
            "alt-speed-down": 200,
            "alt-speed-up": 100,
            "alt-speed-enabled": true,
            "alt-speed-time-enabled": false,
            "alt-speed-time-begin": 540,
            "alt-speed-time-end": 1080,
            "alt-speed-time-day": 127,
            "peer-port": 51413,
            "peer-port-random-on-start": false,
            "port-forwarding-enabled": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let settings = try JSONDecoder().decode(SessionSettings.self, from: data)

        #expect(settings.speedLimitDown == 1000)
        #expect(settings.speedLimitDownEnabled == true)
        #expect(settings.speedLimitUp == 500)
        #expect(settings.speedLimitUpEnabled == false)
        #expect(settings.altSpeedDown == 200)
        #expect(settings.altSpeedUp == 100)
        #expect(settings.altSpeedEnabled == true)
        #expect(settings.altSpeedTimeEnabled == false)
        #expect(settings.altSpeedTimeBegin == 540)
        #expect(settings.altSpeedTimeEnd == 1080)
        #expect(settings.altSpeedTimeDay == 127)
        #expect(settings.peerPort == 51413)
        #expect(settings.peerPortRandomOnStart == false)
        #expect(settings.portForwardingEnabled == true)
    }

    // MARK: - TorrentTracker

    @Test func torrentTracker() throws {
        let json: [String: Any] = [
            "id": 1,
            "announce": "https://tracker.example.com/announce",
            "sitename": "example.com",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let tracker = try JSONDecoder().decode(TorrentTracker.self, from: data)

        #expect(tracker.id == 1)
        #expect(tracker.announce == "https://tracker.example.com/announce")
        #expect(tracker.sitename == "example.com")
    }

    // MARK: - TorrentTrackerStat

    @Test func torrentTrackerStat() throws {
        let json: [String: Any] = [
            "id": 1,
            "host": "tracker.example.com",
            "lastAnnounceSucceeded": true,
            "seederCount": 50,
            "leecherCount": 10,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let stat = try JSONDecoder().decode(TorrentTrackerStat.self, from: data)

        #expect(stat.id == 1)
        #expect(stat.lastAnnounceSucceeded == true)
        #expect(stat.seederCount == 50)
        #expect(stat.leecherCount == 10)
    }

    // MARK: - TorrentPeer

    @Test func torrentPeer() throws {
        let json: [String: Any] = [
            "address": "192.168.1.100",
            "clientName": "Transmission 4.0",
            "flagStr": "DUEK",
            "port": 51413,
            "rateToClient": 100_000,
            "rateToPeer": 50_000,
            "progress": 0.85,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let peer = try JSONDecoder().decode(TorrentPeer.self, from: data)

        #expect(peer.address == "192.168.1.100")
        #expect(peer.port == 51413)
        #expect(peer.clientName == "Transmission 4.0")
        #expect(peer.progress == 0.85)
    }

    @Test func torrentPeerComputedId() throws {
        let json: [String: Any] = [
            "address": "10.0.0.1",
            "clientName": "Test",
            "flagStr": "",
            "port": 6881,
            "rateToClient": 0,
            "rateToPeer": 0,
            "progress": 0.0,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let peer = try JSONDecoder().decode(TorrentPeer.self, from: data)

        #expect(peer.id == "10.0.0.1:6881")
    }
}
