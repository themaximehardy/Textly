import AppKit
import Combine
import SwiftUI
import Carbon.HIToolbox

/// The heart of the app: menu bar icon, global shortcuts, the palette, running actions.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    static let shared = AppController()

    let store = SettingsStore.shared
    let palette = PaletteModel()

    private var statusItem: NSStatusItem?
    private var panel: PalettePanel?
    private var hosting: NSHostingView<PaletteView>?
    private var keyMonitor: Any?
    private var capture: CapturedSelection?
    private var currentTask: Task<Void, Never>?
    private var lastRun: (action: TextAction, language: String?)?
    private var cancellables = Set<AnyCancellable>()
    private var anchorPoint: NSPoint = .zero
    private var anchorRect: NSRect = .zero
    private var isClosingPanel = false

    // MARK: - Start

    func start() {
        AppLogos.apply(store.settings.appLogo)
        store.$settings
            .map(\.appLogo)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { logo in
                MainActor.assumeIsolated { AppLogos.apply(logo) }
            }
            .store(in: &cancellables)

        setupStatusItem()
        wirePalette()
        registerHotkeys()

        store.$settings
            .map(\.hotkeyBindings)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.registerHotkeys() }
            }
            .store(in: &cancellables)

        palette.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.paletteContentChanged() }
            }
            .store(in: &cancellables)

        _ = NotificationCenter.default.addObserver(forName: .textlyRecordingChanged, object: nil, queue: .main) { [weak self] note in
            let recording = (note.object as? Bool) ?? false
            MainActor.assumeIsolated {
                if recording {
                    HotkeyCenter.shared.unregisterAll()
                } else {
                    self?.registerHotkeys()
                }
            }
        }

        if !store.settings.hasCompletedOnboarding || !store.hasAPIKey || !Permissions.isTrusted {
            OnboardingWindowController.shared.show()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Textly"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        setBusy(false)

        store.$settings
            .map(\.menuBarIcon)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.setBusy(false) }
            }
            .store(in: &cancellables)
    }

    private func statusImage(busy: Bool) -> NSImage? {
        let image = MenuBarIcons.image(busy ? "hourglass" : store.settings.menuBarIcon)
        image?.isTemplate = true
        return image
    }

    private func setBusy(_ busy: Bool) {
        statusItem?.button?.image = statusImage(busy: busy)
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { self.rebuildMenu(menu) }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let paletteTitle = store.settings.paletteHotkey.map { "Open palette   \($0.display)" } ?? "Open palette"
        menu.addItem(menuItem(paletteTitle, #selector(menuOpenPalette)))
        menu.addItem(.separator())

        for item in buildItems() {
            if case .translateAny = item.kind { continue }
            var title = item.title
            if case .action(let id) = item.kind, let shortcut = action(id)?.shortcut {
                title += "   \(shortcut.display)"
            }
            let entry = menuItem(title, #selector(menuRunEntry(_:)))
            entry.representedObject = item.kind
            entry.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil)
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(menuItem("Setup guide…", #selector(openOnboarding)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Textly", #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func menuOpenPalette() {
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // let the menu close first
            await self.openPalette()
        }
    }

    @objc func menuRunEntry(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? PaletteItem.Kind else { return }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            switch kind {
            case .action(let id):
                if let action = self.action(id) { await self.runDirect(action, language: nil) }
            case .translate(let id, let language):
                if let action = self.action(id) { await self.runDirect(action, language: language) }
            case .translateAny:
                await self.openPalette(startInLanguages: true)
            }
        }
    }

    @objc func openSettings() {
        closePalette()
        SettingsWindowController.shared.show()
    }

    @objc func openOnboarding() {
        OnboardingWindowController.shared.show()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Shortcuts

    private func registerHotkeys() {
        let center = HotkeyCenter.shared
        center.unregisterAll()

        if let hotkey = store.settings.paletteHotkey {
            center.register(hotkey) { [weak self] in
                Task { await self?.openPalette() }
            }
        }

        for action in store.settings.actions {
            guard let hotkey = action.shortcut else { continue }
            let id = action.id
            center.register(hotkey) { [weak self] in
                guard let self, let current = self.action(id) else { return }
                Task { await self.runDirect(current, language: nil) }
            }
        }
    }

    // MARK: - Entry points

    /// Shortcut or menu: grab the selection and show the palette next to it.
    func openPalette(startInLanguages: Bool = false) async {
        if panel?.isVisible == true {
            cancelAndClose()
            return
        }
        guard ensureReady() else { return }
        guard let selection = await SelectionService.capture() else {
            Toast.shared.show("Select some text first", icon: "text.cursor")
            return
        }
        capture = selection
        preparePalette()
        if startInLanguages { palette.showLanguages() }
        showPanel()
    }

    /// An action's own shortcut (or the menu bar): run it straight away.
    func runDirect(_ action: TextAction, language: String?) async {
        if action.isTranslate && language == nil {
            await openPalette(startInLanguages: true)
            return
        }
        guard ensureReady() else { return }
        closePalette()
        guard let selection = await SelectionService.capture() else {
            Toast.shared.show("Select some text first", icon: "text.cursor")
            return
        }
        capture = selection
        preparePalette()
        execute(action, language: language)
    }

    private func ensureReady() -> Bool {
        if !store.hasAPIKey {
            Toast.shared.show("Add your OpenRouter API key first", icon: "key")
            OnboardingWindowController.shared.show()
            return false
        }
        if !Permissions.isTrusted {
            Toast.shared.show("Textly needs Accessibility permission", icon: "lock")
            OnboardingWindowController.shared.show()
            return false
        }
        return true
    }

    // MARK: - Running an action

    private func execute(_ action: TextAction, language: String?) {
        guard let capture else { return }
        let settings = store.settings
        let replaceDirectly = settings.paletteStyle == .list && action.output == .replace
        let title = language.map { "Translate to \($0)" } ?? action.name
        if let language { store.noteRecent(language) }
        lastRun = (action, language)
        currentTask?.cancel()

        if !replaceDirectly && panel?.isVisible != true {
            showPanel()
        }
        if panel?.isVisible == true {
            palette.startWorking(title: title)
        } else {
            Toast.shared.show("\(title)…", spinning: true, duration: nil)
            HotkeyCenter.shared.setEscapeHandler { [weak self] in self?.cancelRun() }
        }
        setBusy(true)

        let parts = TextCleanup.split(capture.text)
        let prompt = PromptBuilder.messages(for: action, language: language, text: parts.core, settings: settings)
        let chosenModel = action.model.trimmingCharacters(in: .whitespaces)
        let request = CompletionRequest(
            apiKey: store.apiKey,
            model: chosenModel.isEmpty ? settings.defaultModel : chosenModel,
            system: prompt.system,
            user: prompt.user,
            temperature: action.temperature,
            noTraining: settings.noTraining,
            fastMode: settings.fastMode
        )
        let showDiff = action.builtin != "summarise" && !action.isTranslate

        currentTask = Task { [weak self] in
            do {
                let response = try await OpenRouterClient.complete(request)
                UsageStore.shared.record(
                    model: request.model,
                    promptTokens: response.promptTokens,
                    completionTokens: response.completionTokens,
                    reportedCost: response.cost
                )
                try Task.checkCancellation()
                let cleaned = TextCleanup.clean(response.content, original: parts.core)
                await self?.finish(
                    result: parts.lead + cleaned + parts.trail,
                    core: cleaned,
                    original: parts.core,
                    title: title,
                    replaceDirectly: replaceDirectly,
                    showDiff: showDiff
                )
            } catch {
                if error is CancellationError { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func finish(result: String, core: String, original: String, title: String, replaceDirectly: Bool, showDiff: Bool) async {
        setBusy(false)
        HotkeyCenter.shared.setEscapeHandler(nil)
        currentTask = nil
        if replaceDirectly {
            let target = capture
            closePalette()
            Toast.shared.hide()
            await SelectionService.replace(with: result, target: target)
        } else {
            Toast.shared.hide()
            if panel?.isVisible != true { showPanel() }
            palette.showResult(title: title, full: result, core: core, original: original, showDiff: showDiff)
        }
    }

    private func fail(_ message: String) {
        setBusy(false)
        HotkeyCenter.shared.setEscapeHandler(nil)
        currentTask = nil
        if panel?.isVisible == true {
            palette.showError(message)
        } else {
            Toast.shared.show(message, icon: "exclamationmark.triangle", duration: 5)
        }
    }

    private func cancelRun() {
        currentTask?.cancel()
        currentTask = nil
        setBusy(false)
        HotkeyCenter.shared.setEscapeHandler(nil)
        Toast.shared.hide()
    }

    // MARK: - Palette wiring

    private func wirePalette() {
        palette.onRun = { [weak self] kind in self?.run(kind) }
        palette.onRunLanguage = { [weak self] language in self?.runTranslate(to: language) }
        palette.onReplace = { [weak self] in self?.replaceWithResult() }
        palette.onCopy = { [weak self] in self?.copyResult() }
        palette.onRetry = { [weak self] in self?.retry() }
        palette.onClose = { [weak self] in self?.cancelAndClose() }
        palette.onOpenSettings = { [weak self] in self?.openSettings() }
        palette.onTogglePin = { [weak self] language in
            guard let self else { return }
            self.store.togglePin(language)
            self.palette.pinned = self.store.settings.pinnedLanguages
            self.palette.items = self.buildItems()
        }
    }

    private func preparePalette() {
        let settings = store.settings
        palette.configure(
            style: settings.paletteStyle,
            items: buildItems(),
            pinned: settings.pinnedLanguages,
            recent: settings.recentLanguages,
            source: capture?.text ?? "",
            brandIcon: settings.menuBarIcon
        )
    }

    private func buildItems() -> [PaletteItem] {
        let settings = store.settings
        var items: [PaletteItem] = []
        for action in settings.actions {
            if action.isTranslate {
                for language in settings.pinnedLanguages {
                    items.append(PaletteItem(
                        id: "lang:\(language)",
                        kind: .translate(action.id, language),
                        title: "Translate to \(language)",
                        icon: action.icon,
                        keySource: language,
                        isCustom: false
                    ))
                }
                items.append(PaletteItem(
                    id: "lang:any",
                    kind: .translateAny(action.id),
                    title: "Translate to…",
                    icon: "character.bubble",
                    keySource: "translate",
                    isCustom: false
                ))
            } else {
                items.append(PaletteItem(
                    id: action.id.uuidString,
                    kind: .action(action.id),
                    title: action.name,
                    icon: action.icon,
                    keySource: action.name,
                    isCustom: action.builtin == nil
                ))
            }
        }
        return PaletteItem.assignKeys(items)
    }

    private func action(_ id: UUID) -> TextAction? {
        store.settings.actions.first { $0.id == id }
    }

    private func run(_ kind: PaletteItem.Kind) {
        switch kind {
        case .action(let id):
            if let action = action(id) { execute(action, language: nil) }
        case .translate(let id, let language):
            if let action = action(id) { execute(action, language: language) }
        case .translateAny:
            palette.showLanguages()
        }
    }

    private func runTranslate(to language: String) {
        guard let action = store.settings.actions.first(where: { $0.isTranslate }) else { return }
        execute(action, language: language)
    }

    private func replaceWithResult() {
        let text = palette.resultFull
        let target = capture
        closePalette()
        Task { await SelectionService.replace(with: text, target: target) }
    }

    private func copyResult() {
        let text = palette.resultCore
        closePalette()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.shared.show("Copied", icon: "doc.on.doc")
    }

    private func retry() {
        guard let last = lastRun else { return }
        let fresh = action(last.action.id) ?? last.action
        execute(fresh, language: last.language)
    }

    private func cancelAndClose() {
        cancelRun()
        closePalette()
    }

    // MARK: - Panel

    private func makePanel() -> PalettePanel {
        let panel = PalettePanel.make()
        let host = NSHostingView(rootView: PaletteView(model: palette))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.onResignKey = { [weak self] in self?.panelResignedKey() }
        self.hosting = host
        self.panel = panel
        return panel
    }

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        let mouse = NSEvent.mouseLocation
        anchorRect = capture?.anchor ?? NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
        anchorPoint = NSPoint(x: anchorRect.minX, y: anchorRect.minY - 6)
        resizePanelToFit(force: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    /// SwiftUI may lay out a moment after the state changes, so measure twice.
    private func paletteContentChanged() {
        resizePanelToFit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.resizePanelToFit() }
        }
    }

    private func resizePanelToFit(force: Bool = false) {
        guard let panel, let hosting, panel.isVisible || force else { return }
        let size = hosting.fittingSize
        if size.width > 0, size.height > 0, size != panel.frame.size {
            panel.setContentSize(size)
        }
        positionPanel()
        panel.invalidateShadow()
    }

    /// Below the selection when there is room, otherwise above it. Always fully on screen.
    private func positionPanel() {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(anchorPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        var top = anchorPoint.y
        if top - size.height < visible.minY + 8 {
            top = anchorRect.maxY + 6 + size.height
        }
        top = min(max(top, visible.minY + size.height + 8), visible.maxY - 8)
        let x = min(max(anchorPoint.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
    }

    func closePalette() {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
        isClosingPanel = true
        panel.orderOut(nil)
        isClosingPanel = false
        palette.screen = .menu
    }

    private func panelResignedKey() {
        guard !isClosingPanel, panel?.isVisible == true else { return }
        cancelAndClose()
    }

    // MARK: - Keyboard inside the palette

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleKey(event) }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow else { return false }
        let code = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        let isReturn = code == kVK_Return || code == kVK_ANSI_KeypadEnter

        if code == kVK_Escape {
            if palette.screen == .languages {
                palette.backToMenu()
            } else {
                cancelAndClose()
            }
            return true
        }
        if command && characters == "," {
            openSettings()
            return true
        }
        // Swallow other ⌘ shortcuts (e.g. ⌘Q, ⌘W) so they don't reach Textly's hidden menu.
        // Keep the editing ones for the language search field, plus ⌘C / ⌘R / ⌘P handled below.
        if command && !["c", "v", "x", "a", "z", "r", "p"].contains(characters) {
            return true
        }

        switch palette.screen {
        case .menu:
            return handleMenuKeys(code: code, characters: characters, flags: flags)

        case .languages:
            if code == kVK_UpArrow { palette.moveLanguage(-1); return true }
            if code == kVK_DownArrow { palette.moveLanguage(1); return true }
            if isReturn { palette.chooseHighlightedLanguage(); return true }
            if command && characters == "p" { palette.togglePinHighlighted(); return true }
            return false

        case .working:
            return true

        case .result:
            if isReturn { replaceWithResult(); return true }
            if command && characters == "c" { copyResult(); return true }
            if command && characters == "r" { retry(); return true }
            if palette.style == .preview { return handleMenuKeys(code: code, characters: characters, flags: flags) }
            return false

        case .error:
            if isReturn || (command && characters == "r") { retry(); return true }
            if palette.style == .preview { return handleMenuKeys(code: code, characters: characters, flags: flags) }
            return false
        }
    }

    private func handleMenuKeys(code: Int, characters: String, flags: NSEvent.ModifierFlags) -> Bool {
        if code == kVK_UpArrow { palette.move(-1); return true }
        if code == kVK_DownArrow { palette.move(1); return true }
        if code == kVK_Return || code == kVK_ANSI_KeypadEnter { palette.runHighlighted(); return true }
        guard flags.intersection([.command, .control, .option]).isEmpty, let letter = characters.first else { return false }
        if let item = palette.items.first(where: { $0.key == letter }) {
            palette.run(item)
        }
        return true
    }
}
