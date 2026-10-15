import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click, then press a key combination (with ⌃, ⌥ or ⌘). Esc cancels, Delete removes the shortcut.
struct ShortcutRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recording { stop() } else { start() }
            } label: {
                Text(recording ? "Press keys…" : (hotkey?.display ?? "Record shortcut"))
                    .frame(minWidth: 110)
            }
            if hotkey != nil && !recording {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        guard !recording else { return }
        recording = true
        NotificationCenter.default.post(name: .textlyRecordingChanged, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            NotificationCenter.default.post(name: .textlyRecordingChanged, object: false)
        }
    }

    private func handle(_ event: NSEvent) {
        let code = Int(event.keyCode)
        if code == kVK_Escape {
            stop()
            return
        }
        if code == kVK_Delete || code == kVK_ForwardDelete {
            hotkey = nil
            stop()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let hasMainModifier = !modifiers.intersection([.command, .option, .control]).isEmpty
        guard hasMainModifier || KeyLabels.functionKeys.contains(code) else {
            NSSound.beep()
            return
        }
        hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers.rawValue, keyLabel: KeyLabels.label(for: event))
        stop()
    }
}

enum KeyLabels {
    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
            return characters.uppercased()
        }
    }
}
