import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class UpdateStore {
    private(set) var packages: [OutdatedPackage] = []
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    /// IDs of packages that are upgrading or waiting in the queue.
    private(set) var upgrading: Set<String> = []
    /// What brew is doing right now, shown in the header.
    private(set) var activity: String?
    private(set) var log = ""
    var errorMessage: String?

    /// Everything installed; empty until the Installed tab is first opened.
    private(set) var installed: [InstalledPackage] = []
    private(set) var isLoadingInstalled = false

    let brew: BrewService?

    var updatableCount: Int { packages.filter { !$0.pinned }.count }

    /// brew holds a global lock, so every command runs through this serial queue.
    private var queueTail: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var notifiedKeys: Set<String> = []

    private static let maxLogLength = 20_000

    init() {
        brew = BrewService.locate()
        if brew == nil {
            errorMessage = "Homebrew wasn't found in /opt/homebrew or /usr/local."
        }
        startScheduler()
    }

    // MARK: - Checking

    func check() async {
        guard let brew, !isChecking else { return }
        isChecking = true
        await enqueue { [self] in
            defer { isChecking = false }
            activity = "Checking for updates…"
            defer { activity = nil }

            var updateError: String?
            do {
                try await brew.run(["update"])
            } catch {
                // Offline or a broken tap: still report what brew already knows.
                updateError = "brew update failed: \(error.localizedDescription)"
            }

            do {
                try await refreshOutdated(using: brew)
                lastChecked = .now
                errorMessage = updateError
                notifyAboutNewUpdates()
            } catch {
                errorMessage = error.localizedDescription
            }
        }.value
    }

    private func refreshOutdated(using brew: BrewService) async throws {
        var arguments = ["outdated", "--json=v2"]
        if Preferences.greedy { arguments.append("--greedy") }
        var result = try OutdatedPackage.parse(try await brew.run(arguments))
        if !Preferences.includeCasks {
            result.removeAll { $0.kind == .cask }
        }
        packages = result
    }

    func outdatedPackage(for package: InstalledPackage) -> OutdatedPackage? {
        packages.first { $0.id == package.id }
    }

    // MARK: - Installed packages

    func loadInstalled() async {
        guard let brew, !isLoadingInstalled else { return }
        isLoadingInstalled = true
        await enqueue { [self] in
            defer { isLoadingInstalled = false }
            do {
                try await refreshInstalled(using: brew)
            } catch {
                errorMessage = "Couldn't list installed packages: \(error.localizedDescription)"
            }
        }.value
    }

    private func refreshInstalled(using brew: BrewService) async throws {
        installed = try InstalledPackage.parse(try await brew.run(["info", "--json=v2", "--installed"]))
    }

    /// Keeps the Installed tab current after upgrades, without loading it eagerly.
    private func refreshInstalledIfLoaded(using brew: BrewService) async {
        guard !installed.isEmpty else { return }
        try? await refreshInstalled(using: brew)
    }

    /// Checks on launch and then whenever the last check is older than the
    /// configured interval. Polling keeps interval changes effective immediately.
    private func startScheduler() {
        schedulerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                guard let self else { return }
                let interval = TimeInterval(Preferences.checkIntervalHours * 3600)
                if lastChecked.map({ Date.now.timeIntervalSince($0) >= interval }) ?? true {
                    await check()
                }
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
    }

    // MARK: - Upgrading

    func upgrade(_ package: OutdatedPackage) {
        guard let brew, !package.pinned, !upgrading.contains(package.id) else { return }
        upgrading.insert(package.id)

        var arguments = ["upgrade", package.kind == .cask ? "--cask" : "--formula"]
        if package.kind == .cask && Preferences.greedy { arguments.append("--greedy") }
        arguments.append(package.name)

        enqueue { [self] in
            defer { upgrading.remove(package.id) }
            activity = "Upgrading \(package.name)…"
            defer { activity = nil }
            do {
                try await runLogged(arguments, using: brew)
                packages.removeAll { $0.id == package.id }
            } catch {
                errorMessage = upgradeFailureMessage(package.name, error)
            }
            await refreshInstalledIfLoaded(using: brew)
        }
    }

    func upgradeAll() {
        guard let brew else { return }
        let targets = packages.filter { !$0.pinned && !upgrading.contains($0.id) }
        guard !targets.isEmpty else { return }
        upgrading.formUnion(targets.map(\.id))

        var arguments = ["upgrade"]
        if !Preferences.includeCasks { arguments.append("--formula") }
        if Preferences.greedy { arguments.append("--greedy") }

        enqueue { [self] in
            defer { upgrading.subtract(targets.map(\.id)) }
            activity = "Upgrading \(targets.count) packages…"
            defer { activity = nil }
            do {
                try await runLogged(arguments, using: brew)
            } catch {
                errorMessage = upgradeFailureMessage(nil, error)
            }
            // Some packages may have failed; ask brew what's left.
            try? await refreshOutdated(using: brew)
            await refreshInstalledIfLoaded(using: brew)
        }
    }

    /// Only formulae can be pinned.
    func togglePin(name: String, isPinned: Bool) {
        guard let brew else { return }
        enqueue { [self] in
            do {
                try await brew.run([isPinned ? "unpin" : "pin", name])
                try await refreshOutdated(using: brew)
                await refreshInstalledIfLoaded(using: brew)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func upgradeFailureMessage(_ name: String?, _ error: Error) -> String {
        let subject = name.map { "Upgrading \($0)" } ?? "Upgrade"
        var message = "\(subject) failed: \(error.localizedDescription)"
        if error.localizedDescription.contains("sudo") || error.localizedDescription.contains("password") {
            message += "\nThis package needs an administrator password — run the upgrade in Terminal."
        }
        return message
    }

    // MARK: - Helpers

    private func runLogged(_ arguments: [String], using brew: BrewService) async throws {
        appendLog("\n$ brew \(arguments.joined(separator: " "))\n")
        try await brew.run(arguments) { [weak self] chunk in
            Task { @MainActor in self?.appendLog(chunk) }
        }
    }

    private func appendLog(_ text: String) {
        log += text
        if log.count > Self.maxLogLength {
            log = String(log.suffix(Self.maxLogLength))
        }
    }

    func clearLog() {
        log = ""
    }

    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = queueTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        queueTail = task
        return task
    }

    private func notifyAboutNewUpdates() {
        let candidates = packages.filter { !$0.pinned }
        let fresh = candidates.filter { !notifiedKeys.contains(notificationKey($0)) }
        notifiedKeys.formUnion(candidates.map(notificationKey))

        guard !fresh.isEmpty, Preferences.notifications, Preferences.isBundled else { return }

        let content = UNMutableNotificationContent()
        content.title = fresh.count == 1 ? "Update available" : "\(fresh.count) updates available"
        content.body = fresh.prefix(5).map { "\($0.name) \(displayVersion($0.currentVersion))" }
            .joined(separator: ", ") + (fresh.count > 5 ? ", …" : "")
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private func notificationKey(_ package: OutdatedPackage) -> String {
        "\(package.id)@\(package.currentVersion)"
    }
}
