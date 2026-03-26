import Foundation

actor TransmissionClient {
    let endpoint: URL
    let username: String?
    let password: String?
    private var sessionId: String?

    init(endpoint: URL, username: String?, password: String?) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
    }

    static func fromDefaults() -> TransmissionClient {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:9091"
        let trimmed = serverURL.hasSuffix("/")
            ? String(serverURL.dropLast())
            : serverURL
        let urlString = trimmed.hasSuffix("/transmission/rpc")
            ? trimmed
            : trimmed + "/transmission/rpc"
        let endpoint = URL(string: urlString)!

        let username = UserDefaults.standard.string(forKey: "username")
        let password = UserDefaults.standard.string(forKey: "password")
        return TransmissionClient(endpoint: endpoint, username: username, password: password)
    }

    // MARK: - Torrent List

    func getTorrents(fields: [String] = Torrent.listFields) async throws -> [Torrent] {
        let body = RPCRequest(
            method: "torrent-get",
            arguments: TorrentGetArgs(fields: fields)
        )
        let data = try await callRPC(body: body)
        let response = try JSONDecoder().decode(TorrentGetResponse.self, from: data)
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
        let response = try JSONDecoder().decode(TorrentGetResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments.torrents.first
    }

    // MARK: - Session Stats

    func getSessionStats() async throws -> SessionStats {
        let body = RPCRequest(method: "session-stats", arguments: nil as [String: String]?)
        let data = try await callRPC(body: body)
        let response = try JSONDecoder().decode(SessionStatsResponse.self, from: data)
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
        let response = try JSONDecoder().decode(SessionInfoResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments
    }

    // MARK: - Add Torrent

    func addTorrent(fileURL: URL, options: TorrentAddOptions = TorrentAddOptions()) async throws -> String {
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
        let response = try JSONDecoder().decode(TorrentAddResponse.self, from: data)
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
        let response = try JSONDecoder().decode(SimpleResponse.self, from: data)
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

    func setLocation(ids: [Int], location: String, move: Bool) async throws {
        let body = RPCRequest(
            method: "torrent-set-location",
            arguments: SetLocationArgs(ids: ids, location: location, move: move)
        )
        let data = try await callRPC(body: body)
        let response = try JSONDecoder().decode(SimpleResponse.self, from: data)
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

    private func setTorrent(_ arguments: TorrentSetArgs) async throws {
        let body = RPCRequest(method: "torrent-set", arguments: arguments)
        let data = try await callRPC(body: body)
        let response = try JSONDecoder().decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    private func performAction(_ method: String, ids: [Int]) async throws {
        let body = RPCRequest(method: method, arguments: ["ids": ids])
        let data = try await callRPC(body: body)
        let response = try JSONDecoder().decode(SimpleResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    // MARK: - RPC Transport

    private func callRPC<T: Encodable & Sendable>(body: T) async throws -> Data {
        let jsonData = try JSONEncoder().encode(body)
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

    enum CodingKeys: String, CodingKey {
        case ids
        case filesWanted = "files-wanted"
        case filesUnwanted = "files-unwanted"
        case priorityLow = "priority-low"
        case priorityNormal = "priority-normal"
        case priorityHigh = "priority-high"
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
