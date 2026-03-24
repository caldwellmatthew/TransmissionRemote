import SwiftUI

struct TorrentListView: View {
    @Environment(TorrentManager.self) private var manager
    @State private var sortOrder: [KeyPathComparator<Torrent>]
    @AppStorage("torrentTableColumns") private var columnCustomization: TableColumnCustomization<Torrent>
    @AppStorage("sortColumn") private var sortColumn = "name"
    @AppStorage("sortAscending") private var sortAscending = true

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
    }

    private var sortedTorrents: [Torrent] {
        manager.filteredTorrents.sorted(using: sortOrder)
    }

    private var torrentTable: some View {
        @Bindable var manager = manager

        return Table(sortedTorrents, selection: $manager.selectedTorrentIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
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
                    Capsule()
                        .fill(.tertiary)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(.tint)
                                    .frame(width: geo.size.width * torrent.percentDone)
                            }
                        }
                        .frame(height: 6)
                        .clipped()
                    Text("\(Int(torrent.percentDone * 100))%")
                        .monospacedDigit()
                        .fixedSize()
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
