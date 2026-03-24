import Foundation

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatRate(_ bytesPerSec: Int, showZero: Bool = false) -> String {
    guard bytesPerSec > 0 else { return showZero ? "0 KB/s" : "" }
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

func formatDate(_ unixTimestamp: Int) -> String {
    guard unixTimestamp > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: .now)
}

func formatDuration(_ totalSeconds: Int) -> String {
    guard totalSeconds > 0 else { return "" }
    let d = totalSeconds / 86400
    let h = (totalSeconds % 86400) / 3600
    let m = (totalSeconds % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

func formatPriority(_ priority: Int) -> String {
    switch priority {
    case -1: "Low"
    case 1: "High"
    default: "Normal"
    }
}
