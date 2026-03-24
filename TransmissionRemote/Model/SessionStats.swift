struct SessionStats: Decodable, Sendable {
    let activeTorrentCount: Int
    let pausedTorrentCount: Int
    let torrentCount: Int
    let downloadSpeed: Int
    let uploadSpeed: Int
}
