import Foundation

/// The app used to be "Homebrew Toolbox" (bundle ID local.HomebrewToolbox).
/// Carries its settings over to the new bundle ID and drops its catalog cache.
enum LegacyMigration {
    private static let legacyDomain = "local.HomebrewToolbox"
    private static let doneKey = "migratedFromHomebrewToolbox"
    /// Settings the current version no longer reads.
    private static let obsoleteKeys: Set<String> = ["checkIntervalHours"]

    static func run() {
        let defaults = UserDefaults.standard
        guard Preferences.isBundled, !defaults.bool(forKey: doneKey) else { return }

        if let legacy = defaults.persistentDomain(forName: legacyDomain) {
            for (key, value) in legacy where !obsoleteKeys.contains(key) && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            defaults.removePersistentDomain(forName: legacyDomain)
        }

        let legacyCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomebrewToolbox", isDirectory: true)
        try? FileManager.default.removeItem(at: legacyCache)

        defaults.set(true, forKey: doneKey)
    }
}
