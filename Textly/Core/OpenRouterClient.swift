import Foundation

struct OpenRouterError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CompletionRequest: Sendable {
    let apiKey: String
    let model: String
    let system: String
    let user: String
    let temperature: Double
    let noTraining: Bool
    let fastMode: Bool
}

struct CompletionResult: Sendable {
    let content: String
    let promptTokens: Int
    let completionTokens: Int
    /// USD, as reported by OpenRouter (nil if not reported).
    let cost: Double?
}

struct ORModel: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    /// USD per million tokens.
    let promptPrice: Double?
    let completionPrice: Double?

    private enum CodingKeys: String, CodingKey { case id, name, pricing }
    private struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        let pricing = try? c.decode(Pricing.self, forKey: .pricing)
        promptPrice = pricing?.prompt.flatMap { Double($0) }.map { $0 * 1_000_000 }
        completionPrice = pricing?.completion.flatMap { Double($0) }.map { $0 * 1_000_000 }
    }

    var priceLabel: String {
        guard let input = promptPrice, let output = completionPrice else { return "" }
        if input == 0 && output == 0 { return "Free" }
        return String(format: "$%.2f / $%.2f per 1M", input, output)
    }
}

enum OpenRouterClient {
    private static let base = URL(string: "https://openrouter.ai/api/v1")!

    static func complete(_ request: CompletionRequest) async throws -> CompletionResult {
        var urlRequest = URLRequest(url: base.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        addHeaders(&urlRequest, apiKey: request.apiKey)

        var body: [String: Any] = [
            "model": request.model,
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": request.user],
            ],
            "temperature": request.temperature,
            "usage": ["include": true],
        ]
        if request.noTraining {
            body["provider"] = ["data_collection": "deny"]
        }
        if request.fastMode {
            body["reasoning"] = ["effort": "low", "exclude": true] as [String: Any]
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if status != 200 || json?["error"] != nil {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? "OpenRouter returned an error (HTTP \(status))."
            throw OpenRouterError(message: friendly(status: status, message: message))
        }

        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError(message: "The model sent back an empty answer. Try again or pick another model.")
        }
        let usage = json?["usage"] as? [String: Any]
        return CompletionResult(
            content: content,
            promptTokens: (usage?["prompt_tokens"] as? NSNumber)?.intValue ?? 0,
            completionTokens: (usage?["completion_tokens"] as? NSNumber)?.intValue ?? 0,
            cost: (usage?["cost"] as? NSNumber)?.doubleValue
        )
    }

    static func fetchModels() async throws -> [ORModel] {
        struct Response: Decodable { let data: [ORModel] }
        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        let models = try JSONDecoder().decode(Response.self, from: data).data
        return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Checks that the API key is accepted.
    static func checkKey(_ apiKey: String) async throws {
        for path in ["key", "auth/key"] {
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.timeoutInterval = 20
            addHeaders(&request, apiKey: apiKey)
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return }
            if status == 404 { continue }
            throw OpenRouterError(message: friendly(status: status, message: "OpenRouter rejected the request (HTTP \(status))."))
        }
        throw OpenRouterError(message: "Couldn't check the key. OpenRouter may be unavailable.")
    }

    private static func addHeaders(_ request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.homepage, forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Textly", forHTTPHeaderField: "X-Title")
    }

    private static func friendly(status: Int, message: String) -> String {
        switch status {
        case 401: return "OpenRouter rejected your API key. Check it in Settings › General."
        case 402: return "Your OpenRouter credits have run out. Top up at openrouter.ai."
        case 408: return "OpenRouter took too long to answer. Try again."
        case 429: return "Too many requests right now. Wait a moment and try again."
        default:
            if message.localizedCaseInsensitiveContains("data policy") {
                return "No provider for this model matches your privacy setting. Turn off “Only use providers that don't store or train on my text” or pick another model."
            }
            return message
        }
    }
}
