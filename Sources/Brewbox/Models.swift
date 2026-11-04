import Foundation

enum PackageKind: String, Sendable {
    case formula
    case cask
}

struct OutdatedPackage: Identifiable, Hashable, Sendable {
    let name: String
    let kind: PackageKind
    let installedVersion: String
    let currentVersion: String
    let pinned: Bool

    var id: String { "\(kind.rawValue):\(name)" }
}

extension OutdatedPackage {
    /// Parses `brew outdated --json=v2`.
    static func parse(_ json: String) throws -> [OutdatedPackage] {
        let response = try JSONDecoder().decode(OutdatedResponse.self, from: Data(json.utf8))
        let formulae = response.formulae.map { $0.package(kind: .formula) }
        let casks = response.casks.map { $0.package(kind: .cask) }
        return (formulae + casks).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct InstalledPackage: Identifiable, Hashable, Sendable {
    /// Formula name or cask token — what brew commands take.
    let name: String
    /// Human-facing name: the app name for casks, the formula name otherwise.
    let title: String
    let kind: PackageKind
    let version: String
    let summary: String?
    let homepage: URL?
    let pinned: Bool
    /// False for formulae that were only pulled in as dependencies.
    let installedOnRequest: Bool

    var id: String { "\(kind.rawValue):\(name)" }
}

extension InstalledPackage {
    /// Parses `brew info --json=v2 --installed`.
    static func parse(_ json: String) throws -> [InstalledPackage] {
        let response = try JSONDecoder().decode(InfoResponse.self, from: Data(json.utf8))
        let formulae = response.formulae.map { formula in
            InstalledPackage(
                name: formula.name,
                title: formula.name,
                kind: .formula,
                version: formula.installed.last?.version ?? "?",
                summary: formula.desc,
                homepage: formula.homepage.flatMap(URL.init(string:)),
                pinned: formula.pinned ?? false,
                installedOnRequest: formula.installed.contains { $0.installedOnRequest ?? true }
            )
        }
        let casks = response.casks.map { cask in
            InstalledPackage(
                name: cask.token,
                title: cask.name?.first ?? cask.token,
                kind: .cask,
                version: cask.installed ?? cask.version ?? "?",
                summary: cask.desc,
                homepage: cask.homepage.flatMap(URL.init(string:)),
                pinned: false,
                installedOnRequest: true
            )
        }
        return (formulae + casks).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

private struct InfoResponse: Decodable {
    let formulae: [Formula]
    let casks: [Cask]

    struct Formula: Decodable {
        let name: String
        let desc: String?
        let homepage: String?
        let pinned: Bool?
        let installed: [Keg]

        struct Keg: Decodable {
            let version: String
            let installedOnRequest: Bool?

            enum CodingKeys: String, CodingKey {
                case version
                case installedOnRequest = "installed_on_request"
            }
        }
    }

    struct Cask: Decodable {
        let token: String
        let name: [String]?
        let desc: String?
        let homepage: String?
        let installed: String?
        let version: String?
    }
}

/// A Homebrew tap: a git repository of formulae and casks.
struct Tap: Identifiable, Hashable, Sendable {
    /// "user/repo", what `brew tap` and `brew untap` take.
    let name: String
    let remote: String?
    /// Short formula names and cask tokens, without the tap prefix.
    let formulaNames: [String]
    let caskTokens: [String]

    var id: String { name }
    var packageCount: Int { formulaNames.count + caskTokens.count }

    /// The taps Brewbox already searches through the formulae.brew.sh catalog.
    static let defaultNames: Set<String> = ["homebrew/core", "homebrew/cask"]

    /// Fully qualified names, for `brew info`.
    var qualifiedNames: [String] {
        (formulaNames + caskTokens).map { "\(name)/\($0)" }
    }

    var webURL: URL? {
        guard let remote, remote.hasPrefix("http") else { return nil }
        return URL(string: remote.hasSuffix(".git") ? String(remote.dropLast(4)) : remote)
    }
}

extension Tap {
    /// Parses `brew tap-info --json --installed`, keeping only taps added by the user.
    /// It lists homebrew/core and homebrew/cask even when they aren't cloned.
    static func parse(_ json: String) throws -> [Tap] {
        try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
            .filter { $0.installed && !defaultNames.contains($0.name) }
            .map { entry in
                // Names come qualified ("user/repo/name") in some brew versions.
                func short(_ name: String) -> String { name.split(separator: "/").last.map(String.init) ?? name }
                return Tap(
                    name: entry.name,
                    remote: entry.remote,
                    formulaNames: (entry.formulaNames ?? []).map(short).sorted(),
                    caskTokens: (entry.caskTokens ?? []).map(short).sorted()
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Turns what the user typed or pasted into `brew tap` arguments: "user/repo",
    /// "brew tap user/repo", "user/repo/package", or a git URL. Returns nil when
    /// it's none of those.
    static func tapArguments(for input: String) -> [String]? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["brew tap ", "brew install --cask ", "brew install "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if text.contains("://") || text.hasPrefix("git@") || text.hasPrefix("github.com/") {
            // The repository path, after "host/" or, for scp-style URLs, "host:".
            var path = text
            if let range = path.range(of: "://") { path = String(path[range.upperBound...]) }
            guard let separator = path.firstIndex(where: { $0 == "/" || $0 == ":" }) else { return nil }
            path = String(path[path.index(after: separator)...])
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2, isValidComponent(parts[0]) else { return nil }
            var repo = parts[1]
            if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
            guard isValidComponent(repo) else { return nil }
            let user = parts[0].lowercased()
            let lowered = repo.lowercased()
            // brew only infers the URL for GitHub repos named "homebrew-<name>".
            if text.contains("github.com"), lowered.hasPrefix("homebrew-") {
                return ["tap", "\(user)/\(lowered.dropFirst("homebrew-".count))"]
            }
            let url = text.hasPrefix("github.com/") ? "https://\(text)" : text
            return ["tap", "\(user)/\(lowered)", url]
        }

        let parts = text.split(separator: "/").map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy(isValidComponent) else { return nil }
        return ["tap", "\(parts[0])/\(parts[1])".lowercased()]
    }

    private static func isValidComponent(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isLetter || $0.isNumber || "-_.@".contains($0) }
    }

    private struct Entry: Decodable {
        let name: String
        let remote: String?
        let installed: Bool
        let formulaNames: [String]?
        let caskTokens: [String]?

        enum CodingKeys: String, CodingKey {
            case name, remote, installed
            case formulaNames = "formula_names"
            case caskTokens = "cask_tokens"
        }
    }
}

/// Cask versions often carry a build suffix ("3.9,3.9.0.88839"); show only the
/// human-facing part.
func displayVersion(_ version: String) -> String {
    version.split(separator: ",").first.map(String.init) ?? version
}

private struct OutdatedResponse: Decodable {
    let formulae: [Entry]
    let casks: [Entry]

    struct Entry: Decodable {
        let name: String
        let installedVersions: [String]
        let currentVersion: String
        let pinned: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
            case pinned
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            currentVersion = try container.decode(String.self, forKey: .currentVersion)
            pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
            // Older brew versions emit a single string for casks.
            if let versions = try? container.decode([String].self, forKey: .installedVersions) {
                installedVersions = versions
            } else {
                installedVersions = [try container.decode(String.self, forKey: .installedVersions)]
            }
        }

        func package(kind: PackageKind) -> OutdatedPackage {
            OutdatedPackage(
                name: name,
                kind: kind,
                installedVersion: installedVersions.last ?? "?",
                currentVersion: currentVersion,
                pinned: pinned
            )
        }
    }
}
