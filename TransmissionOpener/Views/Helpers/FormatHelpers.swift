import Foundation

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatRate(_ bytesPerSec: Int) -> String {
    guard bytesPerSec > 0 else { return "" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
}

func formatETA(_ seconds: Int) -> String {
    guard seconds >= 0 else { return "" }
    if seconds == 0 { return "" }

    let h = seconds / 3600
    let m = (seconds % 3600) / 60

    if h > 24 {
        let days = h / 24
        return "\(days)d \(h % 24)h"
    } else if h > 0 {
        return "\(h)h \(m)m"
    } else if m > 0 {
        return "\(m)m"
    } else {
        return "\(seconds)s"
    }
}
