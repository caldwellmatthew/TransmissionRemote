import Foundation
@testable import TransmissionRemote

func makeTorrent(
    id: Int = 1,
    name: String = "Test Torrent",
    status: TorrentStatus = .downloading,
    percentDone: Double = 0.5,
    rateDownload: Int = 0,
    rateUpload: Int = 0,
    totalSize: Int64 = 1_000_000_000,
    eta: Int = 3600,
    error: Int = 0,
    errorString: String = "",
    downloadDir: String = "/downloads",
    addedDate: Int = 1_700_000_000,
    doneDate: Int = 0,
    uploadRatio: Double = 0.0,
    peersConnected: Int = 0,
    labels: [String] = []
) -> Torrent {
    let json: [String: Any] = [
        "id": id,
        "name": name,
        "status": status.rawValue,
        "percentDone": percentDone,
        "rateDownload": rateDownload,
        "rateUpload": rateUpload,
        "totalSize": totalSize,
        "eta": eta,
        "error": error,
        "errorString": errorString,
        "downloadDir": downloadDir,
        "addedDate": addedDate,
        "doneDate": doneDate,
        "uploadRatio": uploadRatio,
        "peersConnected": peersConnected,
        "labels": labels,
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(Torrent.self, from: data)
}
