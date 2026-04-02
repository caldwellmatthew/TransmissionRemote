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

private enum WantedState {
    case yes, no, mixed

    var isOn: Bool { self == .yes }
}

private enum PriorityState: Equatable {
    case low, normal, high, mixed

    init(raw: Int) {
        switch raw {
        case -1: self = .low
        case 1:  self = .high
        default: self = .normal
        }
    }

    var rawValue: Int? {
        switch self {
        case .low: return -1
        case .normal: return 0
        case .high: return 1
        case .mixed: return nil
        }
    }
}

private struct FileNode: Identifiable {
    let id: String
    let name: String
    let children: [FileNode]?
    let fileIndex: Int?
    let size: Int64
    let progress: Double
    let wanted: WantedState
    let priority: PriorityState

    var isDirectory: Bool { children != nil }

    var allFileIndices: [Int] {
        if let fileIndex { return [fileIndex] }
        return children?.flatMap(\.allFileIndices) ?? []
    }

    static func buildTree(files: [TorrentFile], stats: [TorrentFileStat]) -> [FileNode] {
        class MutableNode {
            let name: String
            var children: [String: MutableNode] = [:]
            var childOrder: [String] = []
            var fileIndex: Int?
            var fileLength: Int64 = 0
            var bytesCompleted: Int64 = 0
            var wanted: Bool = true
            var priority: Int = 0
            init(name: String) { self.name = name }
        }

        let root = MutableNode(name: "")

        for (index, file) in files.enumerated() {
            let components = file.name.split(separator: "/").map(String.init)
            let stat = index < stats.count ? stats[index] : nil
            var current = root
            for (depth, component) in components.enumerated() {
                let isLeaf = depth == components.count - 1
                if current.children[component] == nil {
                    current.children[component] = MutableNode(name: component)
                    current.childOrder.append(component)
                }
                let child = current.children[component]!
                if isLeaf {
                    child.fileIndex = index
                    child.fileLength = file.length
                    child.bytesCompleted = file.bytesCompleted
                    child.wanted = stat?.wanted ?? true
                    child.priority = stat?.priority ?? 0
                }
                current = child
            }
        }

        func convert(_ node: MutableNode, pathPrefix: String) -> FileNode {
            if node.children.isEmpty {
                let progress = node.fileLength > 0 ? Double(node.bytesCompleted) / Double(node.fileLength) : 0
                return FileNode(
                    id: pathPrefix + node.name,
                    name: node.name,
                    children: nil,
                    fileIndex: node.fileIndex,
                    size: node.fileLength,
                    progress: progress,
                    wanted: node.wanted ? .yes : .no,
                    priority: PriorityState(raw: node.priority)
                )
            }

            let prefix = pathPrefix.isEmpty ? node.name + "/" : pathPrefix + node.name + "/"
            let childNodes = node.childOrder.map { convert(node.children[$0]!, pathPrefix: prefix) }

            let totalSize = childNodes.reduce(Int64(0)) { $0 + $1.size }
            let weightedProgress = totalSize > 0
                ? childNodes.reduce(0.0) { $0 + $1.progress * Double($1.size) } / Double(totalSize)
                : 0.0

            let allWanted = childNodes.allSatisfy { $0.wanted == .yes }
            let noneWanted = childNodes.allSatisfy { $0.wanted == .no }
            let wantedState: WantedState = allWanted ? .yes : noneWanted ? .no : .mixed

            let priorities = Set(childNodes.map(\.priority))
            let priorityState: PriorityState = priorities.count == 1 ? priorities.first! : .mixed

            return FileNode(
                id: pathPrefix + node.name,
                name: node.name,
                children: childNodes,
                fileIndex: nil,
                size: totalSize,
                progress: weightedProgress,
                wanted: wantedState,
                priority: priorityState
            )
        }

        return root.childOrder.map { convert(root.children[$0]!, pathPrefix: "") }
    }
}

private struct FileTreeRows: TableRowContent {
    let nodes: [FileNode]
    @Binding var expanded: Set<String>

    var tableRowBody: some TableRowContent<FileNode> {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureTableRow(node, isExpanded: Binding(
                    get: { expanded.contains(node.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expanded.insert(node.id)
                        } else {
                            expanded.remove(node.id)
                        }
                    }
                )) {
                    FileTreeRows(nodes: children, expanded: $expanded)
                }
            } else {
                TableRow(node)
            }
        }
    }
}

private struct FilesTab: View {
    let torrent: Torrent
    let torrentID: Int
    var onChanged: () async -> Void
    @Environment(TorrentManager.self) private var manager
    @State private var actionError: String?
    @State private var expandedNodes: Set<String> = []
    @State private var hasInitializedExpansion = false
    @State private var fileTree: [FileNode] = []

    var body: some View {
        Table(of: FileNode.self) {
            TableColumn("Name") { node in
                Label {
                    Text(node.name)
                        .lineLimit(1)
                        .help(node.id)
                } icon: {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                        .foregroundStyle(node.isDirectory ? .blue : .secondary)
                }
            }
            .width(min: 200, ideal: 300)

            TableColumn("Size") { node in
                Text(formatBytes(node.size))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Progress") { node in
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.tertiary)
                        Capsule().fill(.tint).scaleEffect(x: node.progress, anchor: .leading)
                    }
                    .frame(height: 6)
                    Text("\(Int(node.progress * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("Download") { node in
                HStack {
                    Spacer()
                    wantedControl(for: node)
                    Spacer()
                }
            }
            .width(min: 40, ideal: 55)

            TableColumn("Priority") { node in
                priorityControl(for: node)
            }
            .width(min: 70, ideal: 85)
        } rows: {
            FileTreeRows(nodes: fileTree, expanded: $expandedNodes)
        }
        .scrollIndicators(.hidden)
        .onChange(of: torrent.files) { rebuildTree() }
        .onChange(of: torrent.fileStats) { rebuildTree() }
        .onAppear { rebuildTree() }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func wantedControl(for node: FileNode) -> some View {
        switch node.wanted {
        case .yes, .no:
            Toggle("", isOn: Binding(
                get: { node.wanted.isOn },
                set: { newValue in
                    Task {
                        do {
                            try await manager.setFilesWanted(torrentID: torrentID, fileIndices: node.allFileIndices, wanted: newValue)
                        } catch {
                            actionError = error.localizedDescription
                        }
                        await onChanged()
                    }
                }
            ))
            .labelsHidden()
        case .mixed:
            Button {
                Task {
                    do {
                        try await manager.setFilesWanted(torrentID: torrentID, fileIndices: node.allFileIndices, wanted: true)
                    } catch {
                        actionError = error.localizedDescription
                    }
                    await onChanged()
                }
            } label: {
                Image(systemName: "minus.square.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func priorityControl(for node: FileNode) -> some View {
        Picker("", selection: Binding(
            get: { node.priority.rawValue ?? -2 },
            set: { newValue in setPriority(newValue, for: node) }
        )) {
            Text("↓").tag(-1)
            Text("—").tag(0)
            Text("↑").tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 80)
    }

    private func setPriority(_ priority: Int, for node: FileNode) {
        Task {
            do {
                try await manager.setFilePriority(torrentID: torrentID, fileIndices: node.allFileIndices, priority: priority)
            } catch {
                actionError = error.localizedDescription
            }
            await onChanged()
        }
    }

    private func rebuildTree() {
        let files = torrent.files ?? []
        let stats = torrent.fileStats ?? []
        fileTree = FileNode.buildTree(files: files, stats: stats)
        if !hasInitializedExpansion {
            expandedNodes = collectDirectoryIDs(fileTree)
            hasInitializedExpansion = true
        }
    }

    private func collectDirectoryIDs(_ nodes: [FileNode]) -> Set<String> {
        var ids = Set<String>()
        for node in nodes {
            if let children = node.children {
                ids.insert(node.id)
                ids.formUnion(collectDirectoryIDs(children))
            }
        }
        return ids
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
