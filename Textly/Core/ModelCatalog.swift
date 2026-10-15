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
            models = try await OpenRouterClient.fetchModels()
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
