import Foundation

@MainActor private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

@MainActor private let rateFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    return f
}()

@MainActor private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

@MainActor
func formatBytes(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes)
}

@MainActor
func formatRate(_ bytesPerSec: Int, showZero: Bool = false) -> String {
    guard bytesPerSec > 0 else { return showZero ? "0 KB/s" : "" }
    return rateFormatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
}

func formatETA(_ seconds: Int) -> String {
    guard seconds >= 0 else { return "" }
    if seconds == 0 { return "" }

    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60

    if h >= 24 {
        let days = h / 24
        return "\(days)d \(h % 24)h"
    } else if h > 0 {
        return "\(h)h \(m)m \(s)s"
    } else if m > 0 {
        return "\(m)m \(s)s"
    } else {
        return "\(s)s"
    }
}

func formatAbsoluteDate(_ unixTimestamp: Int) -> String {
    guard unixTimestamp > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))
    return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.defaultDigits))
}

@MainActor
func formatRelativeDate(_ unixTimestamp: Int) -> String {
    guard unixTimestamp > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))
    return relativeDateFormatter.localizedString(for: date, relativeTo: .now)
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

/// Title for the remove confirmation. Names the torrent outright when only one is
/// selected, so the user can see what they're about to remove; falls back to a
/// count when the selection is larger or the selected torrent is no longer known.
func removeConfirmationTitle(singleName: String?, count: Int) -> String {
    if let singleName {
        return "Remove \u{201C}\(singleName)\u{201D}?"
    }
    return "Remove \(count) torrent\(count == 1 ? "" : "s")?"
}
