import SwiftUI

/// Invisible NSView that finds its enclosing NSToolbarItem and sets isBordered = false.
/// Use as .background(ToolbarItemBorderRemover()) on a toolbar item's content.
private struct ToolbarItemBorderRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { disableBorder(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func disableBorder(from view: NSView) {
        guard let toolbar = view.window?.toolbar else { return }
        for item in toolbar.items where item.isBordered {
            if let itemView = item.view, view.isDescendant(of: itemView) {
                item.isBordered = false
                return
            }
        }
    }
}

struct TorrentListView: View {
    @Environment(TorrentManager.self) private var manager
    @Environment(\.openWindow) private var openWindow
    @State private var sortOrder: [KeyPathComparator<Torrent>]
    @AppStorage("torrentTableColumns") private var columnCustomization: TableColumnCustomization<Torrent>
    @AppStorage("sortColumn") private var sortColumn = "name"
    @AppStorage("sortAscending") private var sortAscending = true
    @State private var showingFileImporter = false
    @State private var pendingAddSource: AddTorrentSheet.Source?
    @State private var showingRemoveConfirmation = false
    @State private var showingMoveSheet = false
    @State private var moveLocation = ""

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
        .navigationTitle("")
        .toolbar { toolbarContent }
        .onChange(of: sortOrder) { _, newOrder in
            if let first = newOrder.first {
                sortColumn = Self.columnName(for: first)
                sortAscending = first.order == .forward
            }
        }
        .sheet(item: $pendingAddSource) { source in
            AddTorrentSheet(source: source, manager: manager) { error in
                if let error { manager.actionError = error }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.init(filenameExtension: "torrent")!],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            pendingAddSource = .file(url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in
                        pendingAddSource = .file(url)
                    }
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTorrentFile)) { notification in
            if let url = notification.object as? URL {
                pendingAddSource = .file(url)
            } else {
                showingFileImporter = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addTorrentLink)) { notification in
            let link = (notification.object as? String) ?? ""
            pendingAddSource = .link(link)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTorrentInfo)) { _ in
            if manager.selectedTorrentIDs.count == 1, let id = manager.selectedTorrentIDs.first {
                openWindow(id: "torrent-detail", value: id)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { manager.actionError != nil },
            set: { if !$0 { manager.actionError = nil } }
        )) {
            Button("OK") { manager.actionError = nil }
        } message: {
            Text(manager.actionError ?? "")
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
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            let selectedTorrents = sortedTorrents.filter { ids.contains($0.id) }

            if selectedTorrents.count == 1, let id = selectedTorrents.first?.id {
                Button("Get Info") {
                    openWindow(id: "torrent-detail", value: id)
                }
                Divider()
            }

            Button("Verify") {
                manager.selectedTorrentIDs = ids
                Task { await manager.verifySelected() }
            }

            Button("Reannounce") {
                manager.selectedTorrentIDs = ids
                Task { await manager.reannounceSelected() }
            }

            Divider()

            Button("Change Download Location...") {
                manager.selectedTorrentIDs = ids
                moveLocation = selectedTorrents.first?.downloadDir ?? ""
                showingMoveSheet = true
            }

            Divider()

            if let torrent = selectedTorrents.first, selectedTorrents.count == 1,
               let magnet = torrent.magnetLink, !magnet.isEmpty {
                Button("Copy Magnet Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(magnet, forType: .string)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, ids.count == 1 {
                openWindow(id: "torrent-detail", value: id)
            }
        }
        .sheet(isPresented: $showingMoveSheet) {
            MoveLocationSheet(location: $moveLocation) { newLocation, move in
                let ids = Array(manager.selectedTorrentIDs)
                Task { await manager.setLocation(ids: ids, location: newLocation, move: move) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Left: filter picker
        ToolbarItem(placement: .navigation) {
            Picker("Filter", selection: Bindable(manager).statusFilter) {
                ForEach(TorrentManager.StatusFilter.allCases) { filter in
                    Label(filter.label, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelStyle(.titleAndIcon)
        }


        // Center: speeds
        ToolbarItem(placement: .principal) {
            if manager.connectionState == .connected {
                HStack(spacing: 14) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .foregroundStyle(manager.totalDownloadRate > 0 ? .primary : .tertiary)
                        Text(formatRate(manager.totalDownloadRate, showZero: true))
                            .monospacedDigit()
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(manager.totalUploadRate > 0 ? .primary : .tertiary)
                        Text(formatRate(manager.totalUploadRate, showZero: true))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .background(ToolbarItemBorderRemover())
            }
        }

        // Right: action buttons
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Open File...") {
                    showingFileImporter = true
                }
                Button("Add Magnet or URL...") {
                    pendingAddSource = .link("")
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
                showingRemoveConfirmation = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(manager.selectedTorrentIDs.isEmpty)
            .help("Remove selected torrents")
            .confirmationDialog(
                "Remove \(manager.selectedTorrentIDs.count) torrent\(manager.selectedTorrentIDs.count == 1 ? "" : "s")?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Torrent Only") {
                    Task { await manager.removeSelected(deleteData: false) }
                }
                Button("Remove Torrent and Delete Data", role: .destructive) {
                    Task { await manager.removeSelected(deleteData: true) }
                }
                Button("Cancel", role: .cancel) {}
            }
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

private struct AddTorrentSheet: View {
    enum Source: Identifiable, Hashable {
        case file(URL)
        case link(String)

        var id: String {
            switch self {
            case .file(let url): "file:\(url.absoluteString)"
            case .link(let str): "link:\(str)"
            }
        }
    }

    let source: Source
    let manager: TorrentManager
    var onComplete: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var downloadDir = ""
    @State private var startPaused = false
    @State private var priority = 0
    @State private var labelsText = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if case .link = source {
                    TextField("Magnet link or URL:", text: $linkText)
                } else if case .file(let url) = source {
                    LabeledContent("File:") {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                    }
                }

                TextField("Download to:", text: $downloadDir)
                    .help("Leave empty for server default")

                Picker("Priority:", selection: $priority) {
                    Text("Low").tag(-1)
                    Text("Normal").tag(0)
                    Text("High").tag(1)
                }

                Toggle("Start paused", isOn: $startPaused)

                TextField("Labels:", text: $labelsText)
                    .help("Comma-separated labels")
            }
            .formStyle(.grouped)
            .frame(width: 400)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addTorrent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAddDisabled)
            }
            .padding()
        }
        .task {
            downloadDir = await manager.getDefaultDownloadDir()
            if case .link(let str) = source { linkText = str }
            isLoading = false
        }
    }

    private var isAddDisabled: Bool {
        if case .link = source {
            return linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    private var options: TorrentAddOptions {
        let labels = labelsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return TorrentAddOptions(
            downloadDir: downloadDir.isEmpty ? nil : downloadDir,
            paused: startPaused ? true : nil,
            bandwidthPriority: priority != 0 ? priority : nil,
            labels: labels.isEmpty ? nil : labels
        )
    }

    private func addTorrent() {
        Task {
            do {
                switch source {
                case .file(let url):
                    _ = try await manager.addTorrent(fileURL: url, options: options)
                case .link:
                    let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try await manager.addTorrent(url: trimmed, options: options)
                }
                onComplete(nil)
            } catch {
                onComplete(error.localizedDescription)
            }
            dismiss()
        }
    }
}

private struct MoveLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var location: String
    @State private var moveFiles = true
    var onMove: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Download Location")
                .font(.headline)

            TextField("Path on server:", text: $location)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
                .onSubmit { moveAndDismiss() }

            Toggle("Move existing files to new location", isOn: $moveFiles)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set Location") { moveAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func moveAndDismiss() {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onMove(trimmed, moveFiles)
        dismiss()
    }
}
