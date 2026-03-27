struct SessionStats: Decodable, Sendable {
    let activeTorrentCount: Int
    let pausedTorrentCount: Int
    let torrentCount: Int
    let downloadSpeed: Int
    let uploadSpeed: Int
}

struct SessionSettings: Decodable, Sendable {
    let speedLimitDown: Int
    let speedLimitDownEnabled: Bool
    let speedLimitUp: Int
    let speedLimitUpEnabled: Bool
    let altSpeedDown: Int
    let altSpeedUp: Int
    let altSpeedEnabled: Bool
    let altSpeedTimeEnabled: Bool
    let altSpeedTimeBegin: Int
    let altSpeedTimeEnd: Int
    let altSpeedTimeDay: Int

    enum CodingKeys: String, CodingKey {
        case speedLimitDown = "speed-limit-down"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitUp = "speed-limit-up"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeDay = "alt-speed-time-day"
    }
}
