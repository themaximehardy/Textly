import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let date: Date
    /// "Fix", "Translate to Spanish"…
    let title: String
    let original: String
    let result: String
    /// The app the text came from.
    let appName: String?
}

/// The last results, newest first (menu bar › Recent results).
/// Kept in memory while Textly runs; saved to disk only when "Keep history after quitting" is on.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore(fileURL: SettingsStore.folderURL.appendingPathComponent("history.json"))
    static let limit = 20

    @Published private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL
    private var persistent = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
            persistent = true
        }
    }

    /// Turning it off deletes the file straight away (the in-memory list stays until Textly quits).
    func setPersistent(_ on: Bool) {
        persistent = on
        if on {
            save()
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func add(title: String, original: String, result: String, appName: String?) {
        let entry = HistoryEntry(date: Date(), title: title, original: original, result: result, appName: appName)
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        if persistent { save() }
    }

    func clear() {
        entries = []
        if persistent { save() }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Textly: could not save history: \(error.localizedDescription)")
        }
    }
}
