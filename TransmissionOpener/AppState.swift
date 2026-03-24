import SwiftUI

@MainActor
@Observable
final class AppState {
    var status: SendStatus = .idle
    var lastFileName: String = ""

    enum SendStatus: Equatable {
        case idle
        case sending
        case success(String)
        case error(String)
    }

    func handleFile(url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "torrent" else { return }
        lastFileName = url.lastPathComponent
        status = .sending

        Task {
            do {
                let client = TransmissionClient.fromDefaults()
                let name = try await client.addTorrent(fileURL: url)
                self.status = .success(name)
            } catch {
                self.status = .error(error.localizedDescription)
            }
        }
    }
}
