import Foundation

/// A formula or cask from the public Homebrew catalog, installed or not.
struct CatalogPackage: Identifiable, Hashable, Sendable {
    /// Formula name or cask token — what `brew install` takes.
    let name: String
    let title: String
    let kind: PackageKind
    let version: String
    let summary: String?
    let homepage: URL?
    let license: String?
    let dependencies: [String]
    let caveats: String?
    let tap: String
    let deprecated: Bool
    let autoUpdates: Bool

    var id: String { "\(kind.rawValue):\(name)" }

    var brewPageURL: URL {
        URL(string: "https://formulae.brew.sh/\(kind.rawValue)/\(name)")!
    }

    var installCommand: String {
        kind == .cask ? "brew install --cask \(name)" : "brew install \(name)"
    }
}

/// Downloads the catalog from formulae.brew.sh, caches it on disk for a day, and
/// falls back to the stale copy when offline. `brew search` takes seconds per
/// query; searching the decoded catalog in memory is instant.
struct CatalogService: Sendable {
    private static let maxAge: TimeInterval = 24 * 3600

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomebrewToolbox", isDirectory: true)
    }

    func load(forceRefresh: Bool = false) async throws -> [CatalogPackage] {
        async let formulaData = data(for: "formula", forceRefresh: forceRefresh)
        async let caskData = data(for: "cask", forceRefresh: forceRefresh)
        let (formulae, casks) = try await (formulaData, caskData)

        let decoder = JSONDecoder()
        let formulaPackages = try decoder.decode([FormulaEntry].self, from: formulae)
            .filter { !$0.disabled }
            .map(\.package)
        let caskPackages = try decoder.decode([CaskEntry].self, from: casks)
            .filter { !$0.disabled }
            .map(\.package)
        return formulaPackages + caskPackages
    }

    private func data(for kind: String, forceRefresh: Bool) async throws -> Data {
        let cacheURL = cacheDirectory.appendingPathComponent("\(kind).json")
        let modified = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let isFresh = modified.map { Date.now.timeIntervalSince($0) < Self.maxAge } ?? false

        if isFresh && !forceRefresh, let cached = try? Data(contentsOf: cacheURL) {
            return cached
        }
        do {
            let url = URL(string: "https://formulae.brew.sh/api/\(kind).json")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw BrewError(message: "formulae.brew.sh returned an unexpected response.")
            }
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            return data
        } catch {
            if let cached = try? Data(contentsOf: cacheURL) { return cached }
            throw error
        }
    }
}

extension [CatalogPackage] {
    /// Ranks exact name matches first, then name prefixes, then name and
    /// description matches.
    func search(_ query: String, limit: Int = 80) -> [CatalogPackage] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }

        var ranked: [(rank: Int, package: CatalogPackage)] = []
        for package in self {
            let name = package.name.lowercased()
            let title = package.title.lowercased()
            let rank: Int
            if name == query || title == query {
                rank = 0
            } else if name.hasPrefix(query) || title.hasPrefix(query) {
                rank = 1
            } else if name.contains(query) || title.contains(query) {
                rank = 2
            } else if package.summary?.localizedCaseInsensitiveContains(query) == true {
                rank = 3
            } else {
                continue
            }
            ranked.append((rank + (package.deprecated ? 4 : 0), package))
        }
        return ranked
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank
                    ? lhs.rank < rhs.rank
                    : lhs.package.name.count < rhs.package.name.count
            }
            .prefix(limit)
            .map(\.package)
    }
}

private struct FormulaEntry: Decodable {
    let name: String
    let tap: String?
    let desc: String?
    let license: String?
    let homepage: String?
    let versions: Versions
    let dependencies: [String]?
    let caveats: String?
    let deprecated: Bool?
    let disabledFlag: Bool?

    struct Versions: Decodable {
        let stable: String?
    }

    enum CodingKeys: String, CodingKey {
        case name, tap, desc, license, homepage, versions, dependencies, caveats, deprecated
        case disabledFlag = "disabled"
    }

    var disabled: Bool { disabledFlag ?? false }

    var package: CatalogPackage {
        CatalogPackage(
            name: name,
            title: name,
            kind: .formula,
            version: versions.stable ?? "?",
            summary: desc,
            homepage: homepage.flatMap(URL.init(string:)),
            license: license,
            dependencies: dependencies ?? [],
            caveats: caveats,
            tap: tap ?? "homebrew/core",
            deprecated: deprecated ?? false,
            autoUpdates: false
        )
    }
}

private struct CaskEntry: Decodable {
    let token: String
    let tap: String?
    let name: [String]?
    let desc: String?
    let homepage: String?
    let version: String?
    let caveats: String?
    let deprecated: Bool?
    let disabledFlag: Bool?
    let autoUpdates: Bool?

    enum CodingKeys: String, CodingKey {
        case token, tap, name, desc, homepage, version, caveats, deprecated
        case disabledFlag = "disabled"
        case autoUpdates = "auto_updates"
    }

    var disabled: Bool { disabledFlag ?? false }

    var package: CatalogPackage {
        CatalogPackage(
            name: token,
            title: name?.first ?? token,
            kind: .cask,
            version: version ?? "?",
            summary: desc,
            homepage: homepage.flatMap(URL.init(string:)),
            license: nil,
            dependencies: [],
            caveats: caveats,
            tap: tap ?? "homebrew/cask",
            deprecated: deprecated ?? false,
            autoUpdates: autoUpdates ?? false
        )
    }
}
