import Foundation

/// UserDefaults keys shared by `@AppStorage` in views and by `UpdateStore`.
enum Preferences {
    enum Key {
        static let checkFrequency = "checkFrequency"
        static let checkMinuteOfDay = "checkMinuteOfDay"
        static let autoUpdate = "autoUpdate"
        static let autoUpdateExcluded = "autoUpdateExcluded"
        static let lastScheduledRun = "lastScheduledRun"
        static let scheduleAnchor = "scheduleAnchor"
        static let includeCasks = "includeCasks"
        static let greedy = "greedy"
        static let notifications = "notifications"
        static let showCountInMenuBar = "showCountInMenuBar"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let checkAppUpdates = "checkAppUpdates"
    }

    static let defaultCheckFrequency = CheckFrequency.daily
    /// 9:00.
    static let defaultCheckMinuteOfDay = 9 * 60

    private static var defaults: UserDefaults { .standard }

    static var schedule: UpdateSchedule {
        UpdateSchedule(
            frequency: defaults.string(forKey: Key.checkFrequency).flatMap(CheckFrequency.init) ?? defaultCheckFrequency,
            minuteOfDay: defaults.object(forKey: Key.checkMinuteOfDay) as? Int ?? defaultCheckMinuteOfDay
        )
    }

    /// Install updates on schedule, except pinned and excluded packages.
    static var autoUpdate: Bool {
        defaults.object(forKey: Key.autoUpdate) as? Bool ?? false
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

    /// Look for new Brewbox releases on GitHub once a day.
    static var checkAppUpdates: Bool {
        defaults.object(forKey: Key.checkAppUpdates) as? Bool ?? true
    }

    /// Notifications and login items need a real .app bundle; `swift run` has none.
    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }
}
