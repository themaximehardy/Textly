import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ActionsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?
    @State private var packMessage: String?

    private var selectedAction: TextAction? {
        guard let selection else { return nil }
        return store.settings.actions.first { $0.id == selection }
    }

    private var canDelete: Bool {
        selectedAction.map { $0.builtin == nil } ?? false
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.settings.actions) { action in
                        Label(action.name, systemImage: action.icon)
                    }
                    .onMove { source, destination in
                        store.settings.actions.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.sidebar)
                Divider()
                HStack(spacing: 4) {
                    Button {
                        addAction()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 20)
                    }
                    .help("New action")
                    Button {
                        deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 20, height: 20)
                    }
                    .help("Delete action (built-in actions can't be deleted)")
                    .disabled(!canDelete)
                    Spacer()
                    Button("Import…") { importPack() }
                        .help("Add actions from a file someone sent you (a Textly action pack)")
                    Menu("Export…") {
                        Button("Export all my actions…") { exportPack(onlySelected: false) }
                            .disabled(!store.settings.actions.contains { $0.builtin == nil })
                        Button("Export “\(selectedAction?.name ?? "this action")”…") { exportPack(onlySelected: true) }
                            .disabled(selectedAction == nil)
                        Divider()
                        Link("Get action packs on GitHub", destination: URL(string: "\(AppInfo.homepage)/tree/main/docs/packs")!)
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Save your actions to a file to send to someone")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 220)

            Divider()

            if let index = store.settings.actions.firstIndex(where: { $0.id == selection }) {
                ActionEditor(store: store, action: $store.settings.actions[index])
                    .id(selection)
            } else {
                Text("Select an action, or press + to create your own.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = store.settings.actions.first?.id }
        }
        .alert("Action packs", isPresented: Binding(get: { packMessage != nil }, set: { if !$0 { packMessage = nil } })) {
            Button("OK") { packMessage = nil }
        } message: {
            Text(packMessage ?? "")
        }
    }

    // MARK: Packs

    private func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Textly action pack (.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try ActionPack.decode(Data(contentsOf: url))
            let added = store.importPack(pack)
            if let last = store.settings.actions.last, added > 0 { selection = last.id }
            packMessage = added == 1
                ? "Added 1 action from “\(pack.name)”."
                : "Added \(added) actions from “\(pack.name)”."
        } catch {
            packMessage = error.localizedDescription
        }
    }

    private func exportPack(onlySelected: Bool) {
        let actions: [TextAction]
        let name: String
        if onlySelected, let action = selectedAction {
            actions = [action]
            name = action.name
        } else {
            actions = store.settings.actions.filter { $0.builtin == nil }
            name = "My Textly actions"
        }
        guard !actions.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(name).json"
        panel.message = "Shortcuts aren't included. Anyone with Textly can import this file in Settings › Actions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ActionPack(name: name, actions: actions).encoded().write(to: url, options: .atomic)
        } catch {
            packMessage = "Couldn't save the pack: \(error.localizedDescription)"
        }
    }

    private func addAction() {
        let action = TextAction(
            name: "New action",
            icon: "wand.and.stars",
            prompt: DefaultPrompts.newActionTemplate,
            output: .replace
        )
        store.settings.actions.append(action)
        selection = action.id
    }

    private func deleteSelected() {
        guard let id = selection, canDelete else { return }
        selection = nil
        Task { @MainActor in
            store.settings.actions.removeAll { $0.id == id }
            selection = store.settings.actions.first?.id
        }
    }
}

struct ActionEditor: View {
    @ObservedObject var store: SettingsStore
    @Binding var action: TextAction
    @State private var showModelPicker = false
    @State private var sample = DefaultPrompts.sampleText(for: SettingsStore.shared.settings.writingProfile)
    @State private var tryLanguage = SettingsStore.shared.settings.pinnedLanguages.first ?? "English"
    @State private var tryResult = ""
    @State private var tryStatus = ""
    @State private var tryTask: Task<Void, Never>?
    @State private var tryRunID = 0

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $action.name)
                LabeledContent("Icon") {
                    IconPicker(selection: $action.icon)
                }
                Picker("Result", selection: $action.output) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text(resultHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Shortcut") {
                    ShortcutRecorder(hotkey: $action.shortcut)
                }
                if action.isTranslate {
                    Text("This shortcut opens the language list. Pinned languages are set in General.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Model") {
                if store.settings.provider == .local {
                    LabeledContent("Model") {
                        Text("\(store.settings.localModel.isEmpty ? "No local model chosen" : store.settings.localModel) (local)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        TextField("Model", text: $action.model, prompt: Text("Default: \(store.settings.defaultModel)"))
                        Button("Browse…") { showModelPicker = true }
                    }
                }
                LabeledContent("Creativity") {
                    HStack {
                        Slider(value: $action.temperature, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", action.temperature))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            Section {
                Toggle("Include shared rules (Rules & Glossary tab)", isOn: $action.useSharedRules)
                TextEditor(text: $action.prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                if action.isTranslate {
                    Text("{{language}} is replaced by the language you pick.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if action.builtin != nil {
                    HStack {
                        Spacer()
                        Button("Reset to default") { store.resetBuiltin(action.id) }
                    }
                }
            } header: {
                Text("Instructions")
            } footer: {
                Text("Tell the AI what to do with the selected text. Your glossary and the output rules (return only the text) are always added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $sample)
                    .font(.body)
                    .frame(height: 64)
                if action.isTranslate {
                    TextField("Language", text: $tryLanguage)
                }
                HStack {
                    if tryTask == nil {
                        Button("Run") { runTry() }
                            .disabled(sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Stop") { stopTry() }
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Text(tryStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !tryResult.isEmpty {
                    Text(tryResult)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Try it")
            } footer: {
                Text("Runs this action on the text above with your current instructions, so you can tune the prompt before using it for real. Nothing is pasted anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopTry() }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(selection: $action.model)
        }
    }

    private var resultHelp: String {
        switch action.output {
        case .replace:
            return "The selection is replaced as soon as the answer arrives. Hold ⇧ when you pick the action in the palette to review the changes instead, just that once."
        case .show:
            return "The whole result is shown first, with the changes highlighted. ↵ replaces the selection."
        case .review:
            return action.isTranslate || action.builtin == "summarise"
                ? "Each change is listed so you can keep or drop it. Translations and summaries change everything, so they show the whole result instead."
                : "Each change is listed (old → new) so you can keep or drop it one by one, then apply the ones you kept."
        }
    }

    // MARK: Try it

    private func runTry() {
        stopTry()
        let language = action.isTranslate ? tryLanguage.trimmingCharacters(in: .whitespaces) : nil
        let prepared: PreparedRun
        do {
            prepared = try ActionRunner.prepare(
                action: action,
                language: language?.isEmpty == true ? "English" : language,
                text: sample,
                settings: store.settings,
                apiKey: store.apiKey
            )
        } catch {
            tryStatus = error.localizedDescription
            return
        }
        tryRunID += 1
        let id = tryRunID
        tryResult = ""
        tryStatus = "Writing…"
        let started = Date()
        let relay = StreamRelay { text in
            guard id == tryRunID else { return }
            tryResult = text
        }
        tryTask = Task {
            do {
                let output = try await ActionRunner.run(prepared) { text in relay.push(text) }
                relay.stop()
                guard id == tryRunID else { return }
                tryResult = output.core
                let seconds = String(format: "%.1f s", Date().timeIntervalSince(started))
                let tokens = output.completion.promptTokens + output.completion.completionTokens
                var parts = [seconds]
                if tokens > 0 { parts.append("\(tokens) tokens") }
                if let cost = output.completion.cost, prepared.request.endpoint.isOpenRouter { parts.append(Money.format(cost)) }
                tryStatus = parts.joined(separator: " · ")
            } catch {
                relay.stop()
                guard id == tryRunID else { return }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                tryStatus = cancelled ? "Stopped" : error.localizedDescription
            }
            if id == tryRunID { tryTask = nil }
        }
    }

    private func stopTry() {
        guard let task = tryTask else { return }
        task.cancel()
        tryTask = nil
        tryRunID += 1
        tryStatus = "Stopped"
    }
}
