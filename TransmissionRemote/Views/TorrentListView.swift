import SwiftUI
import UniformTypeIdentifiers

private struct TorrentFileDrop: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: UTType("org.bittorrent.torrent")!) { received in
            TorrentFileDrop(url: try copyToTemporary(received.file))
        }
        FileRepresentation(importedContentType: UTType("com.bittorrent.torrent")!) { received in
            TorrentFileDrop(url: try copyToTemporary(received.file))
        }
    }

    // The received file is only guaranteed to exist while the importing
    // closure runs, but it isn't read until the user confirms the add sheet.
    // Copy it to a location we own so it can't vanish in between.
    private static func copyToTemporary(_ source: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
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
    @State private var showingNewLabelSheet = false
    @State private var columnsReady = UserDefaults.standard.dictionary(forKey: "torrentTableColumnWidths") == nil

    init() {
        let column = UserDefaults.standard.string(forKey: "sortColumn") ?? "name"
        let ascending = UserDefaults.standard.object(forKey: "sortAscending") as? Bool ?? true
        let order: SortOrder = ascending ? .forward : .reverse
        _sortOrder = State(initialValue: [Self.comparator(for: column, order: order)])
    }

    var body: some View {
        @Bindable var manager = manager

        VStack(spacing: 0) {
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
                    torrentTable
                        .opacity(manager.filteredTorrents.isEmpty ? 0 : 1)
                        .overlay {
                            if manager.filteredTorrents.isEmpty && manager.torrents.isEmpty {
                                ContentUnavailableView(
                                    "No Torrents",
                                    systemImage: "tray",
                                    description: Text("Add a torrent to get started")
                                )
                            } else if manager.filteredTorrents.isEmpty {
                                ContentUnavailableView.search(text: manager.searchText)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)

            if manager.connectionState == .connected {
                Divider()
                HStack {
                    Group {
                        if manager.filteredTorrents.count != manager.torrents.count {
                            Text("\(manager.filteredTorrents.count) of \(manager.torrents.count) torrents")
                        } else {
                            Text("\(manager.torrents.count) torrents")
                        }
                    }
                    .foregroundStyle(.tertiary)

                    if manager.pendingAddCount > 0 {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                            Text(manager.pendingAddCount == 1
                                 ? "Adding torrent…"
                                 : "Adding \(manager.pendingAddCount) torrents…")
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await manager.toggleTurtleMode() }
                    } label: {
                        Image(systemName: manager.isTurtleModeEnabled ? "tortoise.fill" : "tortoise")
                            .foregroundStyle(manager.isTurtleModeEnabled ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(manager.isTurtleModeEnabled ? "Disable turtle mode" : "Enable turtle mode")

                    HStack(spacing: 14) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .foregroundStyle(manager.totalDownloadRate > 0 ? .primary : .tertiary)
                            Text(formatRate(manager.totalDownloadRate, showZero: true))
                                .monospacedDigit()
                            if let limit = activeDownloadLimit {
                                Text("(\(formatRate(limit * 1000)))")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .foregroundStyle(manager.totalUploadRate > 0 ? .primary : .tertiary)
                            Text(formatRate(manager.totalUploadRate, showZero: true))
                                .monospacedDigit()
                            if let limit = activeUploadLimit {
                                Text("(\(formatRate(limit * 1000)))")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 5)
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
            AddTorrentSheet(source: source, manager: manager)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.init(filenameExtension: "torrent")!],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            pendingAddSource = .file(url)
        }
        .dropDestination(for: TorrentFileDrop.self) { items, _ in
            guard let file = items.first else { return false }
            pendingAddSource = .file(file.url)
            return true
        } isTargeted: { _ in }
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
                .customizationID("name")
                .disabledCustomizationBehavior(.all)

                TableColumn("Progress", value: \.percentDone) { torrent in
                    ProgressCell(torrent: torrent)
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

            Menu("Queue") {
                Button("Move to Top") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.queueMoveTopSelected() }
                }
                Button("Move Up") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.queueMoveUpSelected() }
                }
                Button("Move Down") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.queueMoveDownSelected() }
                }
                Button("Move to Bottom") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.queueMoveBottomSelected() }
                }
            }

            Menu("Priority") {
                let currentPriority = selectedTorrents.count == 1 ? selectedTorrents.first?.bandwidthPriority : nil
                Button(currentPriority == 1 ? "✓ High" : "  High") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.setBandwidthPrioritySelected(priority: 1) }
                }
                Button(currentPriority == 0 ? "✓ Normal" : "  Normal") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.setBandwidthPrioritySelected(priority: 0) }
                }
                Button(currentPriority == -1 ? "✓ Low" : "  Low") {
                    manager.selectedTorrentIDs = ids
                    Task { await manager.setBandwidthPrioritySelected(priority: -1) }
                }
            }

            Divider()

            Button("Change Download Location...") {
                manager.selectedTorrentIDs = ids
                moveLocation = selectedTorrents.first?.downloadDir ?? ""
                showingMoveSheet = true
            }

            Divider()

            Menu("Add Label") {
                let existing = manager.allLabels
                let presentOnAll = Set(selectedTorrents.dropFirst().reduce(
                    Set(selectedTorrents.first?.labels ?? [])
                ) { acc, t in acc.intersection(t.labels) })
                ForEach(existing, id: \.self) { label in
                    Button(presentOnAll.contains(label) ? "✓ \(label)" : "  \(label)") {
                        manager.selectedTorrentIDs = ids
                        Task { await manager.addLabelToSelected(label) }
                    }
                }
                if !existing.isEmpty { Divider() }
                Button("New Label...") {
                    manager.selectedTorrentIDs = ids
                    showingNewLabelSheet = true
                }
            }

            let removable = manager.labelsOnSelection
            if !removable.isEmpty {
                Menu("Remove Label") {
                    ForEach(removable, id: \.self) { label in
                        Button(label) {
                            manager.selectedTorrentIDs = ids
                            Task { await manager.removeLabelFromSelected(label) }
                        }
                    }
                }
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
        .sheet(isPresented: $showingNewLabelSheet) {
            NewLabelSheet { label in
                Task { await manager.addLabelToSelected(label) }
            }
        }
        .background(TableColumnWidthPersister(ready: $columnsReady))
        .opacity(columnsReady ? 1 : 0)
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

    private var activeDownloadLimit: Int? {
        guard let s = manager.sessionSettings else { return nil }
        if s.altSpeedEnabled { return s.altSpeedDown }
        if s.speedLimitDownEnabled { return s.speedLimitDown }
        return nil
    }

    private var activeUploadLimit: Int? {
        guard let s = manager.sessionSettings else { return nil }
        if s.altSpeedEnabled { return s.altSpeedUp }
        if s.speedLimitUpEnabled { return s.speedLimitUp }
        return nil
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

private struct ProgressCell: View {
    let torrent: Torrent

    var body: some View {
        let isChecking = torrent.status == .checking || torrent.status == .checkWait
        let progress = isChecking ? (torrent.recheckProgress ?? 0) : torrent.percentDone
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                Capsule()
                    .fill(isChecking ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                    .scaleEffect(x: progress, anchor: .leading)
            }
            .frame(height: 6)
            Text("\(Int(progress * 100))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}
