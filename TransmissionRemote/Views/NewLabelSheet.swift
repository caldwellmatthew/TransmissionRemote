import SwiftUI

struct NewLabelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var labelText = ""
    var onAdd: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Label")
                .font(.headline)

            TextField("", text: $labelText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { addAndDismiss() }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addAndDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding()
    }

    private var trimmed: String {
        labelText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addAndDismiss() {
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        dismiss()
    }
}
