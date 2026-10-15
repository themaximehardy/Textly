import AppKit

/// "1.2.10" > "1.2.9". Ignores a leading "v" and anything after "-" (e.g. "0.4.0-beta").
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("v") { trimmed.removeFirst() }
        if let dash = trimmed.firstIndex(of: "-") { trimmed = String(trimmed[..<dash]) }
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct ReleaseInfo: Equatable {
    let version: String
    let pageURL: URL
    let downloadURL: URL?
    let notes: String

    /// Reads GitHub's "latest release" JSON.
    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        if (json["draft"] as? Bool) == true || (json["prerelease"] as? Bool) == true { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        return ReleaseInfo(version: tag, pageURL: page, downloadURL: dmg, notes: json["body"] as? String ?? "")
    }
}

/// Checks GitHub for a newer release once a day (and from the menu: Check for Updates…).
/// Textly isn't signed with an Apple Developer ID yet, so it can't replace itself silently:
/// it offers to download the new DMG instead.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let defaults = UserDefaults.standard
    private let lastCheckKey = "TextlyLastUpdateCheck"
    private let skippedKey = "TextlySkippedVersion"
    private var timer: Timer?
    private var isChecking = false

    /// Called at launch: checks now if a day has passed, then every few hours.
    func start(enabled: @escaping @MainActor () -> Bool) {
        timer?.invalidate()
        let tick: @MainActor () -> Void = { [weak self] in
            guard let self, enabled() else { return }
            let last = self.defaults.object(forKey: self.lastCheckKey) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 23 * 3600 {
                Task { await self.check(userInitiated: false) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            MainActor.assumeIsolated { tick() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let url = URL(string: "https://api.github.com/repos/\(AppInfo.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Textly/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            defaults.set(Date(), forKey: lastCheckKey)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                if userInitiated {
                    if status == 404 {
                        showUpToDate(note: "No release has been published yet.")
                    } else {
                        alert(title: "Couldn't check for updates", message: "GitHub returned an error (HTTP \(status)). Try again later.", buttons: ["OK"])
                    }
                }
                return
            }
            guard let release = ReleaseInfo.parse(data) else {
                if userInitiated { showUpToDate(note: nil) }
                return
            }
            guard let latest = AppVersion(release.version),
                  let current = AppVersion(AppInfo.version),
                  current < latest else {
                if userInitiated { showUpToDate(note: nil) }
                return
            }
            if !userInitiated && defaults.string(forKey: skippedKey) == latest.description { return }
            showUpdate(release, version: latest.description)
        } catch {
            if userInitiated {
                alert(title: "Couldn't check for updates", message: error.localizedDescription, buttons: ["OK"])
            }
        }
    }

    private func showUpdate(_ release: ReleaseInfo, version: String) {
        let notes = release.notes
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(12)
            .joined(separator: "\n")
        let message = "You have \(AppInfo.version). Download the new version, open it and drag Textly to Applications to replace the old one."
            + (notes.isEmpty ? "" : "\n\n" + notes)
        let response = alert(
            title: "Textly \(version) is available",
            message: message,
            buttons: ["Download", "Later", "Skip This Version"]
        )
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        case .alertThirdButtonReturn:
            defaults.set(version, forKey: skippedKey)
        default:
            break
        }
    }

    private func showUpToDate(note: String?) {
        alert(
            title: "Textly is up to date",
            message: "You have the latest version (\(AppInfo.version))." + (note.map { " \($0)" } ?? ""),
            buttons: ["OK"]
        )
    }

    @discardableResult
    private func alert(title: String, message: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        NSApp.activate()
        return alert.runModal()
    }
}
