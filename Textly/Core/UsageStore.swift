import Foundation

struct UsageEntry: Codable, Equatable {
    let date: Date
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    /// USD. Reported by OpenRouter, or estimated from the model's price.
    let cost: Double?
}

struct UsageSummary {
    let requests: Int
    let cost: Double
    let hasUnknownCost: Bool
}

/// A local log of requests and their cost (kept 120 days), for Settings › Usage.
/// Stored in ~/Library/Application Support/Textly/usage.json. Never contains your text.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var entries: [UsageEntry] = []

    private static var fileURL: URL { SettingsStore.folderURL.appendingPathComponent("usage.json") }
    private static let keepDays: Double = 120

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([UsageEntry].self, from: data)) ?? []
        }
    }

    func record(model: String, promptTokens: Int, completionTokens: Int, reportedCost: Double?) {
        var cost = reportedCost
        if cost == nil,
           let info = ModelCatalog.shared.model(model),
           let inputPrice = info.promptPrice,
           let outputPrice = info.completionPrice {
            cost = (Double(promptTokens) * inputPrice + Double(completionTokens) * outputPrice) / 1_000_000
        }
        entries.append(UsageEntry(date: Date(), model: model, promptTokens: promptTokens, completionTokens: completionTokens, cost: cost))
        let cutoff = Date().addingTimeInterval(-Self.keepDays * 86_400)
        entries.removeAll { $0.date < cutoff }
        save()
    }

    func summary(days: Int) -> UsageSummary {
        let start: Date
        if days <= 1 {
            start = Calendar.current.startOfDay(for: Date())
        } else {
            start = Date().addingTimeInterval(-Double(days) * 86_400)
        }
        let recent = entries.filter { $0.date >= start }
        return UsageSummary(
            requests: recent.count,
            cost: recent.compactMap(\.cost).reduce(0, +),
            hasUnknownCost: recent.contains { $0.cost == nil }
        )
    }

    /// Average tokens per request over the last 200 requests, if there is enough history.
    var averageTokens: (prompt: Double, completion: Double)? {
        let recent = entries.suffix(200)
        guard recent.count >= 5 else { return nil }
        let prompt = Double(recent.map(\.promptTokens).reduce(0, +)) / Double(recent.count)
        let completion = Double(recent.map(\.completionTokens).reduce(0, +)) / Double(recent.count)
        return (prompt, completion)
    }

    /// Average uses per day over the last 30 days (only counting days since the first use).
    var averageUsesPerDay: Double? {
        guard let first = entries.first?.date else { return nil }
        let windowStart = max(first, Date().addingTimeInterval(-30 * 86_400))
        let days = max(1, Date().timeIntervalSince(windowStart) / 86_400)
        let count = entries.filter { $0.date >= windowStart }.count
        guard days >= 1, count > 0 else { return nil }
        return Double(count) / days
    }

    func reset() {
        entries = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: SettingsStore.folderURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Textly: could not save usage: \(error.localizedDescription)")
        }
    }
}

enum Money {
    /// "$0.0042" for small amounts, "$1.23" otherwise.
    static func format(_ value: Double) -> String {
        if value == 0 { return "$0.00" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.3f", value) }
        return String(format: "$%.2f", value)
    }
}
