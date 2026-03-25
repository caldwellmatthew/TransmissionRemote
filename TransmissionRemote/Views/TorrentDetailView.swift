import SwiftUI

struct TorrentDetailView: View {
    let torrentID: Int
    @Environment(TorrentManager.self) private var manager
    @State private var torrent: Torrent?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let torrent {
                TabView {
                    InfoTab(torrent: torrent)
                        .tabItem { Label("Info", systemImage: "info.circle") }

                    FilesTab(torrent: torrent)
                        .tabItem { Label("Files", systemImage: "doc.on.doc") }

                    TrackersTab(torrent: torrent)
                        .tabItem { Label("Trackers", systemImage: "antenna.radiowaves.left.and.right") }

                    PeersTab(torrent: torrent)
                        .tabItem { Label("Peers", systemImage: "person.2") }
                }
                .navigationTitle(torrent.name)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await refresh()
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await refresh()
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func refresh() async {
        torrent = await manager.getTorrentDetail(id: torrentID)
    }
}

// MARK: - Info Tab

private struct InfoTab: View {
    let torrent: Torrent

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                section("General") {
                    row("Name", torrent.name)
                    row("Status", torrent.status.label)
                    row("Progress", "\(Int(torrent.percentDone * 100))%")
                    row("Size", formatBytes(torrent.totalSize))
                    if let sizeWhenDone = torrent.sizeWhenDone {
                        row("Size When Done", formatBytes(sizeWhenDone))
                    }
                    if let uploaded = torrent.uploadedEver {
                        row("Uploaded", formatBytes(uploaded))
                    }
                    row("Ratio", torrent.uploadRatio >= 0 ? String(format: "%.2f", torrent.uploadRatio) : "—")
                    if let priority = torrent.bandwidthPriority {
                        row("Priority", formatPriority(priority))
                    }
                }

                Divider()

                section("Transfer") {
                    row("Download", formatRate(torrent.rateDownload, showZero: true))
                    row("Upload", formatRate(torrent.rateUpload, showZero: true))
                    if torrent.eta > 0 { row("ETA", formatETA(torrent.eta)) }
                    row("Peers", "\(torrent.peersConnected)")
                    if let sending = torrent.peersSendingToUs {
                        row("Seeds → Us", "\(sending)")
                    }
                    if let getting = torrent.peersGettingFromUs {
                        row("Us → Peers", "\(getting)")
                    }
                }

                Divider()

                section("Time") {
                    row("Added", formatDate(torrent.addedDate))
                    if torrent.doneDate > 0 { row("Completed", formatDate(torrent.doneDate)) }
                    if let activity = torrent.activityDate, activity > 0 {
                        row("Last Active", formatDate(activity))
                    }
                    if let dl = torrent.secondsDownloading, dl > 0 {
                        row("Time Downloading", formatDuration(dl))
                    }
                    if let seed = torrent.secondsSeeding, seed > 0 {
                        row("Time Seeding", formatDuration(seed))
                    }
                }

                Divider()

                section("Storage") {
                    row("Location", torrent.downloadDir)
                    if let hash = torrent.hashString { row("Hash", hash) }
                    if let pieces = torrent.pieceCount, let size = torrent.pieceSize {
                        row("Pieces", "\(pieces) × \(formatBytes(size))")
                    }
                    if let files = torrent.fileCount { row("Files", "\(files)") }
                }

                if torrent.comment != nil || torrent.creator != nil || !torrent.labels.isEmpty {
                    Divider()

                    section("Metadata") {
                        if let comment = torrent.comment, !comment.isEmpty {
                            row("Comment", comment)
                        }
                        if let creator = torrent.creator, !creator.isEmpty {
                            row("Creator", creator)
                        }
                        if !torrent.labels.isEmpty {
                            row("Labels", torrent.labels.joined(separator: ", "))
                        }
                    }
                }

                if torrent.error != 0 {
                    Divider()

                    section("Error") {
                        GridRow {
                            Text("Message")
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(torrent.errorString)
                                .foregroundStyle(.red)
                                .gridColumnAlignment(.leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            Text(title)
                .font(.headline)
                .gridCellColumns(2)
                .padding(.top, 4)
        }
        content()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .gridColumnAlignment(.leading)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Files Tab

private struct FileRow: Identifiable {
    let id: Int
    let name: String
    let size: Int64
    let progress: Double
    let wanted: Bool
    let priority: Int
}

private struct FilesTab: View {
    let torrent: Torrent

    private var fileRows: [FileRow] {
        guard let files = torrent.files else { return [] }
        let stats = torrent.fileStats ?? []
        return files.enumerated().map { i, file in
            let stat = i < stats.count ? stats[i] : nil
            let progress = file.length > 0 ? Double(file.bytesCompleted) / Double(file.length) : 0
            return FileRow(
                id: i,
                name: (file.name as NSString).lastPathComponent,
                size: file.length,
                progress: progress,
                wanted: stat?.wanted ?? true,
                priority: stat?.priority ?? 0
            )
        }
    }

    var body: some View {
        Table(of: FileRow.self) {
            TableColumn("Name") { row in
                Text(row.name)
                    .lineLimit(1)
                    .help(row.name)
            }
            .width(min: 200)

            TableColumn("Size") { row in
                Text(formatBytes(row.size))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Progress") { row in
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.tertiary)
                        Capsule().fill(.tint).scaleEffect(x: row.progress, anchor: .leading)
                    }
                    .frame(height: 6)
                    Text("\(Int(row.progress * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("Wanted") { row in
                Image(systemName: row.wanted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.wanted ? .green : .secondary)
            }
            .width(min: 40, ideal: 55)

            TableColumn("Priority") { row in
                Text(formatPriority(row.priority))
            }
            .width(min: 50, ideal: 70)
        } rows: {
            ForEach(fileRows) { row in
                TableRow(row)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Trackers Tab

private struct TrackersTab: View {
    let torrent: Torrent

    private var trackerRows: [TorrentTrackerStat] {
        torrent.trackerStats ?? []
    }

    var body: some View {
        if trackerRows.isEmpty {
            ContentUnavailableView("No Tracker Data", systemImage: "antenna.radiowaves.left.and.right")
        } else {
        Table(trackerRows) {
            TableColumn("Host") { stat in
                Text(stat.host)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 500)

            TableColumn("Status") { stat in
                Image(systemName: stat.lastAnnounceSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(stat.lastAnnounceSucceeded ? .green : .red)
            }
            .width(min: 40, ideal: 55)

            TableColumn("Seeders") { stat in
                Text(stat.seederCount >= 0 ? "\(stat.seederCount)" : "?")
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60)

            TableColumn("Leechers") { stat in
                Text(stat.leecherCount >= 0 ? "\(stat.leecherCount)" : "?")
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60)
        }
        .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Peers Tab

private struct PeersTab: View {
    let torrent: Torrent

    private var peerRows: [TorrentPeer] {
        torrent.peers ?? []
    }

    var body: some View {
        if peerRows.isEmpty {
            ContentUnavailableView("No Peers Connected", systemImage: "person.2")
        } else {
        Table(peerRows) {
            TableColumn("Address") { peer in
                Text(peer.address)
                    .monospaced()
            }
            .width(min: 100, ideal: 130)

            TableColumn("Client") { peer in
                Text(peer.clientName)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 500)

            TableColumn("Progress") { peer in
                Text("\(Int(peer.progress * 100))%")
                    .monospacedDigit()
            }
            .width(min: 40, ideal: 50)

            TableColumn("↓ Down") { peer in
                Text(formatRate(peer.rateToClient))
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 70)

            TableColumn("↑ Up") { peer in
                Text(formatRate(peer.rateToPeer))
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 70)

            TableColumn("Flags") { peer in
                Text(peer.flagStr)
                    .monospaced()
            }
            .width(min: 30, ideal: 45)
        }
        .scrollIndicators(.hidden)
        }
    }
}
