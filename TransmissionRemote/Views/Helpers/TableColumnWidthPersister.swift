import AppKit
import SwiftUI

private let userDefaultsKey = "torrentTableColumnWidths"

/// Invisible NSView that finds the underlying NSTableView behind a SwiftUI Table,
/// observes column resize events via KVO, and persists/restores widths via UserDefaults.
/// Attach as `.background(TableColumnWidthPersister(ready: $columnsReady))` on the Table.
struct TableColumnWidthPersister: NSViewRepresentable {
    @Binding var ready: Bool

    func makeNSView(context: Context) -> DiscoveryView {
        DiscoveryView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: DiscoveryView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(ready: $ready) }

    /// Custom NSView that triggers discovery when added to a window.
    final class DiscoveryView: NSView {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let window = self.window else { return }
                MainActor.assumeIsolated {
                    self.coordinator.discover(from: window.contentView!)
                }
            }
        }
    }

    @MainActor final class Coordinator: NSObject {
        private weak var tableView: NSTableView?
        private var columnObservations: [NSKeyValueObservation] = []
        private nonisolated(unsafe) var resetObservation: Any?
        private var defaultWidths: [String: Double] = [:]
        private var debounceWork: DispatchWorkItem?
        private var isRestoring = false
        private var ready: Binding<Bool>

        init(ready: Binding<Bool>) {
            self.ready = ready
        }

        func discover(from contentView: NSView) {
            guard tableView == nil,
                  let table = Self.findTableView(in: contentView) else { return }
            tableView = table
            captureDefaultWidths()
            restoreWidths()
            observeResizes()
            observeReset()
            // Re-apply after SwiftUI finishes its layout pass, then signal ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.restoreWidths()
                self?.ready.wrappedValue = true
            }
        }

        private func captureDefaultWidths() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                let key = column.headerCell.stringValue
                if !key.isEmpty {
                    defaultWidths[key] = Double(column.width)
                }
            }
        }

        private static func findTableView(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for subview in view.subviews {
                if let found = findTableView(in: subview) { return found }
            }
            return nil
        }

        private func restoreWidths() {
            guard let tableView,
                  let saved = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double],
                  !saved.isEmpty else { return }
            isRestoring = true
            for column in tableView.tableColumns {
                let key = column.headerCell.stringValue
                if !key.isEmpty, let width = saved[key] {
                    column.width = CGFloat(width)
                }
            }
            isRestoring = false
        }

        private func observeReset() {
            resetObservation = NotificationCenter.default.addObserver(
                forName: .resetColumns,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resetToDefaults()
                }
            }
        }

        private func resetToDefaults() {
            guard let tableView else { return }
            isRestoring = true
            for column in tableView.tableColumns {
                let key = column.headerCell.stringValue
                if !key.isEmpty, let width = defaultWidths[key] {
                    column.width = CGFloat(width)
                }
            }
            isRestoring = false
        }

        private func observeResizes() {
            guard let tableView else { return }
            columnObservations = tableView.tableColumns.map { column in
                column.observe(\.width, options: [.new, .old]) { [weak self] _, change in
                    guard change.oldValue != change.newValue else { return }
                    MainActor.assumeIsolated {
                        self?.scheduleWidthSave()
                    }
                }
            }
        }

        private func scheduleWidthSave() {
            guard !isRestoring else { return }
            debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.saveWidths()
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        private func saveWidths() {
            guard let tableView else { return }
            var widths: [String: Double] = [:]
            for column in tableView.tableColumns {
                let key = column.headerCell.stringValue
                if !key.isEmpty {
                    widths[key] = Double(column.width)
                }
            }
            UserDefaults.standard.set(widths, forKey: userDefaultsKey)
        }

        deinit {
            if let resetObservation { NotificationCenter.default.removeObserver(resetObservation) }
        }
    }
}
