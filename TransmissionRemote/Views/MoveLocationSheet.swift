import SwiftUI

struct MoveLocationSheet: View {
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
