import SwiftUI
import AppKit

/// The translucent macOS popover background.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Shows a menu bar icon choice: a custom template asset ("asset:MenuT") or an SF Symbol.
struct MenuBarIconView: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        if let asset = MenuBarIcons.assetName(name) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 1.25, height: size * 1.25)
        } else {
            Image(systemName: name)
                .font(.system(size: size))
        }
    }
}

/// A small key badge, e.g. [F].
struct KeyCap: View {
    let text: String
    var inverted = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .foregroundStyle(inverted ? Color.white.opacity(0.9) : Color.secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(inverted ? Color.white.opacity(0.5) : Color.secondary.opacity(0.4), lineWidth: 1)
            )
    }
}

/// Measures how tall a block of text will be, so the result area can size itself.
enum TextMeasure {
    static func height(_ text: String, width: CGFloat, fontSize: CGFloat = 13) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: max(width, 10), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)],
            context: nil
        )
        return ceil(rect.height) + 6
    }
}

/// A grid of SF Symbols to choose an action icon from.
struct IconPicker: View {
    @Binding var selection: String
    @State private var isOpen = false

    static let symbols = [
        "checkmark", "sparkles", "text.alignleft", "globe", "scissors", "wand.and.stars",
        "bubble.left", "quote.bubble", "envelope", "hand.thumbsup", "face.smiling", "list.bullet",
        "briefcase", "graduationcap", "lightbulb", "pencil", "text.badge.checkmark", "character.bubble",
        "doc.text", "arrow.uturn.backward", "megaphone", "heart", "star", "bolt",
    ]

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Image(systemName: selection)
                .frame(width: 22, height: 18)
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        isOpen = false
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(symbol == selection ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                }
            }
            .padding(12)
        }
        .help("Choose an icon")
    }
}

/// A removable language tag in Settings.
struct LanguageChip: View {
    let name: String
    let onRemove: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Unpin \(name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}
