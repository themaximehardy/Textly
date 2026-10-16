import AppKit
import SwiftUI

/// Small message near the mouse pointer ("Select some text first", "Fixing…").
@MainActor
final class Toast {
    static let shared = Toast()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, icon: String = "info.circle", spinning: Bool = false, duration: TimeInterval? = 1.8) {
        hideWork?.cancel()

        let host = NSHostingView(rootView: ToastView(message: message, icon: icon, spinning: spinning))
        host.sizingOptions = []
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? Self.makePanel()
        panel.contentView = host
        panel.setContentSize(size)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        self.panel = panel

        if let duration {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.hide() }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct ToastView: View {
    let message: String
    let icon: String
    let spinning: Bool

    var body: some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
            }
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .frame(maxWidth: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .fixedSize()
    }
}
