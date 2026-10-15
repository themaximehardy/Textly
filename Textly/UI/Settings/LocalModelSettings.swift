import SwiftUI

/// Server address and model for local models (Ollama, LM Studio, or any OpenAI-compatible server).
/// Used in Settings › General and in the setup window.
struct LocalModelSettings: View {
    @ObservedObject var store: SettingsStore
    var compact = false
    @ObservedObject private var catalog = LocalModelCatalog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Server", text: $store.settings.localBaseURL, prompt: Text(LocalServer.ollama))
                    .labelsHidden()
                    .frame(width: 230)
                    .onSubmit { refresh() }
                Menu("Presets") {
                    Button("Ollama (localhost:11434)") { use(LocalServer.ollama) }
                    Button("LM Studio (localhost:1234)") { use(LocalServer.lmStudio) }
                }
                .fixedSize()
                Button(catalog.isLoading ? "Connecting…" : "Connect") { refresh() }
                    .disabled(catalog.isLoading)
            }
            HStack(spacing: 8) {
                if catalog.models.isEmpty {
                    TextField("Model", text: $store.settings.localModel, prompt: Text("Model, e.g. llama3.2"))
                        .labelsHidden()
                        .frame(width: 230)
                } else {
                    Picker("Model", selection: $store.settings.localModel) {
                        if !catalog.models.contains(where: { $0.id == store.settings.localModel }) {
                            Text(store.settings.localModel.isEmpty ? "Choose a model" : store.settings.localModel)
                                .tag(store.settings.localModel)
                        }
                        ForEach(catalog.models) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }
                if let status = catalog.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(catalog.isReachable || catalog.isLoading ? Color.secondary : Color.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !compact {
                Text("Install [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai), download a model (Llama, Mistral, Qwen, Gemma…), start the server, then press Connect. Your text never leaves your Mac and it's free. Small models are fast but less accurate than the best cloud models.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await reload()
        }
    }

    private func use(_ address: String) {
        store.settings.localBaseURL = address
        refresh()
    }

    private func refresh() {
        Task { await reload() }
    }

    private func reload() async {
        await catalog.reload(address: store.settings.localBaseURL)
        if store.settings.localModel.trimmingCharacters(in: .whitespaces).isEmpty, let first = catalog.models.first {
            store.settings.localModel = first.id
        }
    }
}
