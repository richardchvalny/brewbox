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
    private(set) var activity: String? {
        didSet { updateIconAnimation() }
    }
    /// Current bubbles animation frame; nil while idle.
    private(set) var iconFrame: Int?
    private var animationTask: Task<Void, Never>?
    private(set) var log = ""
    /// The latest failure, shown as a banner until dismissed.
    var error: ErrorReport?
    /// `brew --version`, for error reports.
    private(set) var brewVersion: String?

    var systemInfo: SystemInfo {
        SystemInfo(brewVersion: brewVersion, brewPath: brew?.brewURL.path)
    }

    /// Everything installed; empty until the Installed tab is first opened.
    private(set) var installed: [InstalledPackage] = []
    private(set) var isLoadingInstalled = false

    /// The full Homebrew catalog for discovering new packages; loaded on demand.
    private(set) var catalog: [CatalogPackage] = []
    private(set) var isLoadingCatalog = false
    private(set) var catalogError: String?
    /// IDs of packages being installed or waiting in the queue.
    private(set) var installing: Set<String> = []
    /// IDs of packages being uninstalled or waiting in the queue.
    private(set) var uninstalling: Set<String> = []
    private let catalogService = CatalogService()

    var installedIDs: Set<String> { Set(installed.map(\.id)) }

    /// When the last scheduled check ran; persisted so the schedule survives relaunches.
    private(set) var lastScheduledRun: Date? = UserDefaults.standard.object(forKey: Preferences.Key.lastScheduledRun) as? Date {
        didSet { UserDefaults.standard.set(lastScheduledRun, forKey: Preferences.Key.lastScheduledRun) }
    }
    /// When scheduling started, so the first run doesn't drift before it happens.
    let scheduleAnchor: Date
    /// Packages the user opted out of automatic updates.
    private(set) var autoUpdateExcluded = Set(UserDefaults.standard.stringArray(forKey: Preferences.Key.autoUpdateExcluded) ?? []) {
        didSet { UserDefaults.standard.set(autoUpdateExcluded.sorted(), forKey: Preferences.Key.autoUpdateExcluded) }
    }

    var nextScheduledRun: Date {
        Preferences.schedule.nextRun(after: lastScheduledRun, anchor: scheduleAnchor)
    }

    let brew: BrewService?

    var updatableCount: Int { packages.filter { !$0.pinned }.count }

    /// brew holds a global lock, so every command runs through this serial queue.
    private var queueTail: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var notifiedKeys: Set<String> = []

    private static let maxLogLength = 20_000

    init() {
        scheduleAnchor = Self.loadScheduleAnchor()
        brew = BrewService.locate()
        if let brew {
            Task { [weak self] in
                let version = try? await brew.run(["--version"])
                self?.brewVersion = version?.split(separator: "\n").first.map(String.init)
            }
        } else {
            error = ErrorReport(
                title: "Homebrew not found",
                message: "Homebrew wasn't found in /opt/homebrew or /usr/local.",
                hint: "Install it from brew.sh, then reopen the app."
            )
        }
        startScheduler()
    }

    /// Static store for snapshots: no brew, no scheduler.
    init(
        preview packages: [OutdatedPackage],
        installed: [InstalledPackage],
        catalog: [CatalogPackage] = [],
        log: String = "",
        error: ErrorReport? = nil
    ) {
        brew = BrewService(brewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        scheduleAnchor = .now
        self.error = error
        brewVersion = "Homebrew 7.0.11"
        self.packages = packages
        self.installed = installed
        self.catalog = catalog
        self.log = log
        lastChecked = .now.addingTimeInterval(-12 * 60)
    }

    // MARK: - Checking

    func check() async {
        guard let brew, !isChecking else { return }
        isChecking = true
        await enqueue { [self] in
            defer { isChecking = false }
            activity = "Checking for updates…"
            defer { activity = nil }

            var updateError: ErrorReport?
            do {
                try await brew.run(["update"])
            } catch {
                // Offline or a broken tap: still report what brew already knows.
                updateError = ErrorReport(title: "Couldn't update Homebrew", error: error)
            }

            do {
                try await refreshOutdated(using: brew)
                lastChecked = .now
                self.error = updateError
                notifyAboutNewUpdates()
            } catch {
                self.error = ErrorReport(title: "Couldn't check for updates", error: error)
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

    func outdatedPackage(id: String) -> OutdatedPackage? {
        packages.first { $0.id == id }
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
                self.error = ErrorReport(title: "Couldn't list installed packages", error: error)
            }
        }.value
    }

    private func refreshInstalled(using brew: BrewService) async throws {
        installed = try InstalledPackage.parse(try await brew.run(["info", "--json=v2", "--installed"]))
    }

    // MARK: - Discovering and installing

    func loadCatalog(forceRefresh: Bool = false) async {
        guard !isLoadingCatalog, catalog.isEmpty || forceRefresh else { return }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            catalog = try await catalogService.load(forceRefresh: forceRefresh)
            catalogError = nil
        } catch {
            catalogError = "Couldn't load the Homebrew catalog. Check your connection and try again."
        }
    }

    func install(_ package: CatalogPackage) {
        guard let brew, !installing.contains(package.id), !installedIDs.contains(package.id) else { return }
        installing.insert(package.id)
        let arguments = ["install", package.kind == .cask ? "--cask" : "--formula", package.name]

        enqueue { [self] in
            defer { installing.remove(package.id) }
            activity = "Installing \(package.title)…"
            defer { activity = nil }
            do {
                try await runLogged(arguments, using: brew)
            } catch {
                self.error = ErrorReport(title: "Installing \(package.title) failed", error: error)
            }
            // Always reload so the new package shows as installed everywhere.
            try? await refreshInstalled(using: brew)
        }
    }

    /// brew refuses to remove a formula other installed formulae depend on; that
    /// error is shown as-is.
    func uninstall(_ package: CatalogPackage) {
        guard let brew, !uninstalling.contains(package.id), installedIDs.contains(package.id) else { return }
        uninstalling.insert(package.id)
        let arguments = ["uninstall", package.kind == .cask ? "--cask" : "--formula", package.name]

        enqueue { [self] in
            defer { uninstalling.remove(package.id) }
            activity = "Uninstalling \(package.title)…"
            defer { activity = nil }
            do {
                try await runLogged(arguments, using: brew)
                packages.removeAll { $0.id == package.id }
            } catch {
                self.error = ErrorReport(title: "Uninstalling \(package.title) failed", error: error)
            }
            try? await refreshInstalled(using: brew)
        }
    }

    /// Detail data for an installed package: the catalog entry when there is one,
    /// otherwise what `brew info` reported (packages from third-party taps).
    func catalogPackage(for package: InstalledPackage) -> CatalogPackage {
        if let entry = catalog.first(where: { $0.id == package.id }) {
            return entry
        }
        return CatalogPackage(
            name: package.name,
            title: package.title,
            kind: package.kind,
            version: package.version,
            summary: package.summary,
            homepage: package.homepage,
            license: nil,
            dependencies: [],
            caveats: nil,
            tap: nil,
            deprecated: false,
            autoUpdates: false
        )
    }

    /// Keeps the Installed tab current after upgrades, without loading it eagerly.
    private func refreshInstalledIfLoaded(using brew: BrewService) async {
        guard !installed.isEmpty else { return }
        try? await refreshInstalled(using: brew)
    }

    private static func loadScheduleAnchor() -> Date {
        if let anchor = UserDefaults.standard.object(forKey: Preferences.Key.scheduleAnchor) as? Date {
            return anchor
        }
        let anchor = Date.now
        UserDefaults.standard.set(anchor, forKey: Preferences.Key.scheduleAnchor)
        return anchor
    }

    /// Checks once on launch so the menu bar is current, then runs the scheduled
    /// check (and automatic update) whenever it comes due. Polling every minute
    /// picks up schedule changes and catches up after the Mac wakes.
    private func startScheduler() {
        schedulerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.check()
            while !Task.isCancelled {
                guard let self else { return }
                if Date.now >= nextScheduledRun {
                    await runScheduled()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func runScheduled() async {
        // Recorded first, so a failing check doesn't retry every minute.
        lastScheduledRun = .now
        await check()
        if Preferences.autoUpdate {
            let targets = packages.filter { !$0.pinned && !autoUpdateExcluded.contains($0.id) }
            upgrade(targets, automatically: true)
        }
    }

    // MARK: - Automatic updates

    /// Every package updates automatically unless the user turned it off.
    func isAutoUpdateEnabled(id: String) -> Bool {
        !autoUpdateExcluded.contains(id)
    }

    func setAutoUpdate(_ enabled: Bool, id: String) {
        if enabled {
            autoUpdateExcluded.remove(id)
        } else {
            autoUpdateExcluded.insert(id)
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
                self.error = ErrorReport(title: "Upgrading \(package.name) failed", error: error)
            }
            await refreshInstalledIfLoaded(using: brew)
        }
    }

    func upgradeAll() {
        upgrade(packages, automatically: false)
    }

    /// Upgrades formulae and casks with separate commands, so a name shared by a
    /// formula and a cask can't be resolved to the wrong one.
    private func upgrade(_ candidates: [OutdatedPackage], automatically: Bool) {
        guard let brew else { return }
        let targets = candidates.filter { !$0.pinned && !upgrading.contains($0.id) }
        guard !targets.isEmpty else { return }
        upgrading.formUnion(targets.map(\.id))

        var commands: [[String]] = []
        let formulae = targets.filter { $0.kind == .formula }.map(\.name)
        if !formulae.isEmpty {
            commands.append(["upgrade", "--formula"] + formulae)
        }
        let casks = targets.filter { $0.kind == .cask }.map(\.name)
        if !casks.isEmpty {
            commands.append(["upgrade", "--cask"] + (Preferences.greedy ? ["--greedy"] : []) + casks)
        }

        enqueue { [self] in
            defer { upgrading.subtract(targets.map(\.id)) }
            let count = targets.count == 1 ? targets[0].name : "\(targets.count) packages"
            activity = automatically ? "Updating \(count) automatically…" : "Upgrading \(count)…"
            defer { activity = nil }

            for arguments in commands {
                do {
                    try await runLogged(arguments, using: brew)
                } catch {
                    self.error = ErrorReport(
                        title: automatically ? "Automatic update failed" : "Upgrading packages failed",
                        error: error
                    )
                }
            }
            // Some packages may have failed; ask brew what's left.
            try? await refreshOutdated(using: brew)
            await refreshInstalledIfLoaded(using: brew)
            if automatically {
                let remaining = Set(packages.map(\.id))
                notifyAboutAutomaticUpdates(targets.filter { !remaining.contains($0.id) })
            }
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
                self.error = ErrorReport(title: isPinned ? "Unpinning \(name) failed" : "Pinning \(name) failed", error: error)
            }
        }
    }

    // MARK: - Helpers

    private func updateIconAnimation() {
        if activity != nil {
            guard animationTask == nil else { return }
            animationTask = Task { [weak self] in
                var frame = 0
                while !Task.isCancelled {
                    self?.iconFrame = frame
                    frame = (frame + 1) % BubblesIcon.frameCount
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        } else {
            animationTask?.cancel()
            animationTask = nil
            iconFrame = nil
        }
    }

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

    private func notifyAboutAutomaticUpdates(_ updated: [OutdatedPackage]) {
        guard !updated.isEmpty, Preferences.notifications, Preferences.isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = updated.count == 1 ? "Updated \(updated[0].name)" : "Updated \(updated.count) packages"
        content.body = updated.prefix(5).map { "\($0.name) \(displayVersion($0.currentVersion))" }
            .joined(separator: ", ") + (updated.count > 5 ? ", …" : "")
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private func notificationKey(_ package: OutdatedPackage) -> String {
        "\(package.id)@\(package.currentVersion)"
    }
}
