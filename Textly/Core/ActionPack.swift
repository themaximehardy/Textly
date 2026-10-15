import Foundation

/// A shareable set of actions, saved as a .json file (Settings › Actions › Share).
/// Shortcuts are not included, so importing never clashes with your own.
struct ActionPack: Codable, Equatable {
    static let formatName = "textly-action-pack"

    var format: String = ActionPack.formatName
    var version: Int = 1
    var name: String
    var description: String?
    var actions: [Item]

    struct Item: Codable, Equatable {
        var name: String
        var icon: String
        var prompt: String
        var output: OutputMode
        /// Empty or missing: the user's default model.
        var model: String?
        var temperature: Double?
        var useSharedRules: Bool?
    }

    init(name: String, description: String? = nil, actions: [TextAction]) {
        self.name = name
        self.description = description
        self.actions = actions.map { action in
            Item(
                name: action.name,
                icon: action.icon,
                prompt: action.prompt,
                output: action.output,
                model: action.model.isEmpty ? nil : action.model,
                temperature: action.temperature,
                useSharedRules: action.useSharedRules
            )
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ActionPack {
        let pack: ActionPack
        do {
            pack = try JSONDecoder().decode(ActionPack.self, from: data)
        } catch {
            throw AIError(message: "This file isn't a Textly action pack.")
        }
        guard pack.format == formatName else {
            throw AIError(message: "This file isn't a Textly action pack.")
        }
        guard pack.version <= 1 else {
            throw AIError(message: "This pack was made by a newer version of Textly. Update Textly to import it.")
        }
        guard !pack.actions.isEmpty else {
            throw AIError(message: "This pack has no actions.")
        }
        return pack
    }

    /// New actions ready to add. Names that are already taken get " 2", " 3"…
    func makeActions(existingNames: [String]) -> [TextAction] {
        var taken = Set(existingNames.map { $0.lowercased() })
        return actions.compactMap { item in
            let base = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty, !prompt.isEmpty else { return nil }
            var name = base
            var counter = 2
            while taken.contains(name.lowercased()) {
                name = "\(base) \(counter)"
                counter += 1
            }
            taken.insert(name.lowercased())
            return TextAction(
                name: name,
                icon: item.icon.isEmpty ? "wand.and.stars" : item.icon,
                prompt: item.prompt,
                output: item.output,
                model: item.model ?? "",
                temperature: min(max(item.temperature ?? 0.3, 0), 1),
                useSharedRules: item.useSharedRules ?? true
            )
        }
    }
}

extension ActionPack {
    enum CodingKeys: String, CodingKey { case format, version, name, description, actions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Actions"
        description = try c.decodeIfPresent(String.self, forKey: .description)
        actions = try c.decode([Item].self, forKey: .actions)
    }
}
