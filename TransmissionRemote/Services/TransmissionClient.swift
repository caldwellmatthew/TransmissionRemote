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
            arguments: ["fields": fields]
        )
        let data = try await callRPC(body: body)
        let response = try JSONDecoder().decode(TorrentGetResponse.self, from: data)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
        return response.arguments.torrents
    }

    func getTorrentDetail(id: Int) async throws -> Torrent? {
        let body: [String: Any] = [
            "method": "torrent-get",
            "arguments": [
                "ids": [id],
                "fields": Torrent.detailFields,
            ] as [String: Any],
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await callRPCRaw(body: jsonData)
        let response = try JSONDecoder().decode(TorrentGetResponse.self, from: responseData)
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
        let data = try Data(contentsOf: fileURL)
        var args = options.asArguments()
        args["metainfo"] = data.base64EncodedString()
        return try await addTorrent(arguments: args)
    }

    func addTorrent(url: String, options: TorrentAddOptions = TorrentAddOptions()) async throws -> String {
        var args = options.asArguments()
        args["filename"] = url
        return try await addTorrent(arguments: args)
    }

    private func addTorrent(arguments: [String: Any]) async throws -> String {
        let body: [String: Any] = ["method": "torrent-add", "arguments": arguments]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await callRPCRaw(body: jsonData)
        let response = try JSONDecoder().decode(TorrentAddResponse.self, from: responseData)
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
        let body: [String: Any] = [
            "method": "torrent-remove",
            "arguments": [
                "ids": ids,
                "delete-local-data": deleteLocalData,
            ] as [String: Any],
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await callRPCRaw(body: jsonData)
        let response = try JSONDecoder().decode(SimpleResponse.self, from: responseData)
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
        let body: [String: Any] = [
            "method": "torrent-set-location",
            "arguments": [
                "ids": ids,
                "location": location,
                "move": move,
            ] as [String: Any],
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await callRPCRaw(body: jsonData)
        let response = try JSONDecoder().decode(SimpleResponse.self, from: responseData)
        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }
    }

    // MARK: - Torrent Set

    func setFilesWanted(id: Int, fileIndices: [Int]) async throws {
        try await setTorrent(id: id, arguments: ["files-wanted": fileIndices])
    }

    func setFilesUnwanted(id: Int, fileIndices: [Int]) async throws {
        try await setTorrent(id: id, arguments: ["files-unwanted": fileIndices])
    }

    func setFilePriority(id: Int, fileIndices: [Int], priority: Int) async throws {
        let key: String
        switch priority {
        case -1: key = "priority-low"
        case 1:  key = "priority-high"
        default: key = "priority-normal"
        }
        try await setTorrent(id: id, arguments: [key: fileIndices])
    }

    private func setTorrent(id: Int, arguments: [String: Any]) async throws {
        var args = arguments
        args["ids"] = [id]
        let body: [String: Any] = ["method": "torrent-set", "arguments": args]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await callRPCRaw(body: jsonData)
        let response = try JSONDecoder().decode(SimpleResponse.self, from: responseData)
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
        return try await callRPCRaw(body: jsonData)
    }

    private func callRPCRaw(body: Data, retried: Bool = false) async throws -> Data {
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
            return try await callRPCRaw(body: body, retried: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TransmissionError.httpError(http.statusCode, message)
        }

        return data
    }
}

// MARK: - Request Types

private struct RPCRequest<T: Encodable & Sendable>: Encodable, Sendable {
    let method: String
    let arguments: T?
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

struct TorrentAddOptions: Sendable {
    var downloadDir: String?
    var paused: Bool = false
    var bandwidthPriority: Int = 0
    var labels: [String] = []
    var peerLimit: Int?

    func asArguments() -> [String: Any] {
        var args: [String: Any] = [:]
        if let dir = downloadDir, !dir.isEmpty { args["download-dir"] = dir }
        if paused { args["paused"] = true }
        if bandwidthPriority != 0 { args["bandwidthPriority"] = bandwidthPriority }
        if !labels.isEmpty { args["labels"] = labels }
        if let limit = peerLimit { args["peer-limit"] = limit }
        return args
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
