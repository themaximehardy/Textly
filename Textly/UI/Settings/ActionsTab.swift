import SwiftUI

struct ActionsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?

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
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                HStack {
                    TextField("Model", text: $action.model, prompt: Text("Default: \(store.settings.defaultModel)"))
                    Button("Browse…") { showModelPicker = true }
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
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(selection: $action.model)
        }
    }
}
