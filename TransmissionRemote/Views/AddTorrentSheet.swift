import SwiftUI

struct AddTorrentSheet: View {
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

    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var downloadDir = ""
    @State private var startPaused = false
    @State private var priority = 0
    @State private var labelsText = ""

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
        switch source {
        case .file(let url):
            manager.addTorrentInBackground(fileURL: url, options: options)
        case .link:
            let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
            manager.addTorrentInBackground(url: trimmed, options: options)
        }
        dismiss()
    }
}
