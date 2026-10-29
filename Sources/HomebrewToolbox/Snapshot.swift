import AppKit
import SwiftUI

/// `HomebrewToolbox --snapshot <dir>` renders the panel with sample data to PNGs,
/// so the design can be reviewed without clicking through the menu bar.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot") else { return }
        let directory = URL(fileURLWithPath: arguments.indices.contains(index + 1) ? arguments[index + 1] : ".")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        _ = NSApplication.shared
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(MenuView(initialTab: .updates), store: sampleStore(), appearance: appearance,
                   to: directory.appendingPathComponent("updates-\(name).png"))
            render(MenuView(initialTab: .installed), store: sampleStore(), appearance: appearance,
                   to: directory.appendingPathComponent("installed-\(name).png"))
            render(MenuView(initialTab: .updates), store: UpdateStore(preview: [], installed: sampleInstalled),
                   appearance: appearance, to: directory.appendingPathComponent("empty-\(name).png"))
            render(MenuBarIconStrip(), store: sampleStore(), appearance: appearance,
                   to: directory.appendingPathComponent("icon-\(name).png"))
        }
        exit(0)
    }

    private static func render(_ view: some View, store: UpdateStore, appearance: NSAppearance.Name, to url: URL) {
        // cacheDisplay skips the window background, and the panel is key while open.
        let content = view
            .environment(store)
            .environment(\.controlActiveState, .key)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let lazy stacks and .task modifiers settle.
        RunLoop.main.run(until: .now.addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func sampleStore() -> UpdateStore {
        UpdateStore(
            preview: [
                OutdatedPackage(name: "gh", kind: .formula, installedVersion: "2.103.3", currentVersion: "2.104.0", pinned: false),
                OutdatedPackage(name: "node", kind: .formula, installedVersion: "26.13.0", currentVersion: "26.14.1", pinned: true),
                OutdatedPackage(name: "raycast", kind: .cask, installedVersion: "2.10.1.0", currentVersion: "2.11.0", pinned: false),
                OutdatedPackage(name: "slack", kind: .cask, installedVersion: "4.53.269", currentVersion: "4.54.102", pinned: false),
            ],
            installed: sampleInstalled,
            log: "$ brew upgrade --formula gh\n==> Upgrading gh\n  2.103.3 -> 2.104.0\n==> Pouring gh--2.104.0.arm64_tahoe.bottle.tar.gz\n🍺  /opt/homebrew/Cellar/gh/2.104.0: 221 files, 58.1MB\n"
        )
    }

    private static let sampleInstalled: [InstalledPackage] = [
        .init(name: "claude-code", title: "Claude Code", kind: .cask, version: "2.1.308", summary: "Terminal-based AI coding assistant", homepage: nil, pinned: false, installedOnRequest: true),
        .init(name: "gh", title: "gh", kind: .formula, version: "2.103.3", summary: "GitHub command-line tool", homepage: nil, pinned: false, installedOnRequest: true),
        .init(name: "ghostty", title: "Ghostty", kind: .cask, version: "1.4.0", summary: "Terminal emulator that uses platform-native UI and GPU acceleration", homepage: nil, pinned: false, installedOnRequest: true),
        .init(name: "git", title: "git", kind: .formula, version: "2.56.0_2", summary: "Distributed revision control system", homepage: nil, pinned: false, installedOnRequest: true),
        .init(name: "libyaml", title: "libyaml", kind: .formula, version: "0.2.5", summary: "YAML Parser", homepage: nil, pinned: false, installedOnRequest: false),
        .init(name: "node", title: "node", kind: .formula, version: "26.13.0", summary: "Open-source, cross-platform JavaScript runtime environment", homepage: nil, pinned: true, installedOnRequest: true),
        .init(name: "orbstack", title: "OrbStack", kind: .cask, version: "2.2.5,21124", summary: "Replacement for Docker Desktop", homepage: nil, pinned: false, installedOnRequest: true),
        .init(name: "raycast", title: "Raycast", kind: .cask, version: "2.10.1.0", summary: "Control your tools with a few keystrokes", homepage: nil, pinned: false, installedOnRequest: true),
        .init(name: "slack", title: "Slack", kind: .cask, version: "4.53.269", summary: "Team communication and collaboration software", homepage: nil, pinned: false, installedOnRequest: true),
    ]
}

/// Menu bar icon states at real size and 4x: idle, with updates, and animation frames.
struct MenuBarIconStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Image(nsImage: BubblesIcon.image(hasUpdates: false))
                HStack(spacing: 3) {
                    Image(nsImage: BubblesIcon.image(hasUpdates: true))
                    Text("3").font(.system(size: 13))
                }
                ForEach([0, 4, 8, 12, 16, 20], id: \.self) { frame in
                    Image(nsImage: BubblesIcon.image(hasUpdates: false, frame: frame))
                }
            }
            HStack(spacing: 18) {
                Image(nsImage: BubblesIcon.image(hasUpdates: false, size: 72))
                Image(nsImage: BubblesIcon.image(hasUpdates: true, size: 72))
                Image(nsImage: BubblesIcon.image(hasUpdates: false, frame: 6, size: 72))
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
    }
}
