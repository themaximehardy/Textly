import Foundation

/// One action, ready to send: the request plus what's needed to put the answer back together.
struct PreparedRun: Sendable {
    let request: CompletionRequest
    let parts: TextCleanup.Parts
    /// "Fix", "Translate to Spanish"…
    let title: String
    /// Show the changes highlighted (not for summaries and translations, where everything changes).
    let showDiff: Bool
}

struct RunOutput: Sendable {
    /// The result with the spaces and line breaks that surrounded the selection.
    let full: String
    /// The result itself.
    let core: String
    let original: String
    let completion: CompletionResult
}

/// Builds and runs an action. Shared by the palette, the shortcuts, Services and the "Try it" box.
@MainActor
enum ActionRunner {
    static func prepare(action: TextAction, language: String?, text: String, settings: AppSettings, apiKey: String) throws -> PreparedRun {
        let endpoint = try endpoint(settings: settings, apiKey: apiKey)
        let model = settings.model(for: action)
        guard !model.isEmpty else {
            throw AIError(message: settings.provider == .local
                ? "Choose a local model in Settings › General."
                : "Choose a model in Settings › General.")
        }
        let parts = TextCleanup.split(text)
        let prompt = PromptBuilder.messages(for: action, language: language, text: parts.core, settings: settings)
        let request = CompletionRequest(
            endpoint: endpoint,
            model: model,
            system: prompt.system,
            user: prompt.user,
            temperature: action.temperature,
            noTraining: settings.noTraining,
            fastMode: settings.fastMode
        )
        return PreparedRun(
            request: request,
            parts: parts,
            title: language.map { "Translate to \($0)" } ?? action.name,
            showDiff: action.builtin != "summarise" && !action.isTranslate
        )
    }

    static func endpoint(settings: AppSettings, apiKey: String) throws -> AIEndpoint {
        switch settings.provider {
        case .openRouter:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIError(message: "Add your OpenRouter API key in Settings › General.")
            }
            return .openRouter(apiKey: apiKey)
        case .local:
            guard let endpoint = AIEndpoint.local(settings.localBaseURL) else {
                throw AIError(message: "The local server address isn't valid. Check it in Settings › General.")
            }
            return endpoint
        }
    }

    /// Sends the request, streams the text to `onPartial` (from a background thread), records the cost.
    static func run(_ prepared: PreparedRun, onPartial: @escaping @Sendable (String) -> Void) async throws -> RunOutput {
        let completion = try await AIClient.stream(prepared.request) { text in
            onPartial(TextCleanup.partial(text))
        }
        UsageStore.shared.record(
            model: prepared.request.model,
            promptTokens: completion.promptTokens,
            completionTokens: completion.completionTokens,
            reportedCost: prepared.request.endpoint.isOpenRouter ? completion.cost : 0
        )
        try Task.checkCancellation()
        let cleaned = TextCleanup.clean(completion.content, original: prepared.parts.core)
        return RunOutput(
            full: prepared.parts.lead + cleaned + prepared.parts.trail,
            core: cleaned,
            original: prepared.parts.core,
            completion: completion
        )
    }
}

/// Collects streamed text off the main thread and hands the latest version to the UI
/// at most about 25 times a second, always in order.
final class StreamRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var latest = ""
    private var scheduled = false
    private var stopped = false
    private let deliver: @MainActor (String) -> Void

    init(deliver: @escaping @MainActor (String) -> Void) {
        self.deliver = deliver
    }

    func push(_ text: String) {
        lock.lock()
        latest = text
        let schedule = !scheduled && !stopped
        scheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [self] in
            lock.lock()
            let text = latest
            let isStopped = stopped
            scheduled = false
            lock.unlock()
            guard !isStopped else { return }
            MainActor.assumeIsolated { deliver(text) }
        }
    }

    /// No more updates after this (the final result is about to be shown).
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
