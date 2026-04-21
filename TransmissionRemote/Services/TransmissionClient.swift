import Foundation

actor TransmissionClient {
    let endpoint: URL
    let username: String?
    let password: String?
    private var sessionId: String?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(endpoint: URL, username: String?, password: String?) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
    }

    static let defaultEndpoint = URL(string: "http://localhost:9091/transmission/rpc")!

    static func parseEndpoint(_ serverURL: String?) -> URL {
        guard let serverURL, !serverURL.isEmpty else { return defaultEndpoint }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: ["/"])
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return defaultEndpoint
        }
        if url.path.hasSuffix("/transmission/rpc") {
            return url
        }
        return url.appendingPathComponent("transmission/rpc")
    }

    static func fromDefaults() -> TransmissionClient {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL")
        let endpoint = parseEndpoint(serverURL)

        let username = KeychainHelper.load(account: "username")
        let password = KeychainHelper.load(account: "password")
        return TransmissionClient(endpoint: endpoint, username: username, password: password)
    }

    // MARK: - Torrent List

    func getTorrents(fields: [String] = Torrent.listFields) async throws -> [Torrent] {
        let body = RPCRequest(
            method: "torrent-get",
            arguments: TorrentGetArgs(fields: fields)
        )
        let data = try await callRPC(body: body)
        let response = try decoder.decode(TorrentGetResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments.torrents
    }

    func getTorrentDetail(id: Int) async throws -> Torrent? {
        let body = RPCRequest(
            method: "torrent-get",
            arguments: TorrentGetArgs(ids: [id], fields: Torrent.detailFields)
        )
        let data = try await callRPC(body: body)
        let response = try decoder.decode(TorrentGetResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments.torrents.first
    }

    // MARK: - Session Stats

    func getSessionStats() async throws -> SessionStats {
        let body = RPCRequest(method: "session-stats", arguments: nil as [String: String]?)
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SessionStatsResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments
    }

    // MARK: - Session Info

    func getSession() async throws -> SessionInfo {
        let body = RPCRequest(
            method: "session-get",
            arguments: ["fields": ["download-dir"]] as [String: [String]]
        )
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SessionInfoResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments
    }

    // MARK: - Session Settings

    func getSessionSettings() async throws -> SessionSettings {
        let body = RPCRequest(
            method: "session-get",
            arguments: ["fields": [
                "speed-limit-down", "speed-limit-down-enabled",
                "speed-limit-up", "speed-limit-up-enabled",
                "alt-speed-down", "alt-speed-up", "alt-speed-enabled",
                "alt-speed-time-enabled", "alt-speed-time-begin",
                "alt-speed-time-end", "alt-speed-time-day",
            ]] as [String: [String]]
        )
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SessionSettingsResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments
    }

    func setSession(_ arguments: SessionSetArgs) async throws {
        let body = RPCRequest(method: "session-set", arguments: arguments)
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    // MARK: - Add Torrent

    func addTorrent(fileURL: URL, options: TorrentAddOptions = TorrentAddOptions()) async throws -> String {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }
        let fileData = try Data(contentsOf: fileURL)
        var args = options
        args.metainfo = fileData.base64EncodedString()
        return try await addTorrent(arguments: args)
    }

    func addTorrent(url: String, options: TorrentAddOptions = TorrentAddOptions()) async throws -> String {
        var args = options
        args.filename = url
        return try await addTorrent(arguments: args)
    }

    private func addTorrent(arguments: TorrentAddOptions) async throws -> String {
        let body = RPCRequest(method: "torrent-add", arguments: arguments)
        let data = try await callRPC(body: body)
        let response = try decoder.decode(TorrentAddResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments?.torrentAdded?.name
            ?? response.arguments?.torrentDuplicate?.name
            ?? "Unknown"
    }

    // MARK: - Actions

    func startTorrents(ids: [Int]) async throws {
        try await performAction("torrent-start", ids: ids)
    }

    func stopTorrents(ids: [Int]) async throws {
        try await performAction("torrent-stop", ids: ids)
    }

    func removeTorrents(ids: [Int], deleteLocalData: Bool = false) async throws {
        let body = RPCRequest(
            method: "torrent-remove",
            arguments: TorrentRemoveArgs(ids: ids, deleteLocalData: deleteLocalData)
        )
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    func verifyTorrents(ids: [Int]) async throws {
        try await performAction("torrent-verify", ids: ids)
    }

    func reannounceTorrents(ids: [Int]) async throws {
        try await performAction("torrent-reannounce", ids: ids)
    }

    func queueMoveTop(ids: [Int]) async throws {
        try await performAction("queue-move-top", ids: ids)
    }

    func queueMoveUp(ids: [Int]) async throws {
        try await performAction("queue-move-up", ids: ids)
    }

    func queueMoveDown(ids: [Int]) async throws {
        try await performAction("queue-move-down", ids: ids)
    }

    func queueMoveBottom(ids: [Int]) async throws {
        try await performAction("queue-move-bottom", ids: ids)
    }

    func setLocation(ids: [Int], location: String, move: Bool) async throws {
        let body = RPCRequest(
            method: "torrent-set-location",
            arguments: SetLocationArgs(ids: ids, location: location, move: move)
        )
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    // MARK: - Torrent Set

    func setFilesWanted(id: Int, fileIndices: [Int]) async throws {
        var args = TorrentSetArgs(ids: [id])
        args.filesWanted = fileIndices
        try await setTorrent(args)
    }

    func setFilesUnwanted(id: Int, fileIndices: [Int]) async throws {
        var args = TorrentSetArgs(ids: [id])
        args.filesUnwanted = fileIndices
        try await setTorrent(args)
    }

    func setFilePriority(id: Int, fileIndices: [Int], priority: Int) async throws {
        var args = TorrentSetArgs(ids: [id])
        switch priority {
        case -1: args.priorityLow = fileIndices
        case 1:  args.priorityHigh = fileIndices
        default: args.priorityNormal = fileIndices
        }
        try await setTorrent(args)
    }

    func setTorrentSpeedLimits(id: Int, downloadLimit: Int?, downloadLimited: Bool?,
                               uploadLimit: Int?, uploadLimited: Bool?) async throws {
        var args = TorrentSetArgs(ids: [id])
        args.downloadLimit = downloadLimit
        args.downloadLimited = downloadLimited
        args.uploadLimit = uploadLimit
        args.uploadLimited = uploadLimited
        try await setTorrent(args)
    }

    func setBandwidthPriority(ids: [Int], priority: Int) async throws {
        var args = TorrentSetArgs(ids: ids)
        args.bandwidthPriority = priority
        try await setTorrent(args)
    }

    private func setTorrent(_ arguments: TorrentSetArgs) async throws {
        let body = RPCRequest(method: "torrent-set", arguments: arguments)
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    private func performAction(_ method: String, ids: [Int]) async throws {
        let body = RPCRequest(method: method, arguments: ["ids": ids])
        let data = try await callRPC(body: body)
        let response = try decoder.decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    // MARK: - RPC Transport

    private func callRPC<T: Encodable & Sendable>(body: T) async throws -> Data {
        let jsonData = try encoder.encode(body)
        return try await sendRequest(body: jsonData)
    }

    private func sendRequest(body: Data, retried: Bool = false) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let u = username, !u.isEmpty, let p = password {
            let cred = Data("\(u):\(p)".utf8).base64EncodedString()
            req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }

        if let sid = sessionId {
            req.setValue(sid, forHTTPHeaderField: "X-Transmission-Session-Id")
        }

        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw TransmissionError.invalidResponse
        }

        if http.statusCode == 409 {
            guard let newSessionId = http.value(forHTTPHeaderField: "X-Transmission-Session-Id") else {
                throw TransmissionError.missingSessionId
            }
            guard !retried else {
                throw TransmissionError.missingSessionId
            }
            sessionId = newSessionId
            return try await sendRequest(body: body, retried: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TransmissionError.httpError(http.statusCode, message)
        }

        return data
    }
}

// MARK: - Request / Argument Types

private struct RPCRequest<T: Encodable & Sendable>: Encodable, Sendable {
    let method: String
    let arguments: T?
}

private struct TorrentGetArgs: Encodable, Sendable {
    var ids: [Int]?
    let fields: [String]
}

private struct TorrentRemoveArgs: Encodable, Sendable {
    let ids: [Int]
    let deleteLocalData: Bool

    enum CodingKeys: String, CodingKey {
        case ids
        case deleteLocalData = "delete-local-data"
    }
}

private struct SetLocationArgs: Encodable, Sendable {
    let ids: [Int]
    let location: String
    let move: Bool
}

private struct TorrentSetArgs: Encodable, Sendable {
    let ids: [Int]
    var filesWanted: [Int]?
    var filesUnwanted: [Int]?
    var priorityLow: [Int]?
    var priorityNormal: [Int]?
    var priorityHigh: [Int]?
    var downloadLimit: Int?
    var downloadLimited: Bool?
    var uploadLimit: Int?
    var uploadLimited: Bool?
    var bandwidthPriority: Int?

    enum CodingKeys: String, CodingKey {
        case ids
        case filesWanted = "files-wanted"
        case filesUnwanted = "files-unwanted"
        case priorityLow = "priority-low"
        case priorityNormal = "priority-normal"
        case priorityHigh = "priority-high"
        case downloadLimit, downloadLimited, uploadLimit, uploadLimited, bandwidthPriority
    }
}

struct TorrentAddOptions: Encodable, Sendable {
    var metainfo: String?
    var filename: String?
    var downloadDir: String?
    var paused: Bool?
    var bandwidthPriority: Int?
    var labels: [String]?
    var peerLimit: Int?

    enum CodingKeys: String, CodingKey {
        case metainfo, filename, paused, bandwidthPriority, labels
        case downloadDir = "download-dir"
        case peerLimit = "peer-limit"
    }
}

// MARK: - Response Types

private struct TorrentGetResponse: Decodable {
    let result: String
    struct Arguments: Decodable {
        let torrents: [Torrent]
    }
    let arguments: Arguments
}

private struct SessionStatsResponse: Decodable {
    let result: String
    let arguments: SessionStats
}

private struct SessionInfoResponse: Decodable {
    let result: String
    let arguments: SessionInfo
}

struct SessionSetArgs: Encodable, Sendable {
    var speedLimitDown: Int?
    var speedLimitDownEnabled: Bool?
    var speedLimitUp: Int?
    var speedLimitUpEnabled: Bool?
    var altSpeedDown: Int?
    var altSpeedUp: Int?
    var altSpeedEnabled: Bool?
    var altSpeedTimeEnabled: Bool?
    var altSpeedTimeBegin: Int?
    var altSpeedTimeEnd: Int?
    var altSpeedTimeDay: Int?

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

private struct SessionSettingsResponse: Decodable {
    let result: String
    let arguments: SessionSettings
}

struct SessionInfo: Decodable, Sendable {
    let downloadDir: String

    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
    }
}

private struct TorrentAddResponse: Decodable {
    let result: String
    let arguments: TorrentAddArgs?

    struct TorrentAddArgs: Decodable {
        let torrentAdded: TorrentInfo?
        let torrentDuplicate: TorrentInfo?

        enum CodingKeys: String, CodingKey {
            case torrentAdded = "torrent-added"
            case torrentDuplicate = "torrent-duplicate"
        }
    }

    struct TorrentInfo: Decodable {
        let id: Int?
        let name: String?
        let hashString: String?
    }
}

private struct SimpleResponse: Decodable {
    let result: String
}

// MARK: - Errors

enum TransmissionError: LocalizedError {
    case invalidResponse
    case missingSessionId
    case httpError(Int, String)
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid server response"
        case .missingSessionId:
            "Server returned 409 without session ID"
        case .httpError(let code, let msg):
            "HTTP \(code): \(msg)"
        case .rpcError(let msg):
            "RPC error: \(msg)"
        }
    }
}
