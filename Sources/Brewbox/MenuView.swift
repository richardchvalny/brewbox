import SwiftUI

struct MenuView: View {
    @Environment(UpdateStore.self) private var store
    @State private var showingSettings = false
    @State private var showingOutput = false
    @State private var tab: Tab
    private let discoverQuery: String
    private let discoverSelection: CatalogPackage?
    private let installedSelection: CatalogPackage?

    enum Tab {
        case updates
        case installed
        case discover
    }

    init(
        initialTab: Tab = .updates,
        discoverQuery: String = "",
        discoverSelection: CatalogPackage? = nil,
        installedSelection: CatalogPackage? = nil
    ) {
        _tab = State(initialValue: initialTab)
        self.discoverQuery = discoverQuery
        self.discoverSelection = discoverSelection
        self.installedSelection = installedSelection
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsView { showingSettings = false }
            } else {
                mainContent
            }
        }
        .frame(width: 340)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            if let error = store.error {
                ErrorBanner(report: error, systemInfo: store.systemInfo) { store.error = nil }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            tabBar
            Divider()
            switch tab {
            case .updates:
                UpdatesList()
            case .installed:
                InstalledListView(initialSelection: installedSelection)
            case .discover:
                DiscoverView(initialQuery: discoverQuery, initialSelection: discoverSelection)
            }
            if showingOutput && !store.log.isEmpty {
                Divider()
                OutputView()
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: BubblesIcon.image(hasUpdates: false, frame: store.iconFrame, size: 24))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Brewbox")
                    .font(.system(size: 13, weight: .semibold))
                statusLine
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            IconButton(systemImage: "arrow.clockwise", help: "Check for updates") {
                Task { await store.check() }
            }
            .disabled(store.isChecking || store.brew == nil)
            IconButton(systemImage: "gearshape", help: "Settings") {
                showingSettings = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let activity = store.activity {
            Text(activity)
        } else if let lastChecked = store.lastChecked {
            Text("Checked \(lastChecked.formatted(.relative(presentation: .named)))")
        } else {
            Text("Not checked yet")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            TabButton(title: "Updates", count: store.updatableCount, isSelected: tab == .updates) {
                tab = .updates
            }
            TabButton(title: "Installed", count: nil, isSelected: tab == .installed) {
                tab = .installed
            }
            TabButton(title: "Discover", count: nil, isSelected: tab == .discover) {
                tab = .discover
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            if !store.log.isEmpty {
                Button {
                    showingOutput.toggle()
                } label: {
                    Label(showingOutput ? "Hide output" : "Show output", systemImage: "terminal")
                }
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct TabButton: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(isSelected ? 0.08 : (isHovered ? 0.04 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct UpdatesList: View {
    @Environment(UpdateStore.self) private var store

    /// Pinned packages can't be upgraded, so they sit at the bottom.
    private var sortedPackages: [OutdatedPackage] {
        store.packages.filter { !$0.pinned } + store.packages.filter(\.pinned)
    }

    private var pinnedCount: Int { store.packages.count - store.updatableCount }

    var body: some View {
        if store.packages.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                summary
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedPackages) { package in
                            UpdateRow(package: package)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summary: some View {
        HStack {
            Text(summaryText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if store.updatableCount > 0 {
                Button("Update all") { store.upgradeAll() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(store.packages.allSatisfy { $0.pinned || store.upgrading.contains($0.id) })
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var summaryText: String {
        let updates = store.updatableCount == 1 ? "1 update" : "\(store.updatableCount) updates"
        return pinnedCount > 0 ? "\(updates) · \(pinnedCount) pinned" : updates
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(nsImage: BubblesIcon.image(hasUpdates: false, frame: store.iconFrame, size: 40))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(store.lastChecked == nil ? "Checking for updates…" : "You're up to date")
                .font(.system(size: 13, weight: .medium))
            if let lastChecked = store.lastChecked {
                Text("Checked \(lastChecked.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct UpdateRow: View {
    @Environment(UpdateStore.self) private var store
    let package: OutdatedPackage

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(package.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    KindGlyph(kind: package.kind)
                }
                VersionChange(from: package.installedVersion, to: package.currentVersion)
            }
            .opacity(package.pinned ? 0.55 : 1)
            Spacer()
            trailing
        }
        .rowHover()
        .contextMenu {
            if package.kind == .formula {
                Button(package.pinned ? "Unpin" : "Pin current version") {
                    store.togglePin(name: package.name, isPinned: package.pinned)
                }
            }
            Button("Copy upgrade command") {
                let flag = package.kind == .cask ? " --cask" : ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade\(flag) \(package.name)", forType: .string)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if package.pinned {
            Label("Pinned", systemImage: "pin.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help("Pinned, so brew won't upgrade it. Right-click to unpin.")
        } else if store.upgrading.contains(package.id) {
            ProgressView().controlSize(.small)
        } else {
            RowUpdateButton { store.upgrade(package) }
        }
    }
}

private struct ErrorBanner: View {
    let report: ErrorReport
    let systemInfo: SystemInfo
    let onDismiss: () -> Void
    @State private var copied: CopyKind?

    private enum CopyKind {
        case prompt
        case error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(report.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    if let hint = report.hint {
                        Text(hint)
                            .font(.system(size: 11))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            HStack(spacing: 6) {
                copyButton(.prompt, title: "Copy prompt for AI", systemImage: "sparkles") {
                    report.agentPrompt(environment: systemInfo)
                }
                .help("Copies the error with its command, output, and your setup, framed as a prompt for an AI agent")
                copyButton(.error, title: "Copy error", systemImage: "doc.on.doc") {
                    report.plainText(environment: systemInfo)
                }
            }
            .padding(.leading, 19)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.orange.opacity(0.1)))
    }

    private func copyButton(
        _ kind: CopyKind,
        title: String,
        systemImage: String,
        text: @escaping () -> String
    ) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text(), forType: .string)
            copied = kind
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copied == kind { copied = nil }
            }
        } label: {
            Label(copied == kind ? "Copied" : title, systemImage: copied == kind ? "checkmark" : systemImage)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

private struct OutputView: View {
    @Environment(UpdateStore.self) private var store

    var body: some View {
        ScrollView {
            Text(store.log)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 140)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05)))
        .overlay(alignment: .topTrailing) {
            Button("Clear") { store.clearLog() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .padding(12)
    }
}
