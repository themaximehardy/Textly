import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts, using the Carbon hot key API
/// (still the standard way for Mac apps; it needs no extra permission).
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private static let signature: OSType = 0x5458_544C // "TXTL"
    private static let escapeID: UInt32 = 999_999

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private var escapeRef: EventHotKeyRef?
    private var escapeHandler: (@MainActor () -> Void)?

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    @discardableResult
    func register(_ hotkey: Hotkey, handler: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Textly: could not register shortcut \(hotkey.display) (\(status))")
            return false
        }
        refs.append(ref)
        handlers[id] = handler
        return true
    }

    /// While a request runs without the palette, Esc cancels it.
    func setEscapeHandler(_ handler: (@MainActor () -> Void)?) {
        if let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
        escapeHandler = handler
        guard handler != nil else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.escapeID)
        if RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr {
            escapeRef = ref
        }
    }

    fileprivate func fire(_ id: UInt32) {
        if id == Self.escapeID {
            let handler = escapeHandler
            setEscapeHandler(nil)
            handler?()
            return
        }
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), textlyHotKeyHandler, 1, &spec, nil, nil)
    }
}

/// Carbon calls this C function when one of our shortcuts is pressed.
private func textlyHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotkeyCenter.shared.fire(id) }
    }
    return noErr
}
