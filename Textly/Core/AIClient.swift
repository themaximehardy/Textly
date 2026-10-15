import Foundation

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Where requests go: OpenRouter, or a local OpenAI-compatible server (Ollama, LM Studio…).
struct AIEndpoint: Sendable, Equatable {
    let baseURL: URL
    let apiKey: String
    let isOpenRouter: Bool

    static let openRouterBase = URL(string: "https://openrouter.ai/api/v1")!

    static func openRouter(apiKey: String) -> AIEndpoint {
        AIEndpoint(baseURL: openRouterBase, apiKey: apiKey, isOpenRouter: true)
    }

    static func local(_ address: String) -> AIEndpoint? {
        guard let url = LocalServer.normalisedURL(address) else { return nil }
        return AIEndpoint(baseURL: url, apiKey: "", isOpenRouter: false)
    }
}

/// OpenAI-compatible servers that run models on your Mac.
enum LocalServer {
    static let ollama = "http://localhost:11434/v1"
    static let lmStudio = "http://localhost:1234/v1"

    /// Accepts "localhost:11434", "http://localhost:11434" or "http://localhost:11434/v1/".
    /// Adds http:// and /v1 when they are missing.
    static func normalisedURL(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        if components.path.isEmpty { components.path = "/v1" }
        return components.url
    }
}

struct CompletionRequest: Sendable {
    let endpoint: AIEndpoint
    let model: String
    let system: String
    let user: String
    let temperature: Double
    let noTraining: Bool
    let fastMode: Bool
}

struct CompletionResult: Sendable, Equatable {
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

/// Reads a streamed chat completion ("server-sent events"), one line at a time.
/// Works with OpenRouter, OpenAI, Ollama and LM Studio.
struct SSEParser {
    enum Event: Equatable {
        case text(String)
        case usage(prompt: Int, completion: Int, cost: Double?)
        case error(String)
        case done
    }

    func parse(_ rawLine: String) -> [Event] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Comments (": OPENROUTER PROCESSING"), "event:" and "id:" lines carry nothing we need.
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }
        guard let data = payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }

        if let error = json["error"], !(error is NSNull) {
            let message = ((error as? [String: Any])?["message"] as? String) ?? (error as? String) ?? "The model stopped with an error."
            return [.error(message)]
        }

        var events: [Event] = []
        if let choice = (json["choices"] as? [[String: Any]])?.first {
            let delta = (choice["delta"] as? [String: Any]) ?? (choice["message"] as? [String: Any])
            if let content = delta?["content"] as? String, !content.isEmpty {
                events.append(.text(content))
            }
        }
        if let usage = json["usage"] as? [String: Any] {
            events.append(.usage(
                prompt: (usage["prompt_tokens"] as? NSNumber)?.intValue ?? 0,
                completion: (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0,
                cost: (usage["cost"] as? NSNumber)?.doubleValue
            ))
        }
        return events
    }
}

enum AIClient {
    /// The JSON body for a chat completion. OpenRouter-only options are never sent to local servers.
    static func body(for request: CompletionRequest, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": request.user],
            ],
            "temperature": request.temperature,
        ]
        if stream {
            body["stream"] = true
        }
        if request.endpoint.isOpenRouter {
            body["usage"] = ["include": true]
            if request.noTraining {
                body["provider"] = ["data_collection": "deny"]
            }
            if request.fastMode {
                body["reasoning"] = ["effort": "low", "exclude": true] as [String: Any]
            }
        } else if stream {
            body["stream_options"] = ["include_usage": true]
        }
        return body
    }

    /// Sends the request and streams the answer. `onText` receives the whole text so far, every time it grows.
    static func stream(_ request: CompletionRequest, onText: @escaping @Sendable (String) -> Void) async throws -> CompletionResult {
        var urlRequest = URLRequest(url: request.endpoint.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        // Local models can take a while to load the first time.
        urlRequest.timeoutInterval = request.endpoint.isOpenRouter ? 90 : 300
        addHeaders(&urlRequest, endpoint: request.endpoint)
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request, stream: true))

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        } catch let error as URLError {
            throw connectionError(error, endpoint: request.endpoint)
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let isStream = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("event-stream")

        if status != 200 || !isStream {
            // An error, or a server that ignored "stream": read the whole body.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            if status != 200 {
                throw AIError(message: errorMessage(status: status, data: data, endpoint: request.endpoint))
            }
            let result = try parseComplete(data)
            onText(result.content)
            return result
        }

        let parser = SSEParser()
        var content = ""
        var promptTokens = 0
        var completionTokens = 0
        var cost: Double?
        streaming: for try await line in bytes.lines {
            try Task.checkCancellation()
            for event in parser.parse(line) {
                switch event {
                case .text(let piece):
                    content += piece
                    onText(content)
                case .usage(let prompt, let completion, let reported):
                    promptTokens = prompt
                    completionTokens = completion
                    cost = reported ?? cost
                case .error(let message):
                    throw AIError(message: friendly(status: 0, message: message, endpoint: request.endpoint))
                case .done:
                    break streaming
                }
            }
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "The model sent back an empty answer. Try again or pick another model.")
        }
        return CompletionResult(content: content, promptTokens: promptTokens, completionTokens: completionTokens, cost: cost)
    }

    /// A whole (non-streamed) chat completion response.
    static func parseComplete(_ data: Data) throws -> CompletionResult {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            throw AIError(message: (error["message"] as? String) ?? "The model returned an error.")
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "The model sent back an empty answer. Try again or pick another model.")
        }
        let usage = json?["usage"] as? [String: Any]
        return CompletionResult(
            content: content,
            promptTokens: (usage?["prompt_tokens"] as? NSNumber)?.intValue ?? 0,
            completionTokens: (usage?["completion_tokens"] as? NSNumber)?.intValue ?? 0,
            cost: (usage?["cost"] as? NSNumber)?.doubleValue
        )
    }

    /// Models available at the endpoint (OpenRouter's full catalogue, or what's installed locally).
    static func fetchModels(_ endpoint: AIEndpoint) async throws -> [ORModel] {
        struct Response: Decodable { let data: [ORModel] }
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("models"))
        request.timeoutInterval = endpoint.isOpenRouter ? 30 : 10
        if !endpoint.isOpenRouter { addHeaders(&request, endpoint: endpoint) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw connectionError(error, endpoint: endpoint)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AIError(message: errorMessage(status: status, data: data, endpoint: endpoint))
        }
        guard let models = try? JSONDecoder().decode(Response.self, from: data).data else {
            throw AIError(message: "The server at \(endpoint.baseURL.absoluteString) didn't return a model list. Check the address.")
        }
        return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Checks that the OpenRouter API key is accepted.
    static func checkKey(_ apiKey: String) async throws {
        let endpoint = AIEndpoint.openRouter(apiKey: apiKey)
        for path in ["key", "auth/key"] {
            var request = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
            request.timeoutInterval = 20
            addHeaders(&request, endpoint: endpoint)
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return }
            if status == 404 { continue }
            throw AIError(message: friendly(status: status, message: "OpenRouter rejected the request (HTTP \(status)).", endpoint: endpoint))
        }
        throw AIError(message: "Couldn't check the key. OpenRouter may be unavailable.")
    }

    private static func addHeaders(_ request: inout URLRequest, endpoint: AIEndpoint) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !endpoint.apiKey.isEmpty {
            request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        }
        if endpoint.isOpenRouter {
            request.setValue(AppInfo.homepage, forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Textly", forHTTPHeaderField: "X-Title")
        }
    }

    private static func errorMessage(status: Int, data: Data, endpoint: AIEndpoint) -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = ((json?["error"] as? [String: Any])?["message"] as? String)
            ?? (json?["error"] as? String)
            ?? "\(endpoint.isOpenRouter ? "OpenRouter" : "The local server") returned an error (HTTP \(status))."
        return friendly(status: status, message: message, endpoint: endpoint)
    }

    private static func connectionError(_ error: URLError, endpoint: AIEndpoint) -> Error {
        if error.code == .cancelled { return error }
        if !endpoint.isOpenRouter {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return AIError(message: "Couldn't reach the local server at \(endpoint.baseURL.absoluteString). Make sure Ollama or LM Studio is running.")
            case .appTransportSecurityRequiresSecureConnection:
                return AIError(message: "macOS blocks plain http to this address. Use localhost, an IP address or a name ending in .local.")
            case .timedOut:
                return AIError(message: "The local model took too long to answer. It may still be loading: try again in a moment.")
            default:
                break
            }
        }
        return error
    }

    static func friendly(status: Int, message: String, endpoint: AIEndpoint) -> String {
        guard endpoint.isOpenRouter else {
            if status == 404 || message.localizedCaseInsensitiveContains("not found") {
                return "The local server doesn't have this model. Pick one in Settings › General. (\(message))"
            }
            return message
        }
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
