import AppKit
import Foundation
import Observation
import UserNotifications

/// Keeps Brewbox itself up to date from the GitHub releases `make release` publishes:
/// looks for a newer release once a day and, when asked, downloads its Brewbox.zip,
/// checks it, swaps it in for the running app and relaunches.
@MainActor
@Observable
final class AppUpdater {
    struct Release: Equatable, Sendable {
        /// "0.2.0", from the tag "v0.2.0".
        let version: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        case checkFailed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?

    /// The newer release, while it's waiting or being installed.
    var newRelease: Release? {
        switch status {
        case .available(let release), .installing(let release): release
        default: nil
        }
    }

    var isInstalling: Bool {
        if case .installing = status { return true }
        return false
    }

    /// Updating replaces the .app bundle; `swift run` has none.
    var isSupported: Bool { Preferences.isBundled }

    /// The latest release; BREWBOX_UPDATE_FEED points it at other JSON (a local file) for testing.
    nonisolated private static let feedURL = ProcessInfo.processInfo.environment["BREWBOX_UPDATE_FEED"]
        .flatMap(URL.init(string:))
        ?? URL(string: "https://api.github.com/repos/richardchvalny/brewbox/releases/latest")!
    nonisolated private static let assetName = "Brewbox.zip"
    private static let checkInterval: Duration = .seconds(24 * 60 * 60)
    private var schedulerTask: Task<Void, Never>?
    private var notifiedVersion: String?

    init() {
        guard isSupported else { return }
        schedulerTask = Task { [weak self] in
            // Let launch settle first.
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                if Preferences.checkAppUpdates { await self?.check() }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// Static updater for snapshots: no scheduler.
    init(preview status: Status) {
        self.status = status
    }

    /// Looks for a newer release. Automatic checks notify about it and stay quiet on failure.
    func check(userInitiated: Bool = false) async {
        let previous = status
        switch previous {
        case .checking, .installing: return
        default: break
        }
        status = .checking
        do {
            let latest = try await Self.fetchLatestRelease()
            lastChecked = .now
            if let latest, Self.isVersion(latest.version, newerThan: AppInfo.version) {
                status = .available(latest)
                if !userInitiated { notify(about: latest) }
            } else {
                status = .upToDate
            }
        } catch {
            status = userInitiated ? .checkFailed(error.localizedDescription) : previous
        }
    }

    /// Downloads and checks the new release, then quits; a helper swaps the bundle and relaunches it.
    func install() async throws {
        guard case .available(let release) = status else { return }
        status = .installing(release)
        do {
            let appURL = Bundle.main.bundleURL
            let newAppURL = try await Self.prepare(release, replacing: appURL)
            try Self.relaunch(replacing: appURL, with: newAppURL, after: ProcessInfo.processInfo.processIdentifier)
            AppDelegate.quit()
        } catch {
            status = .available(release)
            throw error
        }
    }

    /// `install()` with a failure shown as the panel's error banner.
    func install(reportingTo store: UpdateStore) {
        Task {
            do {
                try await install()
            } catch {
                store.error = ErrorReport(title: "Couldn't update Brewbox", error: error)
            }
        }
    }

    private func notify(about release: Release) {
        guard notifiedVersion != release.version, Preferences.notifications else { return }
        notifiedVersion = release.version
        let content = UNMutableNotificationContent()
        content.title = "Brewbox \(release.version) is available"
        content.body = "Open Brewbox from the menu bar to update."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    // MARK: - Releases

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }

    /// nil when there's no release (yet) or it has no Brewbox.zip.
    nonisolated static func fetchLatestRelease() async throws -> Release? {
        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Brewbox/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard http.statusCode == 200 else { throw UpdateError.server(http.statusCode) }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let latest = try decoder.decode(GitHubRelease.self, from: data)
        guard let asset = latest.assets.first(where: { $0.name == assetName }) else { return nil }
        let version = latest.tagName.hasPrefix("v") ? String(latest.tagName.dropFirst()) : latest.tagName
        return Release(version: version, downloadURL: asset.browserDownloadUrl, pageURL: latest.htmlUrl)
    }

    /// Compares dotted versions numerically, so "0.10.0" is newer than "0.9.1".
    nonisolated static func isVersion(_ version: String, newerThan current: String) -> Bool {
        let new = version.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Installing

    /// Downloads and unpacks the release next to `appURL` and checks it's a valid build of
    /// this app, signed by the same team. Returns the new app bundle.
    nonisolated static func prepare(_ release: Release, replacing appURL: URL) async throws -> URL {
        let fileManager = FileManager.default
        let folder = appURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: folder.path), fileManager.isWritableFile(atPath: appURL.path) else {
            throw UpdateError.notWritable(folder)
        }

        // On the app's volume, so the swap is a rename.
        let work = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                       appropriateFor: appURL, create: true)
        let (download, response) = try await URLSession.shared.download(from: release.downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.server(http.statusCode)
        }
        let zip = work.appendingPathComponent(assetName)
        try fileManager.moveItem(at: download, to: zip)
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        try? fileManager.removeItem(at: zip)

        let newApp = work.appendingPathComponent("Brewbox.app")
        guard let info = Bundle(url: newApp)?.infoDictionary else {
            throw UpdateError.invalidDownload("it doesn't contain Brewbox.app")
        }
        guard info["CFBundleIdentifier"] as? String == Bundle(url: appURL)?.bundleIdentifier else {
            throw UpdateError.invalidDownload("it's a different app")
        }
        guard info["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError.invalidDownload("it isn't version \(release.version)")
        }
        do {
            try runTool("/usr/bin/codesign", ["--verify", "--strict", newApp.path])
        } catch {
            throw UpdateError.invalidDownload("its code signature is broken")
        }
        if let team = teamIdentifier(of: appURL), teamIdentifier(of: newApp) != team {
            throw UpdateError.invalidDownload("it isn't signed by the same developer")
        }
        _ = try? runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        return newApp
    }

    /// Starts a helper that waits for `pid` to quit, puts `newAppURL` in place of `appURL`
    /// (restoring the old app if that fails) and opens it.
    nonisolated static func relaunch(replacing appURL: URL, with newAppURL: URL, after pid: Int32) throws {
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            work="$(dirname "$3")"
            if mv "$2" "$work/previous.app"; then
                mv "$3" "$2" || mv "$work/previous.app" "$2"
            fi
            open "$2"
            rm -rf "$work"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(pid), appURL.path, newAppURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// The signing team, or nil for ad-hoc signed builds.
    nonisolated private static func teamIdentifier(of url: URL) -> String? {
        guard let output = try? runTool("/usr/bin/codesign", ["-dv", url.path]) else { return nil }
        let team = output.split(separator: "\n")
            .first { $0.hasPrefix("TeamIdentifier=") }?
            .dropFirst("TeamIdentifier=".count)
        return team.map(String.init).flatMap { $0 == "not set" ? nil : $0 }
    }

    /// Runs a system tool and returns stdout and stderr together.
    @discardableResult
    nonisolated private static func runTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw UpdateError.toolFailed(URL(fileURLWithPath: path).lastPathComponent, output)
        }
        return output
    }
}

enum UpdateError: LocalizedError {
    case server(Int)
    case notWritable(URL)
    case invalidDownload(String)
    case toolFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .server(let status):
            "GitHub answered with HTTP \(status)."
        case .notWritable(let folder):
            "Brewbox can't replace itself in \(folder.path). Move it to Applications, or download the new version from GitHub."
        case .invalidDownload(let reason):
            "The downloaded update was rejected because \(reason)."
        case .toolFailed(let tool, let output):
            "\(tool) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
