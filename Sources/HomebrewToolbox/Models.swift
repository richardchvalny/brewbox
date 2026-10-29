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
