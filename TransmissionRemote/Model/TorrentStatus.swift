enum TorrentStatus: Int, Codable, Sendable {
    case stopped        = 0
    case checkWait      = 1
    case checking       = 2
    case downloadWait   = 3
    case downloading    = 4
    case seedWait       = 5
    case seeding        = 6
    case unknown        = -1

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        self = TorrentStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .stopped:      "Paused"
        case .checkWait:    "Queued to verify"
        case .checking:     "Verifying"
        case .downloadWait: "Queued"
        case .downloading:  "Downloading"
        case .seedWait:     "Queued to seed"
        case .seeding:      "Seeding"
        case .unknown:      "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .stopped:      "pause.circle"
        case .checkWait:    "clock"
        case .checking:     "magnifyingglass"
        case .downloadWait: "clock"
        case .downloading:  "arrow.down.circle"
        case .seedWait:     "clock"
        case .seeding:      "arrow.up.circle"
        case .unknown:      "questionmark.circle"
        }
    }

    var isActive: Bool {
        self == .downloading || self == .seeding
    }
}
