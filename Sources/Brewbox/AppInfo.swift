import Foundation

/// Version and credits, read from the bundle's Info.plist.
enum AppInfo {
    static let author = "Richard Chválny"
    static let repositoryURL = URL(string: "https://github.com/richardchvalny/brewbox")!

    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// "0.1.0", or "dev" when running from `swift run` without a bundle.
    static var version: String {
        info["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var copyright: String {
        info["NSHumanReadableCopyright"] as? String ?? "© 2026 \(author)"
    }
}
