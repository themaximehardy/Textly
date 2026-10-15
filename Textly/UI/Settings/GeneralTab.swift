import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var catalog = ModelCatalog.shared
    @State private var keyDraft = ""
    @State private var editingKey = false
    @State private var keyStatus: String?
    @State private var testing = false
    @State private var showModelPicker = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = Permissions.isTrusted
    @State private var newLanguage = ""

    private var maskedKey: String {
        let key = store.apiKey
        guard key.count > 8 else { return "••••••••" }
        return String(key.prefix(6)) + "••••••••" + String(key.suffix(4))
    }

    private var languageSuggestions: [Languages.Entry] {
        Languages.search(newLanguage, limit: 4).filter { !store.settings.pinnedLanguages.contains($0.name) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $store.settings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("AI")
            } footer: {
                Text(store.settings.provider == .openRouter
                     ? "OpenRouter gives you hundreds of models (Gemini, Claude, GPT, Mistral…) with one key. You pay only for what you use."
                     : "Run a model on your Mac with Ollama or LM Studio. Free and private, but small models are less accurate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if store.settings.provider == .local {
                Section("Local model") {
                    LocalModelSettings(store: store)
                }
            }

            if store.settings.provider == .openRouter {
            Section("OpenRouter") {
                LabeledContent("API key") {
                    if editingKey || !store.hasAPIKey {
                        HStack(spacing: 8) {
                            SecureField("API key", text: $keyDraft, prompt: Text("sk-or-v1-…"))
                                .labelsHidden()
                                .frame(width: 260)
                                .onSubmit { saveKey() }
                            Button("Save") { saveKey() }
                                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            if store.hasAPIKey {
                                Button("Cancel") {
                                    editingKey = false
                                    keyDraft = ""
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(maskedKey)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Change") {
                                keyDraft = ""
                                editingKey = true
                            }
                            Button(testing ? "Testing…" : "Test") { test() }
                                .disabled(testing)
                        }
                    }
                }
                HStack {
                    Link("Get a key on openrouter.ai", destination: URL(string: "https://openrouter.ai/keys")!)
                        .font(.callout)
                    Spacer()
                    if let keyStatus {
                        Text(keyStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Model") {
                LabeledContent("Default model") {
                    HStack(spacing: 8) {
                        TextField("Default model", text: $store.settings.defaultModel, prompt: Text("provider/model"))
                            .labelsHidden()
                            .frame(width: 260)
                        Button("Browse…") { showModelPicker = true }
                    }
                }
                if let model = catalog.model(store.settings.defaultModel), !model.priceLabel.isEmpty {
                    LabeledContent("Price") {
                        Text(model.priceLabel)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Fast mode (skip long reasoning so answers come back quicker)", isOn: $store.settings.fastMode)
                Toggle("Only use providers that don't store or train on my text", isOn: $store.settings.noTraining)
            }
            }

            Section("Palette") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(hotkey: $store.settings.paletteHotkey)
                }
                Picker("Style", selection: $store.settings.paletteStyle) {
                    ForEach(PaletteStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(store.settings.paletteStyle.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Translate") {
                LabeledContent("Pinned languages") {
                    HStack(spacing: 6) {
                        ForEach(store.settings.pinnedLanguages, id: \.self) { language in
                            LanguageChip(name: language) { store.togglePin(language) }
                        }
                    }
                }
                LabeledContent("Add a language") {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Add a language", text: $newLanguage, prompt: Text("e.g. Spanish, Deutsch"))
                                .labelsHidden()
                                .frame(width: 200)
                                .onSubmit { addLanguage(newLanguage) }
                            Button("Add") { addLanguage(newLanguage) }
                                .disabled(newLanguage.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !languageSuggestions.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(languageSuggestions, id: \.self) { entry in
                                    Button(entry.name) { addLanguage(entry.name) }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Text("Pinned languages get their own row and letter in the palette. Any other language is one search away with “Translate to…” (T).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Logo") {
                    HStack(spacing: 6) {
                        ForEach(AppLogos.options, id: \.id) { logo in
                            Button {
                                store.settings.appLogo = logo.id
                            } label: {
                                Image(logo.id)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 34, height: 34)
                                    .padding(3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(store.settings.appLogo == logo.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(logo.label)
                        }
                    }
                }
                LabeledContent("Menu bar icon") {
                    HStack(spacing: 4) {
                        ForEach(MenuBarIcons.options, id: \.self) { icon in
                            Button {
                                store.settings.menuBarIcon = icon
                            } label: {
                                MenuBarIconView(name: icon, size: 14)
                                    .frame(width: 30, height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(store.settings.menuBarIcon == icon ? Color.accentColor.opacity(0.22) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(MenuBarIcons.label(icon))
                        }
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("The logo is used in Textly's windows, alerts and About page. Finder and Launchpad always show the default (Ink) icon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep recent results after quitting Textly", isOn: $store.settings.keepHistory)
                HStack {
                    Text("The last \(HistoryStore.limit) results are in the menu bar › Recent Results, to copy or paste again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { HistoryStore.shared.clear() }
                }
            } header: {
                Text("History")
            } footer: {
                Text("When this is off, history is only kept in memory and disappears when Textly quits.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch Textly at login", isOn: $launchAtLogin)
                HStack {
                    Toggle("Check for updates automatically", isOn: $store.settings.checkForUpdates)
                    Spacer()
                    Button("Check now") {
                        Task { await UpdateChecker.shared.check(userInitiated: true) }
                    }
                }
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                HStack {
                    Label(
                        trusted ? "Accessibility permission granted" : "Accessibility permission needed",
                        systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(trusted ? Color.green : Color.orange)
                    Spacer()
                    if !trusted {
                        Button("Grant…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(selection: $store.settings.defaultModel)
        }
        .onAppear {
            trusted = Permissions.isTrusted
        }
        .task {
            await catalog.loadIfNeeded()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = Permissions.isTrusted
        }
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        store.setAPIKey(key)
        keyDraft = ""
        editingKey = false
        keyStatus = "Saved"
        test()
    }

    private func addLanguage(_ raw: String) {
        let language = raw.trimmingCharacters(in: .whitespaces)
        guard !language.isEmpty else { return }
        if !store.settings.pinnedLanguages.contains(where: { $0.caseInsensitiveCompare(language) == .orderedSame }) {
            store.togglePin(language)
        }
        newLanguage = ""
    }

    private func test() {
        testing = true
        keyStatus = "Checking…"
        let key = store.apiKey
        Task {
            do {
                try await AIClient.checkKey(key)
                keyStatus = "Connected ✓"
            } catch {
                keyStatus = error.localizedDescription
            }
            testing = false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            keyStatus = "Couldn't change login item: \(error.localizedDescription)"
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}
