import SwiftUI

struct TorrentDetailView: View {
    let torrentID: Int
    @Environment(TorrentManager.self) private var manager
    @State private var torrent: Torrent?
    @AppStorage("pollInterval") private var pollInterval: Double = 5.0
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let torrent {
                TabView {
                    InfoTab(torrent: torrent)
                        .tabItem { Label("Info", systemImage: "info.circle") }

                    FilesTab(torrent: torrent, torrentID: torrentID, onChanged: refresh)
                        .tabItem { Label("Files", systemImage: "doc.on.doc") }

                    TrackersTab(torrent: torrent)
                        .tabItem { Label("Trackers", systemImage: "antenna.radiowaves.left.and.right") }

                    PeersTab(torrent: torrent)
                        .tabItem { Label("Peers", systemImage: "person.2") }
                }
                .navigationTitle(torrent.name)
            } else if loadFailed {
                ContentUnavailableView(
                    "Unable to Load Torrent",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Could not fetch torrent details from the server.")
                )
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    private func refresh() async {
        let detail = await manager.getTorrentDetail(id: torrentID)
        if let detail {
            torrent = detail
            loadFailed = false
        } else if torrent == nil {
            loadFailed = true
        }
    }
}

// MARK: - Info Tab

private struct InfoTab: View {
    let torrent: Torrent
    @Environment(TorrentManager.self) private var manager
    @State private var dlLimited = false
    @State private var dlLimit = 0
    @State private var ulLimited = false
    @State private var ulLimit = 0
    @State private var limitsLoaded = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Name") {
                        Text(torrent.name)
                            .textSelection(.enabled)
                    }

                    Section("General") {
                        LabeledContent("Status", value: torrent.status.label)
                        LabeledContent("Progress", value: "\(Int(torrent.percentDone * 100))%")
                        LabeledContent("Size", value: formatBytes(torrent.totalSize))
                        if let sizeWhenDone = torrent.sizeWhenDone {
                            LabeledContent("Size When Done", value: formatBytes(sizeWhenDone))
                        }
                        if let uploaded = torrent.uploadedEver {
                            LabeledContent("Uploaded", value: formatBytes(uploaded))
                        }
                        LabeledContent("Ratio", value: torrent.uploadRatio >= 0 ? String(format: "%.2f", torrent.uploadRatio) : "—")
                        if let priority = torrent.bandwidthPriority {
                            LabeledContent("Priority", value: formatPriority(priority))
                        }
                    }

                    Section("Time") {
                        LabeledContent("Added") { dateText(torrent.addedDate) }
                        if torrent.doneDate > 0 {
                            LabeledContent("Completed") { dateText(torrent.doneDate) }
                        }
                        if let activity = torrent.activityDate, activity > 0 {
                            LabeledContent("Last Active") { dateText(activity) }
                        }
                        if let dl = torrent.secondsDownloading, dl > 0 {
                            LabeledContent("Time Downloading", value: formatDuration(dl))
                        }
                        if let seed = torrent.secondsSeeding, seed > 0 {
                            LabeledContent("Time Seeding", value: formatDuration(seed))
                        }
                    }

                }
                .formStyle(.grouped)
                .scrollDisabled(true)

                Form {
                    Section("Transfer") {
                        LabeledContent("Download", value: formatRate(torrent.rateDownload, showZero: true))
                        LabeledContent("Upload", value: formatRate(torrent.rateUpload, showZero: true))
                        if torrent.eta > 0 {
                            LabeledContent("ETA", value: formatETA(torrent.eta))
                        }
                        LabeledContent("Peers", value: "\(torrent.peersConnected)")
                        if let sending = torrent.peersSendingToUs {
                            LabeledContent("Seeds → Us", value: "\(sending)")
                        }
                        if let getting = torrent.peersGettingFromUs {
                            LabeledContent("Us → Peers", value: "\(getting)")
                        }
                        LabeledContent("Download Limit") {
                            HStack(spacing: 6) {
                                Toggle("", isOn: $dlLimited)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .onChange(of: dlLimited) { applySpeedLimits() }
                                TextField("", value: $dlLimit, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .disabled(!dlLimited)
                                    .onSubmit { applySpeedLimits() }
                                Text("KB/s")
                                    .foregroundStyle(dlLimited ? .primary : .tertiary)
                            }
                        }
                        LabeledContent("Upload Limit") {
                            HStack(spacing: 6) {
                                Toggle("", isOn: $ulLimited)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .onChange(of: ulLimited) { applySpeedLimits() }
                                TextField("", value: $ulLimit, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .disabled(!ulLimited)
                                    .onSubmit { applySpeedLimits() }
                                Text("KB/s")
                                    .foregroundStyle(ulLimited ? .primary : .tertiary)
                            }
                        }
                    }
                    .onAppear {
                        guard !limitsLoaded else { return }
                        dlLimited = torrent.downloadLimited ?? false
                        dlLimit = torrent.downloadLimit ?? 0
                        ulLimited = torrent.uploadLimited ?? false
                        ulLimit = torrent.uploadLimit ?? 0
                        limitsLoaded = true
                    }

                    Section("Storage") {
                        LabeledContent("Location", value: torrent.downloadDir)
                        if let hash = torrent.hashString {
                            LabeledContent("Hash") {
                                Text(hash).textSelection(.enabled).monospaced()
                            }
                        }
                        if let pieces = torrent.pieceCount, let size = torrent.pieceSize {
                            LabeledContent("Pieces", value: "\(pieces) × \(formatBytes(size))")
                        }
                        if let files = torrent.fileCount {
                            LabeledContent("Files", value: "\(files)")
                        }
                    }

                    if torrent.comment != nil || torrent.creator != nil || torrent.dateCreated != nil || !torrent.labels.isEmpty {
                        Section("Metadata") {
                            if let comment = torrent.comment, !comment.isEmpty {
                                LabeledContent("Comment", value: comment)
                            }
                            if let creator = torrent.creator, !creator.isEmpty {
                                LabeledContent("Creator", value: creator)
                            }
                            if let dateCreated = torrent.dateCreated, dateCreated > 0 {
                                LabeledContent("Created") { dateText(dateCreated) }
                            }
                            if !torrent.labels.isEmpty {
                                LabeledContent("Labels", value: torrent.labels.joined(separator: ", "))
                            }
                        }
                    }

                    if torrent.error != 0 {
                        Section("Error") {
                            LabeledContent("Message") {
                                Text(torrent.errorString)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
        }
    }

    private func dateText(_ timestamp: Int) -> some View {
        HStack(spacing: 4) {
            Text(formatAbsoluteDate(timestamp))
            Text("(\(formatRelativeDate(timestamp)))")
                .foregroundStyle(.tertiary)
        }
    }

    private func applySpeedLimits() {
        Task {
            await manager.setTorrentSpeedLimits(
                id: torrent.id,
                downloadLimit: dlLimited ? dlLimit : nil,
                downloadLimited: dlLimited,
                uploadLimit: ulLimited ? ulLimit : nil,
                uploadLimited: ulLimited
            )
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
    let torrentID: Int
    var onChanged: () async -> Void
    @Environment(TorrentManager.self) private var manager
    @State private var actionError: String?

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
            .width(min: 200, ideal: 300)

            TableColumn("Size") { row in
                Text(formatBytes(row.size))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 70)

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

            TableColumn("Download") { row in
                HStack {
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { row.wanted },
                        set: { newValue in
                            Task {
                                do {
                                    try await manager.setFileWanted(torrentID: torrentID, fileIndex: row.id, wanted: newValue)
                                } catch {
                                    actionError = error.localizedDescription
                                }
                                await onChanged()
                            }
                        }
                    ))
                    .labelsHidden()
                    Spacer()
                }
            }
            .width(min: 40, ideal: 55)

            TableColumn("Priority") { row in
                Picker("", selection: Binding(
                    get: { row.priority },
                    set: { newValue in
                        Task {
                            do {
                                try await manager.setFilePriority(torrentID: torrentID, fileIndex: row.id, priority: newValue)
                            } catch {
                                actionError = error.localizedDescription
                            }
                            await onChanged()
                        }
                    }
                )) {
                    Text("↓").tag(-1)
                    Text("—").tag(0)
                    Text("↑").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 80)
            }
            .width(min: 70, ideal: 85)
        } rows: {
            ForEach(fileRows) { row in
                TableRow(row)
            }
        }
        .scrollIndicators(.hidden)
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
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
            .width(min: 80, ideal: 150)

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
