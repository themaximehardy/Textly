import SwiftUI

/// Searchable list of every model on OpenRouter, with prices.
struct ModelPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = ModelCatalog.shared
    @State private var query = ""

    private var loading: Bool { catalog.isLoading && catalog.models.isEmpty }
    private var errorText: String? { catalog.models.isEmpty ? catalog.errorText : nil }

    private var filtered: [ORModel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return catalog.models }
        return catalog.models.filter { $0.id.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search models, e.g. gemini, claude, gpt, mistral", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                Text(errorText)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { model in
                    Button {
                        selection = model.id
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.priceLabel)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if model.id == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Text("Prices are per million tokens (input / output). A typical fix uses well under a thousand.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 620, height: 500)
        .task {
            if catalog.models.isEmpty { await catalog.reload() }
        }
    }
}
