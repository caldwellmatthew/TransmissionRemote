import SwiftUI

struct TorrentListView: View {
    @Environment(TorrentManager.self) private var manager
    @State private var sortOrder: [KeyPathComparator<Torrent>] = [
        KeyPathComparator(\.name, order: .forward),
    ]
    @State private var columnCustomization: TableColumnCustomization<Torrent> = .init()

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
            .customizationID("name")

            TableColumn("Progress", value: \.percentDone) { torrent in
                HStack(spacing: 6) {
                    ProgressView(value: torrent.percentDone)
                        .frame(width: 60)
                    Text("\(Int(torrent.percentDone * 100))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .width(110)
            .customizationID("progress")

            TableColumn("↓ Down", value: \.rateDownload) { torrent in
                Text(formatRate(torrent.rateDownload))
                    .monospacedDigit()
                    .foregroundStyle(torrent.rateDownload > 0 ? .primary : .secondary)
            }
            .width(90)
            .customizationID("down")

            TableColumn("↑ Up", value: \.rateUpload) { torrent in
                Text(formatRate(torrent.rateUpload))
                    .monospacedDigit()
                    .foregroundStyle(torrent.rateUpload > 0 ? .primary : .secondary)
            }
            .width(90)
            .customizationID("up")

            TableColumn("Size", value: \.totalSize) { torrent in
                Text(formatBytes(torrent.totalSize))
                    .monospacedDigit()
            }
            .width(80)
            .customizationID("size")

            TableColumn("ETA", value: \.eta) { torrent in
                Text(formatETA(torrent.eta))
                    .monospacedDigit()
            }
            .width(70)
            .customizationID("eta")

            TableColumn("Ratio", value: \.uploadRatio) { torrent in
                Text(torrent.uploadRatio >= 0 ? String(format: "%.2f", torrent.uploadRatio) : "")
                    .monospacedDigit()
            }
            .width(60)
            .customizationID("ratio")

            TableColumn("Added", value: \.addedDate) { torrent in
                Text(formatDate(torrent.addedDate))
            }
            .width(100)
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
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(manager.selectedTorrentIDs.isEmpty)
            .help("Stop selected torrents")

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
                    Label(formatRate(manager.totalDownloadRate), systemImage: "arrow.down")
                        .monospacedDigit()
                    Label(formatRate(manager.totalUploadRate), systemImage: "arrow.up")
                        .monospacedDigit()
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
}
