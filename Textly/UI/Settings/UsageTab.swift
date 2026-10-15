import SwiftUI

/// What Textly has cost so far, and what it would cost at a given number of uses per day.
struct UsageTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @State private var confirmReset = false

    /// Typical request when there's no history yet: shared rules + instructions (~800 tokens) + a short message.
    private static let defaultPromptTokens: Double = 1_000
    private static let defaultCompletionTokens: Double = 150

    private var tokensPerUse: (prompt: Double, completion: Double) {
        usage.averageTokens ?? (Self.defaultPromptTokens, Self.defaultCompletionTokens)
    }

    private var defaultModel: ORModel? { catalog.model(store.settings.defaultModel) }

    private var costPerUse: Double? {
        guard let model = defaultModel, let input = model.promptPrice, let output = model.completionPrice else { return nil }
        return (tokensPerUse.prompt * input + tokensPerUse.completion * output) / 1_000_000
    }

    var body: some View {
        Form {
            Section("Your spending") {
                row("Today", usage.summary(days: 1))
                row("Last 7 days", usage.summary(days: 7))
                row("Last 30 days", usage.summary(days: 30))
                HStack {
                    Link("See every request on openrouter.ai/activity", destination: URL(string: "https://openrouter.ai/activity")!)
                        .font(.callout)
                    Spacer()
                    Button("Reset history…") { confirmReset = true }
                        .disabled(usage.entries.isEmpty)
                }
            }

            Section("Estimate") {
                LabeledContent("Uses per day") {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { Double(store.settings.usesPerDay) },
                                set: { store.settings.usesPerDay = Int($0.rounded()) }
                            ),
                            in: 1...200,
                            step: 1
                        )
                        .frame(width: 200)
                        Text("\(store.settings.usesPerDay)")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                if let average = usage.averageUsesPerDay {
                    Text("You've averaged \(String(format: "%.1f", average)) uses a day recently.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let perUse = costPerUse {
                    let perDay = perUse * Double(store.settings.usesPerDay)
                    LabeledContent("Per use", value: Money.format(perUse))
                    LabeledContent("Per day", value: Money.format(perDay))
                    LabeledContent("Per week", value: Money.format(perDay * 7))
                    LabeledContent("Per month", value: Money.format(perDay * 30))
                        .fontWeight(.semibold)
                } else if catalog.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading prices…").foregroundStyle(.secondary)
                    }
                } else {
                    Text("No price found for “\(store.settings.defaultModel)”. Check the model name in General.")
                        .foregroundStyle(.secondary)
                }

                Text(estimateFootnote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await catalog.loadIfNeeded() }
        .confirmationDialog("Reset usage history?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { usage.reset() }
        } message: {
            Text("This only clears Textly's local log. Your OpenRouter account isn't affected.")
        }
    }

    private var estimateFootnote: String {
        let tokens = tokensPerUse
        let source = usage.averageTokens == nil ? "a typical request" : "your recent average"
        return "Based on \(source): about \(Int(tokens.prompt)) tokens sent and \(Int(tokens.completion)) received per use, with your default model (\(store.settings.defaultModel)). Actions that use another model will differ."
    }

    @ViewBuilder
    private func row(_ title: String, _ summary: UsageSummary) -> some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Text(summary.requests == 1 ? "1 request" : "\(summary.requests) requests")
                    .foregroundStyle(.secondary)
                Text(Money.format(summary.cost) + (summary.hasUnknownCost ? "+" : ""))
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
    }
}
