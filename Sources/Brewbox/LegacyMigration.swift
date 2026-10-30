import Foundation

/// Carries settings over from the app's earlier bundle IDs: "Homebrew Toolbox"
/// (local.HomebrewToolbox) and Brewbox 0.1.0 (local.Brewbox). Drops the old catalog cache.
enum LegacyMigration {
    private static let legacyDomains = ["local.Brewbox", "local.HomebrewToolbox"]
    private static let doneKey = "migratedLegacySettings"
    /// Settings the current version no longer reads.
    private static let obsoleteKeys: Set<String> = ["checkIntervalHours", "migratedFromHomebrewToolbox"]

    static func run() {
        let defaults = UserDefaults.standard
        guard Preferences.isBundled, !defaults.bool(forKey: doneKey) else { return }

        // Newest first, so its values win over older ones.
        for domain in legacyDomains {
            guard let legacy = defaults.persistentDomain(forName: domain) else { continue }
            for (key, value) in legacy where shouldCopy(key) && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            defaults.removePersistentDomain(forName: domain)
        }

        let legacyCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomebrewToolbox", isDirectory: true)
        try? FileManager.default.removeItem(at: legacyCache)

        defaults.set(true, forKey: doneKey)
    }

    /// AppKit's own state stays behind: a menu bar item macOS once hid ("NSStatusItem
    /// VisibleCC …") would otherwise stay hidden under the new ID too.
    private static func shouldCopy(_ key: String) -> Bool {
        !obsoleteKeys.contains(key) && !key.hasPrefix("NSStatusItem") && !key.hasPrefix("NSWindow")
    }
}
