import Foundation

struct Torrent: Identifiable, Decodable, Sendable, Hashable {
    let id: Int
    let name: String
    let status: TorrentStatus
    let percentDone: Double
    let rateDownload: Int
    let rateUpload: Int
    let totalSize: Int64
    let eta: Int
    let error: Int
    let errorString: String
    let downloadDir: String
    let addedDate: Int
    let doneDate: Int
    let uploadRatio: Double
    let peersConnected: Int
    let labels: [String]

    // Detail fields (nil when fetched with list fields only)
    let files: [TorrentFile]?
    let fileStats: [TorrentFileStat]?
    let trackers: [TorrentTracker]?
    let trackerStats: [TorrentTrackerStat]?

    static let listFields: [String] = [
        "id", "name", "status", "percentDone", "rateDownload", "rateUpload",
        "totalSize", "eta", "error", "errorString", "downloadDir",
        "addedDate", "doneDate", "uploadRatio", "peersConnected", "labels",
    ]

    static let detailFields: [String] = listFields + [
        "files", "fileStats", "trackers", "trackerStats",
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        status = try c.decode(TorrentStatus.self, forKey: .status)
        percentDone = try c.decode(Double.self, forKey: .percentDone)
        rateDownload = try c.decode(Int.self, forKey: .rateDownload)
        rateUpload = try c.decode(Int.self, forKey: .rateUpload)
        totalSize = try c.decode(Int64.self, forKey: .totalSize)
        eta = try c.decode(Int.self, forKey: .eta)
        error = try c.decode(Int.self, forKey: .error)
        errorString = try c.decode(String.self, forKey: .errorString)
        downloadDir = try c.decode(String.self, forKey: .downloadDir)
        addedDate = try c.decode(Int.self, forKey: .addedDate)
        doneDate = try c.decode(Int.self, forKey: .doneDate)
        uploadRatio = try c.decode(Double.self, forKey: .uploadRatio)
        peersConnected = try c.decode(Int.self, forKey: .peersConnected)
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        files = try c.decodeIfPresent([TorrentFile].self, forKey: .files)
        fileStats = try c.decodeIfPresent([TorrentFileStat].self, forKey: .fileStats)
        trackers = try c.decodeIfPresent([TorrentTracker].self, forKey: .trackers)
        trackerStats = try c.decodeIfPresent([TorrentTrackerStat].self, forKey: .trackerStats)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, percentDone, rateDownload, rateUpload
        case totalSize, eta, error, errorString, downloadDir
        case addedDate, doneDate, uploadRatio, peersConnected, labels
        case files, fileStats, trackers, trackerStats
    }
}

struct TorrentFile: Decodable, Sendable, Hashable {
    let name: String
    let length: Int64
    let bytesCompleted: Int64
}

struct TorrentFileStat: Decodable, Sendable, Hashable {
    let wanted: Bool
    let priority: Int
}

struct TorrentTracker: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    let announce: String
    let sitename: String
}

struct TorrentTrackerStat: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    let host: String
    let lastAnnounceSucceeded: Bool
    let seederCount: Int
    let leecherCount: Int
}
