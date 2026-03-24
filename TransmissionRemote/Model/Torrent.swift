import Foundation

struct Torrent: Identifiable, Decodable, Sendable, Hashable {
    // MARK: - Core fields (always present in list view)
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

    // MARK: - Extended scalar fields (optional, fetched when requested)
    let activityDate: Int?
    let bandwidthPriority: Int?
    let comment: String?
    let corruptEver: Int64?
    let creator: String?
    let dateCreated: Int?
    let desiredAvailable: Int64?
    let downloadLimit: Int?
    let downloadLimited: Bool?
    let editDate: Int?
    let etaIdle: Int?
    let fileCount: Int?
    let group: String?
    let hashString: String?
    let haveUnchecked: Int64?
    let haveValid: Int64?
    let honorsSessionLimits: Bool?
    let isFinished: Bool?
    let isPrivate: Bool?
    let isStalled: Bool?
    let leftUntilDone: Int64?
    let magnetLink: String?
    let maxConnectedPeers: Int?
    let metadataPercentComplete: Double?
    let peerLimit: Int?
    let peersGettingFromUs: Int?
    let peersSendingToUs: Int?
    let percentComplete: Double?
    let pieceCount: Int?
    let pieceSize: Int64?
    let primaryMimeType: String?
    let queuePosition: Int?
    let recheckProgress: Double?
    let secondsDownloading: Int?
    let secondsSeeding: Int?
    let seedIdleLimit: Int?
    let seedIdleMode: Int?
    let seedRatioLimit: Double?
    let seedRatioMode: Int?
    let sequentialDownload: Bool?
    let sizeWhenDone: Int64?
    let startDate: Int?
    let torrentFile: String?
    let uploadedEver: Int64?
    let uploadLimit: Int?
    let uploadLimited: Bool?
    let webseedsSendingToUs: Int?

    // MARK: - Complex/array fields (detail view only)
    let files: [TorrentFile]?
    let fileStats: [TorrentFileStat]?
    let trackers: [TorrentTracker]?
    let trackerStats: [TorrentTrackerStat]?
    let peers: [TorrentPeer]?

    // MARK: - Field lists for RPC requests

    static let listFields: [String] = [
        "id", "name", "status", "percentDone", "rateDownload", "rateUpload",
        "totalSize", "eta", "error", "errorString", "downloadDir",
        "addedDate", "doneDate", "uploadRatio", "peersConnected", "labels",
        "activityDate", "bandwidthPriority", "comment", "corruptEver",
        "creator", "dateCreated", "desiredAvailable", "downloadLimit",
        "downloadLimited", "editDate", "etaIdle", "fileCount", "group",
        "hashString", "haveUnchecked", "haveValid", "honorsSessionLimits",
        "isFinished", "isPrivate", "isStalled", "leftUntilDone",
        "magnetLink", "maxConnectedPeers", "metadataPercentComplete",
        "peerLimit", "peersGettingFromUs", "peersSendingToUs",
        "percentComplete", "pieceCount", "pieceSize", "primaryMimeType",
        "queuePosition", "recheckProgress", "secondsDownloading",
        "secondsSeeding", "seedIdleLimit", "seedIdleMode", "seedRatioLimit",
        "seedRatioMode", "sequentialDownload", "sizeWhenDone", "startDate",
        "torrentFile", "uploadedEver", "uploadLimit", "uploadLimited",
        "webseedsSendingToUs",
    ]

    static let detailFields: [String] = listFields + [
        "files", "fileStats", "trackers", "trackerStats", "peers",
    ]
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

struct TorrentPeer: Decodable, Sendable, Hashable {
    let address: String
    let clientName: String
    let flagStr: String
    let port: Int
    let rateToClient: Int
    let rateToPeer: Int
    let progress: Double
}
