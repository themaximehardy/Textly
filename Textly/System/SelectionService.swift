import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The text the user selected, and where it came from.
struct CapturedSelection {
    let text: String
    /// The app that owns the selection (re-activated before pasting).
    let app: NSRunningApplication?
    /// Selection bounds in screen coordinates, when the app exposes them.
    let anchor: NSRect?
    /// Set when the selection is inside one of Textly's own windows (e.g. the setup window).
    let ownWindow: NSWindow?
}

/// Reads the selected text in the frontmost app and pastes results back.
/// 1. Accessibility API (no clipboard involved), then
/// 2. fallback: simulate ⌘C, read the clipboard, restore it.
/// Replacing always pastes with ⌘V (works in nearly every app) and restores the clipboard afterwards.
@MainActor
enum SelectionService {
    static func capture() async -> CapturedSelection? {
        let app = NSWorkspace.shared.frontmostApplication
        let isOwnApp = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let ownWindow = isOwnApp ? NSApp.keyWindow : nil

        if !isOwnApp { AppCompatibility.prepare(app) }

        var anchor: NSRect?
        if let element = focusedElement() {
            if isSecureField(element) { return nil }
            anchor = selectionBounds(element)
            if let text = selectedText(element), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CapturedSelection(text: text, app: app, anchor: anchor, ownWindow: ownWindow)
            }
            // The app says nothing is selected. Don't fall back to ⌘C: editors like VS Code
            // would copy the whole line and Textly would paste a duplicate.
            // Browsers are the exception: web editors (Google Docs…) often report an empty selection.
            if selectedRangeLength(element) == 0 && AppCompatibility.trustsEmptySelection(app) { return nil }
        }

        if let text = await copyViaClipboard(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedSelection(text: text, app: app, anchor: anchor, ownWindow: ownWindow)
        }
        return nil
    }

    /// For text handed over by macOS Services: the text is known, only the app and position are needed.
    static func selection(withText text: String) -> CapturedSelection {
        let app = NSWorkspace.shared.frontmostApplication
        let isOwnApp = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let anchor = focusedElement().flatMap { selectionBounds($0) }
        return CapturedSelection(text: text, app: app, anchor: anchor, ownWindow: isOwnApp ? NSApp.keyWindow : nil)
    }

    static func replace(with text: String, target: CapturedSelection?) async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let app = target?.app, app.processIdentifier != ownPID {
            _ = app.activate()
            try? await Task.sleep(nanoseconds: 150_000_000)
        } else if let window = target?.ownWindow {
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Ask clipboard managers to ignore this temporary entry.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChangeCount = pasteboard.changeCount

        await waitForModifiersReleased()
        postCommandKey(CGKeyCode(kVK_ANSI_V))

        try? await Task.sleep(nanoseconds: 500_000_000)
        if pasteboard.changeCount == ourChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    // MARK: Accessibility

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func selectedText(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedRangeLength(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.length
    }

    private static func isSecureField(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success,
              let subrole = value as? String else { return false }
        return subrole == (kAXSecureTextFieldSubrole as String)
    }

    private static func selectionBounds(_ element: AXUIElement) -> NSRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        // Accessibility uses a top-left origin; AppKit uses bottom-left of the main screen.
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let converted = NSRect(x: rect.minX, y: mainScreen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(converted.insetBy(dx: -2, dy: -2)) }) else { return nil }
        return converted
    }

    // MARK: Clipboard fallback

    private static func copyViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount

        await waitForModifiersReleased()
        postCommandKey(CGKeyCode(kVK_ANSI_C))

        var text: String?
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pasteboard.changeCount != before {
                try? await Task.sleep(nanoseconds: 30_000_000)
                text = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before {
            snapshot.restore(to: pasteboard)
        }
        return text
    }

    // MARK: Keyboard

    /// Waits until the user lets go of ⌃⌥⇧⌘ (from the shortcut), so they don't mix with our ⌘C / ⌘V.
    private static func waitForModifiersReleased() async {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<50 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

/// A copy of everything on the clipboard, so it can be put back after Textly borrows it.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
