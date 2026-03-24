import SwiftUI

struct TorrentListView: View {
    @Environment(TorrentManager.self) private var manager
    @State private var sortOrder: [KeyPathComparator<Torrent>]
    @AppStorage("torrentTableColumns") private var columnCustomization: TableColumnCustomization<Torrent>
    @AppStorage("sortColumn") private var sortColumn = "name"
    @AppStorage("sortAscending") private var sortAscending = true
    @State private var showingAddURL = false
    @State private var showingFileImporter = false
    @State private var addURLText = ""
    @State private var addError: String?

    init() {
        let column = UserDefaults.standard.string(forKey: "sortColumn") ?? "name"
        let ascending = UserDefaults.standard.object(forKey: "sortAscending") as? Bool ?? true
        let order: SortOrder = ascending ? .forward : .reverse
        _sortOrder = State(initialValue: [Self.comparator(for: column, order: order)])
    }

    var body: some View {
        @Bindable var manager = manager

        Group {
            switch manager.connectionState {
            case .disconnected, .connecting:
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text("Connecting to Transmission...")
                }

            case .error:
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(manager.errorMessage ?? "Unable to connect")
                } actions: {
                    Button("Retry") {
                        manager.reconnect()
                    }
                    SettingsLink {
                        Text("Open Settings")
                    }
                }

            case .connected:
                if manager.filteredTorrents.isEmpty && manager.torrents.isEmpty {
                    ContentUnavailableView(
                        "No Torrents",
                        systemImage: "tray",
                        description: Text("Add a torrent to get started")
                    )
                } else if manager.filteredTorrents.isEmpty {
                    ContentUnavailableView.search(text: manager.searchText)
                } else {
                    torrentTable
                }
            }
        }
        .searchable(text: $manager.searchText, prompt: "Filter torrents")
        .toolbar { toolbarContent }
        .onChange(of: sortOrder) { _, newOrder in
            if let first = newOrder.first {
                sortColumn = Self.columnName(for: first)
                sortAscending = first.order == .forward
            }
        }
        .sheet(isPresented: $showingAddURL) {
            AddURLSheet(urlText: $addURLText) { url in
                Task {
                    do {
                        _ = try await manager.addTorrent(url: url)
                    } catch {
                        addError = error.localizedDescription
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.init(filenameExtension: "torrent")!],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                Task { try? await manager.addTorrent(fileURL: url) }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in
                        try? await manager.addTorrent(fileURL: url)
                    }
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTorrentFile)) { _ in
            showingFileImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .addTorrentLink)) { _ in
            addURLText = ""
            showingAddURL = true
        }
        .alert("Failed to Add Torrent", isPresented: Binding(
            get: { addError != nil },
            set: { if !$0 { addError = nil } }
        )) {
            Button("OK") { addError = nil }
        } message: {
            Text(addError ?? "")
        }
    }

    private var sortedTorrents: [Torrent] {
        manager.filteredTorrents.sorted(using: sortOrder)
    }

    private var torrentTable: some View {
        @Bindable var manager = manager

        return Table(sortedTorrents, selection: $manager.selectedTorrentIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // Group 1: Default visible columns
            Group {
                TableColumn("Name", value: \.name) { torrent in
                    HStack(spacing: 6) {
                        Image(systemName: torrent.status.systemImage)
                            .foregroundStyle(statusColor(for: torrent))
                            .help(torrent.status.label)
                        Text(torrent.name)
                            .lineLimit(1)
                    }
                }
                .width(min: 200)

                TableColumn("Progress", value: \.percentDone) { torrent in
                    HStack(spacing: 6) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.tertiary)
                            Capsule()
                                .fill(.tint)
                                .scaleEffect(x: torrent.percentDone, anchor: .leading)
                        }
                        .frame(height: 6)
                        Text("\(Int(torrent.percentDone * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .width(min: 80, ideal: 110, max: 160)
                .customizationID("progress")

                TableColumn("↓ Down", value: \.rateDownload) { torrent in
                    Text(formatRate(torrent.rateDownload))
                        .monospacedDigit()
                        .foregroundStyle(torrent.rateDownload > 0 ? .primary : .secondary)
                }
                .width(min: 60, ideal: 90, max: 140)
                .customizationID("down")

                TableColumn("↑ Up", value: \.rateUpload) { torrent in
                    Text(formatRate(torrent.rateUpload))
                        .monospacedDigit()
                        .foregroundStyle(torrent.rateUpload > 0 ? .primary : .secondary)
                }
                .width(min: 60, ideal: 90, max: 140)
                .customizationID("up")

                TableColumn("Size", value: \.totalSize) { torrent in
                    Text(formatBytes(torrent.totalSize))
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("size")

                TableColumn("ETA", value: \.eta) { torrent in
                    Text(formatETA(torrent.eta))
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 70, max: 120)
                .customizationID("eta")

                TableColumn("Ratio", value: \.uploadRatio) { torrent in
                    Text(torrent.uploadRatio >= 0 ? String(format: "%.2f", torrent.uploadRatio) : "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 60, max: 100)
                .customizationID("ratio")

                TableColumn("Added", value: \.addedDate) { torrent in
                    Text(formatDate(torrent.addedDate))
                }
                .width(min: 70, ideal: 100, max: 150)
                .customizationID("added")
            }

            // Group 2: Hidden columns — status, dates, paths, errors, peers
            Group {
                TableColumn("Status") { (torrent: Torrent) in
                    Text(torrent.status.label)
                }
                .width(min: 60, ideal: 90, max: 140)
                .customizationID("status")
                .defaultVisibility(.hidden)

                TableColumn("Done Date") { (torrent: Torrent) in
                    Text(formatDate(torrent.doneDate))
                }
                .width(min: 70, ideal: 100, max: 150)
                .customizationID("doneDate")
                .defaultVisibility(.hidden)

                TableColumn("Download Dir") { (torrent: Torrent) in
                    Text(torrent.downloadDir)
                        .lineLimit(1)
                        .help(torrent.downloadDir)
                }
                .width(min: 80, ideal: 150, max: 300)
                .customizationID("downloadDir")
                .defaultVisibility(.hidden)

                TableColumn("Error") { (torrent: Torrent) in
                    Text(torrent.errorString)
                        .lineLimit(1)
                        .foregroundStyle(.red)
                }
                .width(min: 60, ideal: 120, max: 250)
                .customizationID("errorString")
                .defaultVisibility(.hidden)

                TableColumn("Peers") { (torrent: Torrent) in
                    Text("\(torrent.peersConnected)")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 80)
                .customizationID("peers")
                .defaultVisibility(.hidden)

                TableColumn("Seeds → Us") { (torrent: Torrent) in
                    Text(torrent.peersSendingToUs.map { "\($0)" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 60, max: 80)
                .customizationID("peersSendingToUs")
                .defaultVisibility(.hidden)

                TableColumn("Us → Peers") { (torrent: Torrent) in
                    Text(torrent.peersGettingFromUs.map { "\($0)" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 60, max: 80)
                .customizationID("peersGettingFromUs")
                .defaultVisibility(.hidden)

                TableColumn("Uploaded") { (torrent: Torrent) in
                    Text(torrent.uploadedEver.map { formatBytes($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("uploadedEver")
                .defaultVisibility(.hidden)

                TableColumn("Remaining") { (torrent: Torrent) in
                    Text(torrent.leftUntilDone.map { formatBytes($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("leftUntilDone")
                .defaultVisibility(.hidden)

                TableColumn("Size When Done") { (torrent: Torrent) in
                    Text(torrent.sizeWhenDone.map { formatBytes($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("sizeWhenDone")
                .defaultVisibility(.hidden)
            }

            // Group 3: Hidden columns — byte counts, queue, priority
            Group {
                TableColumn("Have Valid") { (torrent: Torrent) in
                    Text(torrent.haveValid.map { formatBytes($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("haveValid")
                .defaultVisibility(.hidden)

                TableColumn("Corrupt") { (torrent: Torrent) in
                    Text(torrent.corruptEver.map { formatBytes($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("corruptEver")
                .defaultVisibility(.hidden)

                TableColumn("Queue") { (torrent: Torrent) in
                    Text(torrent.queuePosition.map { "\($0)" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 80)
                .customizationID("queuePosition")
                .defaultVisibility(.hidden)

                TableColumn("Priority") { (torrent: Torrent) in
                    Text(torrent.bandwidthPriority.map { formatPriority($0) } ?? "")
                }
                .width(min: 50, ideal: 70, max: 100)
                .customizationID("priority")
                .defaultVisibility(.hidden)

                TableColumn("Seed Ratio Limit") { (torrent: Torrent) in
                    Text(torrent.seedRatioLimit.map { String(format: "%.2f", $0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 60, max: 100)
                .customizationID("seedRatioLimit")
                .defaultVisibility(.hidden)

                TableColumn("Last Active") { (torrent: Torrent) in
                    Text(torrent.activityDate.map { formatDate($0) } ?? "")
                }
                .width(min: 70, ideal: 100, max: 150)
                .customizationID("activityDate")
                .defaultVisibility(.hidden)

                TableColumn("Created") { (torrent: Torrent) in
                    Text(torrent.dateCreated.map { formatDate($0) } ?? "")
                }
                .width(min: 70, ideal: 100, max: 150)
                .customizationID("dateCreated")
                .defaultVisibility(.hidden)

                TableColumn("Started") { (torrent: Torrent) in
                    Text(torrent.startDate.map { formatDate($0) } ?? "")
                }
                .width(min: 70, ideal: 100, max: 150)
                .customizationID("startDate")
                .defaultVisibility(.hidden)

                TableColumn("Time Downloading") { (torrent: Torrent) in
                    Text(torrent.secondsDownloading.map { formatDuration($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("secondsDownloading")
                .defaultVisibility(.hidden)

                TableColumn("Time Seeding") { (torrent: Torrent) in
                    Text(torrent.secondsSeeding.map { formatDuration($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80, max: 120)
                .customizationID("secondsSeeding")
                .defaultVisibility(.hidden)
            }

            // Group 4: Hidden columns — technical details, metadata
            Group {
                TableColumn("Recheck") { (torrent: Torrent) in
                    Text(torrent.recheckProgress.map { "\(Int($0 * 100))%" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 60, max: 100)
                .customizationID("recheckProgress")
                .defaultVisibility(.hidden)

                TableColumn("Files") { (torrent: Torrent) in
                    Text(torrent.fileCount.map { "\($0)" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 80)
                .customizationID("fileCount")
                .defaultVisibility(.hidden)

                TableColumn("Piece Size") { (torrent: Torrent) in
                    Text(torrent.pieceSize.map { formatBytes($0) } ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 70, max: 100)
                .customizationID("pieceSize")
                .defaultVisibility(.hidden)

                TableColumn("Pieces") { (torrent: Torrent) in
                    Text(torrent.pieceCount.map { "\($0)" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 60, max: 100)
                .customizationID("pieceCount")
                .defaultVisibility(.hidden)

                TableColumn("Hash") { (torrent: Torrent) in
                    Text(torrent.hashString ?? "")
                        .lineLimit(1)
                        .monospaced()
                }
                .width(min: 80, ideal: 160, max: 360)
                .customizationID("hash")
                .defaultVisibility(.hidden)

                TableColumn("Comment") { (torrent: Torrent) in
                    Text(torrent.comment ?? "")
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 150, max: 300)
                .customizationID("comment")
                .defaultVisibility(.hidden)

                TableColumn("Creator") { (torrent: Torrent) in
                    Text(torrent.creator ?? "")
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 120, max: 200)
                .customizationID("creator")
                .defaultVisibility(.hidden)

                TableColumn("Labels") { (torrent: Torrent) in
                    Text(torrent.labels.joined(separator: ", "))
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 100, max: 200)
                .customizationID("labels")
                .defaultVisibility(.hidden)

                TableColumn("Group") { (torrent: Torrent) in
                    Text(torrent.group ?? "")
                }
                .width(min: 40, ideal: 70, max: 120)
                .customizationID("group")
                .defaultVisibility(.hidden)

                TableColumn("MIME Type") { (torrent: Torrent) in
                    Text(torrent.primaryMimeType ?? "")
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 100, max: 180)
                .customizationID("mimeType")
                .defaultVisibility(.hidden)
            }

            // Group 5: Hidden columns — flags, limits
            Group {
                TableColumn("Private") { (torrent: Torrent) in
                    Text(torrent.isPrivate.map { $0 ? "Yes" : "No" } ?? "")
                }
                .width(min: 40, ideal: 50, max: 70)
                .customizationID("isPrivate")
                .defaultVisibility(.hidden)

                TableColumn("Finished") { (torrent: Torrent) in
                    Text(torrent.isFinished.map { $0 ? "Yes" : "No" } ?? "")
                }
                .width(min: 40, ideal: 55, max: 70)
                .customizationID("isFinished")
                .defaultVisibility(.hidden)

                TableColumn("Stalled") { (torrent: Torrent) in
                    Text(torrent.isStalled.map { $0 ? "Yes" : "No" } ?? "")
                }
                .width(min: 40, ideal: 50, max: 70)
                .customizationID("isStalled")
                .defaultVisibility(.hidden)

                TableColumn("DL Limit") { (torrent: Torrent) in
                    if let limited = torrent.downloadLimited, limited, let limit = torrent.downloadLimit {
                        Text("\(limit) KB/s").monospacedDigit()
                    } else {
                        Text("")
                    }
                }
                .width(min: 50, ideal: 70, max: 100)
                .customizationID("dlLimit")
                .defaultVisibility(.hidden)

                TableColumn("UL Limit") { (torrent: Torrent) in
                    if let limited = torrent.uploadLimited, limited, let limit = torrent.uploadLimit {
                        Text("\(limit) KB/s").monospacedDigit()
                    } else {
                        Text("")
                    }
                }
                .width(min: 50, ideal: 70, max: 100)
                .customizationID("ulLimit")
                .defaultVisibility(.hidden)

                TableColumn("Webseeds") { (torrent: Torrent) in
                    Text(torrent.webseedsSendingToUs.map { "\($0)" } ?? "")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 80)
                .customizationID("webseeds")
                .defaultVisibility(.hidden)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Open File...") {
                    showingFileImporter = true
                }
                Button("Add Magnet or URL...") {
                    addURLText = ""
                    showingAddURL = true
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add torrent")

            Button {
                Task { await manager.startSelected() }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(manager.selectedTorrentIDs.isEmpty)
            .help("Start selected torrents")

            Button {
                Task { await manager.stopSelected() }
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(manager.selectedTorrentIDs.isEmpty)
            .help("Pause selected torrents")

            Button {
                Task { await manager.removeSelected(deleteData: false) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(manager.selectedTorrentIDs.isEmpty)
            .help("Remove selected torrents")
        }

        ToolbarItem(placement: .status) {
            if manager.connectionState == .connected {
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                        Text(formatRate(manager.totalDownloadRate))
                            .monospacedDigit()
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                        Text(formatRate(manager.totalUploadRate))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        ToolbarItem(placement: .navigation) {
            Picker("Filter", selection: Bindable(manager).statusFilter) {
                ForEach(TorrentManager.StatusFilter.allCases) { filter in
                    Label(filter.label, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func statusColor(for torrent: Torrent) -> Color {
        if torrent.error != 0 { return .red }
        switch torrent.status {
        case .downloading, .downloadWait: return .blue
        case .seeding, .seedWait: return .green
        case .stopped: return .secondary
        case .checking, .checkWait: return .orange
        case .unknown: return .secondary
        }
    }

    private static func comparator(for column: String, order: SortOrder) -> KeyPathComparator<Torrent> {
        switch column {
        case "percentDone":  KeyPathComparator(\.percentDone, order: order)
        case "rateDownload": KeyPathComparator(\.rateDownload, order: order)
        case "rateUpload":   KeyPathComparator(\.rateUpload, order: order)
        case "totalSize":    KeyPathComparator(\.totalSize, order: order)
        case "eta":          KeyPathComparator(\.eta, order: order)
        case "uploadRatio":  KeyPathComparator(\.uploadRatio, order: order)
        case "addedDate":    KeyPathComparator(\.addedDate, order: order)
        default:             KeyPathComparator(\.name, order: order)
        }
    }

    private static func columnName(for comparator: KeyPathComparator<Torrent>) -> String {
        switch comparator.keyPath {
        case \Torrent.percentDone:  "percentDone"
        case \Torrent.rateDownload: "rateDownload"
        case \Torrent.rateUpload:   "rateUpload"
        case \Torrent.totalSize:    "totalSize"
        case \Torrent.eta:          "eta"
        case \Torrent.uploadRatio:  "uploadRatio"
        case \Torrent.addedDate:    "addedDate"
        default:                    "name"
        }
    }
}

private struct AddURLSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var urlText: String
    var onAdd: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Torrent")
                .font(.headline)

            TextField("Magnet link or URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
                .onSubmit { addAndDismiss() }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func addAndDismiss() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        dismiss()
    }
}
