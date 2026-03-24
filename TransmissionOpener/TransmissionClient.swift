import Foundation

struct TransmissionClient: Sendable {
    let endpoint: URL
    let username: String?
    let password: String?

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

    func addTorrent(fileURL: URL) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        let metainfo = data.base64EncodedString()

        let request = RPCRequest(
            method: "torrent-add",
            arguments: TorrentAddArgs(metainfo: metainfo)
        )
        let responseData = try await callRPC(body: request)
        let response = try JSONDecoder().decode(RPCResponse.self, from: responseData)

        guard response.result == "success" else {
            throw TransmissionError.rpcError(response.result)
        }

        return response.arguments?.torrentAdded?.name
            ?? response.arguments?.torrentDuplicate?.name
            ?? fileURL.lastPathComponent
    }

    private func callRPC<T: Encodable & Sendable>(
        body: T,
        sessionId: String? = nil
    ) async throws -> Data {
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

        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw TransmissionError.invalidResponse
        }

        if http.statusCode == 409 {
            guard let newSessionId = http.value(forHTTPHeaderField: "X-Transmission-Session-Id") else {
                throw TransmissionError.missingSessionId
            }
            return try await callRPC(body: body, sessionId: newSessionId)
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
    let arguments: T
}

private struct TorrentAddArgs: Encodable, Sendable {
    let metainfo: String
}

// MARK: - Response Types

private struct RPCResponse: Decodable {
    let result: String
    let arguments: RPCResponseArgs?
}

private struct RPCResponseArgs: Decodable {
    let torrentAdded: TorrentInfo?
    let torrentDuplicate: TorrentInfo?

    enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent-added"
        case torrentDuplicate = "torrent-duplicate"
    }
}

private struct TorrentInfo: Decodable {
    let id: Int?
    let name: String?
    let hashString: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hashString = "hashString"
    }
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
