import SwiftUI

/// Invisible NSView that finds its enclosing NSToolbarItem and sets isBordered = false.
/// Use as .background(ToolbarItemBorderRemover()) on a toolbar item's content.
struct ToolbarItemBorderRemover: NSViewRepresentable {
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
