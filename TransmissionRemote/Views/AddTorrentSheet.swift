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
