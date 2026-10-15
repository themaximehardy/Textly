import Foundation

/// The list of OpenRouter models with their prices, loaded once and shared
/// (model picker, cost estimator, cost fallback when OpenRouter doesn't report one).
@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    @Published private(set) var models: [ORModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    func loadIfNeeded() async {
        guard models.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorText = nil
        do {
            models = try await AIClient.fetchModels(.openRouter(apiKey: ""))
        } catch {
            errorText = "Couldn't load the model list: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func model(_ id: String) -> ORModel? {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        return models.first { $0.id == trimmed }
    }
}

/// The models installed on the local server (Ollama, LM Studio…).
@MainActor
final class LocalModelCatalog: ObservableObject {
    static let shared = LocalModelCatalog()

    @Published private(set) var models: [ORModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var status: String?
    @Published private(set) var isReachable = false

    func reload(address: String) async {
        guard let endpoint = AIEndpoint.local(address) else {
            models = []
            isReachable = false
            status = "Enter an address like http://localhost:11434/v1"
            return
        }
        isLoading = true
        status = "Connecting…"
        do {
            models = try await AIClient.fetchModels(endpoint)
            isReachable = true
            switch models.count {
            case 0: status = "Connected, but no models are installed yet."
            case 1: status = "Connected ✓ 1 model"
            default: status = "Connected ✓ \(models.count) models"
            }
        } catch {
            models = []
            isReachable = false
            status = error.localizedDescription
        }
        isLoading = false
    }
}
