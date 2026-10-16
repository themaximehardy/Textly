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
    private var lastRun: (action: TextAction, language: String?, review: Bool)?
    /// The last text Textly pasted, so ⌃⌥Z (Revert) can put the original back.
    private var lastReplacement: Replacement?
    /// Bumped for every run (and cancel), so late streaming updates from an old run are ignored.
    private var runID = 0
    private var relay: StreamRelay?
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
        ServicesProvider.shared.install()

        HistoryStore.shared.setPersistent(store.settings.keepHistory)
        store.$settings
            .map(\.keepHistory)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { keep in
                MainActor.assumeIsolated { HistoryStore.shared.setPersistent(keep) }
            }
            .store(in: &cancellables)

        UpdateChecker.shared.start { [weak self] in
            self?.store.settings.checkForUpdates ?? false
        }

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

        let needsKey = store.settings.provider == .openRouter && !store.hasAPIKey
        if !store.settings.hasCompletedOnboarding || needsKey || !Permissions.isTrusted {
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
        let revertTitle = "Revert Last Change" + (store.settings.revertHotkey.map { "   \($0.display)" } ?? "")
        if lastReplacement != nil {
            let revert = menuItem(revertTitle, #selector(menuRevert))
            revert.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
            menu.addItem(revert)
        } else {
            let revert = NSMenuItem(title: revertTitle, action: nil, keyEquivalent: "")
            revert.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
            revert.isEnabled = false
            menu.addItem(revert)
        }
        menu.addItem(historyMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(menuItem("Setup guide…", #selector(openOnboarding)))
        menu.addItem(menuItem("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Textly", #selector(quit), key: "q"))
    }

    // MARK: History menu

    private func historyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Recent Results", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let submenu = NSMenu()
        let entries = HistoryStore.shared.entries
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No results yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        for entry in entries {
            let row = NSMenuItem(title: "\(entry.title): \(Self.snippet(entry.result))", action: nil, keyEquivalent: "")
            let actions = NSMenu()
            let when = formatter.localizedString(for: entry.date, relativeTo: Date())
            let header = NSMenuItem(title: [entry.appName, when].compactMap { $0 }.joined(separator: " · "), action: nil, keyEquivalent: "")
            header.isEnabled = false
            actions.addItem(header)
            actions.addItem(.separator())
            for (title, selector) in [
                ("Paste Result", #selector(pasteHistoryResult(_:))),
                ("Copy Result", #selector(copyHistoryResult(_:))),
                ("Copy Original", #selector(copyHistoryOriginal(_:))),
            ] {
                let action = menuItem(title, selector)
                action.representedObject = entry.id
                actions.addItem(action)
            }
            row.submenu = actions
            submenu.addItem(row)
        }
        if !entries.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(menuItem("Clear History", #selector(clearHistory)))
        }
        item.submenu = submenu
        return item
    }

    private static func snippet(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 42 ? String(trimmed.prefix(40)) + "…" : trimmed
    }

    private func historyEntry(_ sender: NSMenuItem) -> HistoryEntry? {
        guard let id = sender.representedObject as? UUID else { return nil }
        return HistoryStore.shared.entries.first { $0.id == id }
    }

    @objc func pasteHistoryResult(_ sender: NSMenuItem) {
        guard let entry = historyEntry(sender) else { return }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await SelectionService.replace(with: entry.result, target: nil)
        }
    }

    @objc func copyHistoryResult(_ sender: NSMenuItem) {
        guard let entry = historyEntry(sender) else { return }
        copyToClipboard(entry.result)
    }

    @objc func copyHistoryOriginal(_ sender: NSMenuItem) {
        guard let entry = historyEntry(sender) else { return }
        copyToClipboard(entry.original)
    }

    @objc func clearHistory() {
        HistoryStore.shared.clear()
    }

    @objc func checkForUpdates() {
        Task { await UpdateChecker.shared.check(userInitiated: true) }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.shared.show("Copied", icon: "doc.on.doc")
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
        if let hotkey = store.settings.revertHotkey {
            center.register(hotkey) { [weak self] in
                Task { await self?.revertLast() }
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

    /// Shortcut, menu or Services: grab the selection and show the palette next to it.
    /// `preset` is text macOS already handed over (Services), so there's nothing to capture.
    func openPalette(startInLanguages: Bool = false, preset: CapturedSelection? = nil) async {
        if panel?.isVisible == true {
            cancelAndClose()
            if preset == nil { return }
        }
        guard ensureReady() else { return }
        var captured = preset
        if captured == nil {
            captured = await SelectionService.capture()
        }
        guard let selection = captured else {
            Toast.shared.show("Select some text first", icon: "text.cursor")
            return
        }
        capture = selection
        preparePalette()
        if startInLanguages { palette.showLanguages() }
        showPanel()
    }

    /// An action's own shortcut (or the menu bar): run it straight away.
    func runDirect(_ action: TextAction, language: String?, preset: CapturedSelection? = nil) async {
        if action.isTranslate && language == nil {
            await openPalette(startInLanguages: true, preset: preset)
            return
        }
        guard ensureReady() else { return }
        closePalette()
        var captured = preset
        if captured == nil {
            captured = await SelectionService.capture()
        }
        guard let selection = captured else {
            Toast.shared.show("Select some text first", icon: "text.cursor")
            return
        }
        capture = selection
        preparePalette()
        execute(action, language: language)
    }

    private func ensureReady() -> Bool {
        switch store.settings.provider {
        case .openRouter:
            if !store.hasAPIKey {
                Toast.shared.show("Add your OpenRouter API key first", icon: "key")
                OnboardingWindowController.shared.show()
                return false
            }
        case .local:
            if store.settings.localModel.trimmingCharacters(in: .whitespaces).isEmpty {
                Toast.shared.show("Choose a local model in Settings", icon: "desktopcomputer")
                SettingsWindowController.shared.show()
                return false
            }
        }
        if !Permissions.isTrusted {
            Toast.shared.show("Textly needs Accessibility permission", icon: "lock")
            OnboardingWindowController.shared.show()
            return false
        }
        return true
    }

    // MARK: - Running an action

    /// `review`: list each change to accept or reject (⇧ in the palette), whatever the action's setting.
    private func execute(_ action: TextAction, language: String?, review forceReview: Bool = false) {
        guard let capture else { return }
        let settings = store.settings
        // Stop any run still in flight first, so its result can't land after this one.
        currentTask?.cancel()
        relay?.stop()
        runID += 1
        let id = runID
        let prepared: PreparedRun
        do {
            prepared = try ActionRunner.prepare(action: action, language: language, text: capture.text, settings: settings, apiKey: store.apiKey)
        } catch {
            fail(error.localizedDescription)
            return
        }
        let mode: OutputMode = forceReview ? .review : action.output
        let replaceDirectly = settings.paletteStyle == .list && mode == .replace
        let wantsReview = mode == .review
        if let language { store.noteRecent(language) }
        lastRun = (action, language, forceReview)

        if !replaceDirectly && panel?.isVisible != true {
            showPanel()
        }
        if panel?.isVisible == true {
            palette.startWorking(title: prepared.title)
        } else {
            Toast.shared.show("\(prepared.title)…", spinning: true, duration: nil)
            HotkeyCenter.shared.setEscapeHandler { [weak self] in self?.cancelRun() }
        }
        setBusy(true)

        // The answer appears word by word in the palette while it is written.
        let relay = StreamRelay { [weak self] text in
            guard let self, self.runID == id, self.panel?.isVisible == true else { return }
            self.palette.showPartial(text)
        }
        self.relay = relay
        let appName = capture.app?.localizedName

        currentTask = Task { [weak self] in
            do {
                let output = try await ActionRunner.run(prepared) { text in relay.push(text) }
                relay.stop()
                guard let self, self.runID == id else { return }
                HistoryStore.shared.add(title: prepared.title, original: output.original, result: output.core, appName: appName)
                await self.finish(output: output, title: prepared.title, replaceDirectly: replaceDirectly, showDiff: prepared.showDiff, review: wantsReview)
            } catch {
                relay.stop()
                if error is CancellationError { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                guard let self, self.runID == id else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finish(output: RunOutput, title: String, replaceDirectly: Bool, showDiff: Bool, review: Bool) async {
        setBusy(false)
        HotkeyCenter.shared.setEscapeHandler(nil)
        currentTask = nil
        if replaceDirectly {
            let target = capture
            closePalette()
            Toast.shared.hide()
            await paste(output.full, over: target)
        } else {
            Toast.shared.hide()
            if panel?.isVisible != true { showPanel() }
            palette.showResult(title: title, output: output, showDiff: showDiff, review: review)
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
        runID += 1
        relay?.stop()
        relay = nil
        currentTask?.cancel()
        currentTask = nil
        setBusy(false)
        HotkeyCenter.shared.setEscapeHandler(nil)
        Toast.shared.hide()
    }

    // MARK: - Palette wiring

    private func wirePalette() {
        palette.onRun = { [weak self] kind, review in self?.run(kind, review: review) }
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

    private func run(_ kind: PaletteItem.Kind, review: Bool = false) {
        switch kind {
        case .action(let id):
            if let action = action(id) { execute(action, language: nil, review: review) }
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
        let text = palette.textToInsert
        let target = capture
        closePalette()
        Task { await self.paste(text, over: target) }
    }

    /// Pastes a result over the selection and remembers it for Revert.
    private func paste(_ text: String, over target: CapturedSelection?) async {
        let replacement = await SelectionService.replace(with: text, target: target)
        guard replacement.inserted != replacement.original else { return }
        lastReplacement = replacement
        if let revert = store.settings.revertHotkey {
            Toast.shared.show("Done · \(revert.display) to revert", icon: "checkmark", duration: 2.2)
        }
    }

    // MARK: - Revert

    func revertLast() async {
        guard let last = lastReplacement else {
            Toast.shared.show("Nothing to revert yet", icon: "arrow.uturn.backward")
            return
        }
        guard Permissions.isTrusted else {
            Toast.shared.show("Textly needs Accessibility permission", icon: "lock")
            return
        }
        closePalette()
        let outcome = await SelectionService.revert(last)
        switch outcome {
        case .restored(let reverse):
            // Pressing the shortcut again swaps back to the result.
            lastReplacement = reverse
            Toast.shared.show("Original text back", icon: "arrow.uturn.backward", duration: 2)
        case .undone:
            lastReplacement = nil
            Toast.shared.show("Undone (⌘Z)", icon: "arrow.uturn.backward", duration: 2)
        }
    }

    @objc func menuRevert() {
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self.revertLast()
        }
    }

    private func copyResult() {
        let text = palette.textToCopy
        closePalette()
        copyToClipboard(text)
    }

    private func retry() {
        guard let last = lastRun else { return }
        let fresh = action(last.action.id) ?? last.action
        execute(fresh, language: last.language, review: last.review)
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
        guard let panel, hosting != nil, panel.isVisible || force else { return }
        let size = idealPanelSize()
        if size != panel.frame.size {
            panel.setContentSize(size)
        }
        positionPanel()
        panel.invalidateShadow()
    }

    /// The width is fixed per style; the height is measured from the SwiftUI content.
    /// (The panel's own hosting view doesn't size itself, so it's measured separately.)
    private func idealPanelSize() -> NSSize {
        let width = (palette.style == .preview && palette.screen != .languages)
            ? PaletteMetrics.previewWidth
            : PaletteMetrics.listWidth
        let measurer = NSHostingController(rootView: PaletteView(model: palette))
        let measured = measurer.sizeThatFits(in: NSSize(width: width, height: 2000))
        let fallback = panel?.frame.height ?? 300
        let height = measured.height > 20 ? min(ceil(measured.height), 900) : fallback
        return NSSize(width: width, height: height)
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

        case .review:
            if code == kVK_UpArrow { palette.moveReview(-1); return true }
            if code == kVK_DownArrow { palette.moveReview(1); return true }
            if code == kVK_Space { palette.toggleHighlightedChange(); return true }
            if isReturn { replaceWithResult(); return true }
            if command && characters == "c" { copyResult(); return true }
            if command && characters == "r" { retry(); return true }
            if palette.style == .preview && !command { return handleMenuKeys(code: code, characters: characters, flags: flags) }
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
