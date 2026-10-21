import AppKit
import Security
import ServiceManagement

/// Installs updates in place and makes sure the right copy of Textly is running.
@MainActor
enum AppInstaller {
    struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Textly can replace itself when it runs from a normal, writable folder
    /// (not straight from the disk image, and not a read-only "translocated" copy macOS makes for downloads).
    static var canReplaceItself: Bool {
        let path = Bundle.main.bundlePath
        guard !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else { return false }
        let folder = (path as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: folder) && FileManager.default.isWritableFile(atPath: path)
    }

    /// Downloads the DMG, copies the new Textly.app over this one and restarts.
    static func install(from dmgURL: URL, version: String) async throws {
        Toast.shared.show("Downloading Textly \(version)…", icon: "arrow.down.circle", spinning: true, duration: nil)
        defer { Toast.shared.hide() }

        let (downloaded, response) = try await URLSession.shared.download(from: dmgURL)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw InstallError(message: "The download failed (HTTP \(status)).")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("TextlyUpdate-\(UUID().uuidString)")
        let dmg = work.appendingPathComponent("Textly.dmg")
        let mount = work.appendingPathComponent("mount")
        let staged = work.appendingPathComponent("Textly.app")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: downloaded, to: dmg)

        Toast.shared.show("Installing Textly \(version)…", icon: "arrow.down.circle", spinning: true, duration: nil)
        try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        do {
            let apps = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }
            guard let app = apps.first(where: { $0.lastPathComponent == "Textly.app" }) ?? apps.first else {
                throw InstallError(message: "Textly.app wasn't found in the download.")
            }
            try await run("/usr/bin/ditto", [app.path, staged.path])
        } catch {
            try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            throw error
        }
        try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])

        guard let bundle = Bundle(url: staged), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw InstallError(message: "The download isn't a Textly app.")
        }
        // Safety: only install a correctly signed app, from the same developer as this one.
        guard isValidlySigned(staged) else {
            throw InstallError(message: "The download's signature isn't valid, so it wasn't installed.")
        }
        if let ourTeam = teamID(ofAppAt: URL(fileURLWithPath: Bundle.main.bundlePath)),
           teamID(ofAppAt: staged) != ourTeam {
            throw InstallError(message: "The download isn't signed by the same developer as this Textly, so it wasn't installed.")
        }
        try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        let current = URL(fileURLWithPath: Bundle.main.bundlePath)
        _ = try FileManager.default.replaceItemAt(current, withItemAt: staged)
        try? FileManager.default.removeItem(at: work)
        relaunch()
    }

    /// The Apple Developer Team ID an app is signed with (nil when signed ad hoc or not signed).
    static func teamID(ofAppAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The app's signature is intact (nothing was changed after signing).
    static func isValidlySigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate) | UInt32(kSecCSCheckNestedCode))
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }

    /// Quits and opens Textly again (this copy, or another one).
    static func relaunch(at path: String = Bundle.main.bundlePath) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "sh", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// A newer Textly in an Applications folder, when this copy is an older one somewhere else
    /// (for example a copy built with Xcode, or an old download).
    static func newerInstalledCopy() -> (path: String, version: String)? {
        let here = URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL.path
        guard let current = AppVersion(AppInfo.version) else { return nil }
        let candidates = ["/Applications/Textly.app", NSHomeDirectory() + "/Applications/Textly.app"]
        for path in candidates where URL(fileURLWithPath: path).standardizedFileURL.path != here {
            guard let bundle = Bundle(path: path),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let text = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
                  let version = AppVersion(text), current < version else { continue }
            return (path, text)
        }
        return nil
    }

    /// At launch: offer to switch to a newer copy, and point "Launch at login" at this copy.
    static func checkRunningCopy() {
        if let newer = newerInstalledCopy() {
            let alert = NSAlert()
            alert.messageText = "A newer Textly is installed"
            alert.informativeText = "You opened Textly \(AppInfo.version) from \(Bundle.main.bundlePath).\nTextly \(newer.version) is in \(newer.path). Open the newer one instead?"
            alert.addButton(withTitle: "Open Textly \(newer.version)")
            alert.addButton(withTitle: "Keep This One")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                relaunch(at: newer.path)
                return
            }
        }
        if SMAppService.mainApp.status == .enabled {
            // Re-register so the login item opens this copy, not an older one.
            try? SMAppService.mainApp.register()
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let name = (tool as NSString).lastPathComponent
                    continuation.resume(throwing: InstallError(message: "\(name) failed (code \(finished.terminationStatus))."))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
