import SwiftUI

/// The palette that appears next to your selection.
/// Two layouts, chosen in Settings › General › Palette style:
///  - Command list (default): compact list, results only shown when needed.
///  - Preview before replacing: actions on the left, result with changes highlighted on the right.
struct PaletteView: View {
    @ObservedObject var model: PaletteModel

    var body: some View {
        content
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .fixedSize()
    }

    @ViewBuilder private var content: some View {
        if model.style == .preview && model.screen != .languages {
            PreviewLayout(model: model)
        } else {
            ListLayout(model: model)
        }
    }
}

// MARK: - Layouts

private struct ListLayout: View {
    @ObservedObject var model: PaletteModel
    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            PaletteHeader(model: model)
            Divider()
            Group {
                switch model.screen {
                case .menu:
                    ActionList(model: model, compact: false)
                        .padding(6)
                case .languages:
                    LanguagePicker(model: model)
                case .working(let title):
                    WorkingView(title: title, partial: model.streamingText, textWidth: Self.width - 28)
                        .padding(14)
                case .result:
                    ResultPane(model: model, textWidth: Self.width - 28)
                        .padding(14)
                case .review:
                    ReviewPane(model: model, textWidth: Self.width - 28)
                        .padding(14)
                case .error(let message):
                    ErrorPane(model: model, message: message)
                        .padding(14)
                }
            }
            Divider()
            FooterHints(screen: model.screen)
        }
        .frame(width: Self.width)
    }
}

private struct PreviewLayout: View {
    @ObservedObject var model: PaletteModel
    static let listWidth: CGFloat = 190
    static let paneWidth: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            PaletteHeader(model: model)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ActionList(model: model, compact: true)
                    .padding(6)
                    .frame(width: Self.listWidth, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.primary.opacity(0.035))
                Divider()
                rightPane
                    .padding(14)
                    .frame(width: Self.paneWidth, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            FooterHints(screen: model.screen)
        }
        .frame(width: Self.listWidth + Self.paneWidth + 1)
    }

    @ViewBuilder private var rightPane: some View {
        switch model.screen {
        case .menu, .languages:
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick an action. The result appears here before anything is replaced.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 13))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .working(let title):
            WorkingView(title: title, partial: model.streamingText, textWidth: Self.paneWidth - 28)
        case .result:
            ResultPane(model: model, textWidth: Self.paneWidth - 28)
        case .review:
            ReviewPane(model: model, textWidth: Self.paneWidth - 28)
        case .error(let message):
            ErrorPane(model: model, message: message)
        }
    }
}

// MARK: - Pieces

private struct PaletteHeader: View {
    @ObservedObject var model: PaletteModel

    var body: some View {
        HStack(spacing: 6) {
            MenuBarIconView(name: model.brandIcon, size: 11)
                .foregroundStyle(.secondary)
            Text("Textly")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(model.sourceText.count) characters")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

private struct ActionList: View {
    @ObservedObject var model: PaletteModel
    let compact: Bool

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                if item.isCustom && index > 0 && !model.items[index - 1].isCustom {
                    Divider()
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                }
                Button {
                    model.run(item)
                } label: {
                    ActionRow(item: item, highlighted: index == model.highlighted, compact: compact)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { model.highlighted = index }
                }
            }
        }
    }
}

private struct ActionRow: View {
    let item: PaletteItem
    let highlighted: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12.5))
                .frame(width: 16)
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let key = item.key {
                KeyCap(text: String(key).uppercased(), inverted: highlighted)
            }
        }
        .font(.system(size: compact ? 12.5 : 13))
        .padding(.horizontal, 10)
        .frame(height: compact ? 28 : 30)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct LanguagePicker: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    model.backToMenu()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Back (esc)")
                Text("Translate to")
                    .font(.system(size: 13, weight: .semibold))
                TextField("Any language…", text: $model.languageQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            Divider()
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(model.languageRows.enumerated()), id: \.element.id) { index, row in
                    if index == 0 || model.languageRows[index - 1].section != row.section {
                        Text(row.section)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 4 : 8)
                            .padding(.bottom, 2)
                    }
                    Button {
                        model.choose(row)
                    } label: {
                        LanguageRowView(row: row, highlighted: index == model.languageHighlighted)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { model.languageHighlighted = index }
                    }
                }
                if model.languageRows.isEmpty {
                    Text("Type any language, e.g. Spanish (Mexico) or formal German.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
            .padding(6)
        }
        .onAppear {
            Task { @MainActor in searchFocused = true }
        }
    }
}

private struct LanguageRowView: View {
    let row: LanguageRow
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.isPinned ? "star.fill" : "globe")
                .font(.system(size: 10.5))
                .frame(width: 16)
                .foregroundStyle(highlighted ? Color.white : (row.isPinned ? Color.accentColor : Color.secondary))
            Text(row.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !row.native.isEmpty && row.native != row.name {
                Text(row.native)
                    .lineLimit(1)
                    .foregroundStyle(highlighted ? Color.white.opacity(0.85) : Color.secondary)
            }
            if highlighted {
                KeyCap(text: "↵", inverted: true)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct WorkingView: View {
    let title: String
    /// The answer so far (streamed), shown live under the title.
    let partial: String
    let textWidth: CGFloat

    private var textHeight: CGFloat {
        min(max(TextMeasure.height(partial, width: textWidth - 8), 20), 280)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("\(title)…")
                    .font(.system(size: partial.isEmpty ? 13 : 12, weight: partial.isEmpty ? .regular : .semibold))
                Spacer(minLength: 0)
            }
            if !partial.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(partial)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear
                                .frame(height: 1)
                                .id("end")
                        }
                    }
                    .frame(width: textWidth, height: textHeight)
                    .onChange(of: partial) { _, _ in
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ResultPane: View {
    @ObservedObject var model: PaletteModel
    let textWidth: CGFloat

    private var displayText: String {
        if let diff = model.diff { return TextDiff.plainText(diff) }
        return model.resultCore
    }

    private var textHeight: CGFloat {
        min(max(TextMeasure.height(displayText, width: textWidth - 8), 20), 280)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(model.resultTitle)
                    .font(.system(size: 12, weight: .semibold))
                if model.diff != nil {
                    Text(changeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ScrollView {
                resultText
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: textWidth, height: textHeight)
            HStack(spacing: 8) {
                Button {
                    model.onReplace?()
                } label: {
                    Text("Replace")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    model.onCopy?()
                } label: {
                    Text("Copy")
                }
                Button {
                    model.onRetry?()
                } label: {
                    Text("Try again")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }

    private var resultText: Text {
        if let diff = model.diff {
            return Text(TextDiff.attributed(diff))
        }
        return Text(model.resultCore)
    }

    private var changeLabel: String {
        switch model.changeCount {
        case 0: return "No changes"
        case 1: return "1 change"
        default: return "\(model.changeCount) changes"
        }
    }
}

/// Each suggested change on its own row: tick the ones to keep, then apply.
private struct ReviewPane: View {
    @ObservedObject var model: PaletteModel
    let textWidth: CGFloat

    private var changes: [SuggestedChange] { model.review?.changes ?? [] }

    private var listHeight: CGFloat {
        let rows = changes.reduce(CGFloat(0)) { total, change in
            total + TextMeasure.height(change.before + change.removed + change.added + change.after, width: textWidth - 44) + 10
        }
        return min(max(rows, 34), 260)
    }

    private var applyLabel: String {
        let kept = model.accepted.count
        if kept == 0 { return "Keep original" }
        if kept == changes.count { return changes.count == 1 ? "Apply the change" : "Apply all \(kept)" }
        return "Apply \(kept) of \(changes.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(model.resultTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(changes.count == 1 ? "1 suggestion" : "\(changes.count) suggestions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("All") { model.setAllChanges(true) }
                Button("None") { model.setAllChanges(false) }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            ChangeRow(
                                change: change,
                                kept: model.accepted.contains(change.id),
                                highlighted: index == model.reviewHighlighted
                            )
                            .id(change.id)
                            .onTapGesture { model.toggleChange(change.id) }
                        }
                    }
                }
                .frame(width: textWidth, height: listHeight)
                .onChange(of: model.reviewHighlighted) { _, index in
                    if changes.indices.contains(index) {
                        proxy.scrollTo(changes[index].id)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.onReplace?()
                } label: {
                    Text(applyLabel)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    model.onCopy?()
                } label: {
                    Text("Copy")
                }
                Button {
                    model.onRetry?()
                } label: {
                    Text("Try again")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }
}

private struct ChangeRow: View {
    let change: SuggestedChange
    let kept: Bool
    let highlighted: Bool

    private var text: AttributedString {
        var result = AttributedString(change.before)
        result[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = .secondary
        if !change.removed.isEmpty {
            var removed = AttributedString(change.removed)
            if kept {
                removed[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self] = Text.LineStyle(pattern: .solid)
            }
            removed[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = kept ? Color.red.opacity(0.8) : Color.primary
            result += removed
        }
        if !change.removed.isEmpty && !change.added.isEmpty {
            result += AttributedString(" ")
        }
        if !change.added.isEmpty {
            var added = AttributedString(change.added)
            added[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = kept ? Color.green : Color.secondary
            added[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = kept ? Color.green.opacity(0.14) : Color.clear
            if !kept {
                added[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self] = Text.LineStyle(pattern: .solid)
            }
            result += added
        }
        var after = AttributedString(change.after)
        after[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = .secondary
        result += after
        return result
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(kept ? Color.accentColor : Color.secondary)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .help(kept ? "Click to drop this change" : "Click to keep this change")
    }
}

private struct ErrorPane: View {
    @ObservedObject var model: PaletteModel
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text(message)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    model.onRetry?()
                } label: {
                    Text("Try again")
                }
                Button {
                    model.onOpenSettings?()
                } label: {
                    Text("Open Settings")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: 312, alignment: .leading)
    }
}

private struct FooterHints: View {
    let screen: PaletteScreen

    private var hints: [String] {
        switch screen {
        case .menu: return ["↵ Run", "⇧ Review each change"]
        case .languages: return ["↵ Translate", "⌘P Pin"]
        case .working: return ["Writing…"]
        case .result: return ["↵ Replace", "⌘C Copy", "⌘R Try again"]
        case .review: return ["↵ Apply", "Space Keep or drop", "⌘C Copy"]
        case .error: return ["↵ Try again"]
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.self) { hint in
                Text(hint)
            }
            Spacer(minLength: 0)
            Text(screen == .languages ? "esc Back" : "esc")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
