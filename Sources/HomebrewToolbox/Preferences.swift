import Foundation

/// UserDefaults keys shared by `@AppStorage` in views and by `UpdateStore`.
enum Preferences {
    enum Key {
        static let checkIntervalHours = "checkIntervalHours"
        static let includeCasks = "includeCasks"
        static let greedy = "greedy"
        static let notifications = "notifications"
        static let showCountInMenuBar = "showCountInMenuBar"
    }

    static let defaultCheckIntervalHours = 4

    private static var defaults: UserDefaults { .standard }

    static var checkIntervalHours: Int {
        defaults.object(forKey: Key.checkIntervalHours) as? Int ?? defaultCheckIntervalHours
    }

    static var includeCasks: Bool {
        defaults.object(forKey: Key.includeCasks) as? Bool ?? true
    }

    /// Also report casks that update themselves (`auto_updates true`) or use `version :latest`.
    static var greedy: Bool {
        defaults.object(forKey: Key.greedy) as? Bool ?? false
    }

    static var notifications: Bool {
        defaults.object(forKey: Key.notifications) as? Bool ?? true
    }

    /// Notifications and login items need a real .app bundle; `swift run` has none.
    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }
}
