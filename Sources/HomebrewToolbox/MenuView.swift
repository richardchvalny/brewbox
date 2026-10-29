import SwiftUI

struct MenuView: View {
    @Environment(UpdateStore.self) private var store
    @State private var showingSettings = false
    @State private var tab = Tab.updates

    private enum Tab {
        case updates
        case installed
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsView { showingSettings = false }
            } else {
                mainContent
            }
        }
        .frame(width: 360)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = store.errorMessage {
                ErrorBanner(message: error) { store.errorMessage = nil }
                Divider()
            }
            Picker("View", selection: $tab) {
                Text(store.updatableCount > 0 ? "Updates (\(store.updatableCount))" : "Updates")
                    .tag(Tab.updates)
                Text("Installed").tag(Tab.installed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            switch tab {
            case .updates:
                packageList
            case .installed:
                InstalledListView()
            }
            if !store.log.isEmpty {
                Divider()
                OutputView()
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Homebrew").font(.headline)
                statusLine
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await store.check() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isChecking || store.brew == nil)
            .help("Check for updates")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let activity = store.activity {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(activity)
            }
        } else if let lastChecked = store.lastChecked {
            Text("Checked \(lastChecked.formatted(.relative(presentation: .named)))")
        } else {
            Text("Not checked yet")
        }
    }

    @ViewBuilder
    private var packageList: some View {
        if store.packages.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: store.lastChecked == nil ? "hourglass" : "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(store.lastChecked == nil ? Color.secondary : Color.green)
                Text(store.lastChecked == nil ? "Looking for updates…" : "Everything is up to date")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Updates available")
                        .font(.subheadline.weight(.semibold))
                    Text("\(store.updatableCount)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                    Spacer()
                    Button("Update All") { store.upgradeAll() }
                        .controlSize(.small)
                        .disabled(store.updatableCount == 0
                            || store.packages.allSatisfy { $0.pinned || store.upgrading.contains($0.id) })
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.packages) { package in
                            PackageRow(package: package)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let brew = store.brew {
                Text(brew.brewURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct PackageRow: View {
    @Environment(UpdateStore.self) private var store
    let package: OutdatedPackage

    var body: some View {
        HStack(spacing: 10) {
            PackageIcon(kind: package.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(package.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(displayVersion(package.installedVersion))
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(displayVersion(package.currentVersion))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if package.kind == .formula {
                Button(package.pinned ? "Unpin" : "Pin Current Version") {
                    store.togglePin(name: package.name, isPinned: package.pinned)
                }
            }
            Button("Copy Upgrade Command") {
                let flag = package.kind == .cask ? " --cask" : ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade\(flag) \(package.name)", forType: .string)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if package.pinned {
            Image(systemName: "pin.fill")
                .foregroundStyle(.secondary)
                .help("Pinned — brew won't upgrade it")
        } else if store.upgrading.contains(package.id) {
            ProgressView().controlSize(.small)
        } else {
            Button("Update") { store.upgrade(package) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

struct PackageIcon: View {
    let kind: PackageKind

    var body: some View {
        Image(systemName: kind == .cask ? "macwindow" : "terminal")
            .frame(width: 28, height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.yellow.opacity(0.1))
    }
}

private struct OutputView: View {
    @Environment(UpdateStore.self) private var store
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label("Output", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                Spacer()
                if isExpanded {
                    Button("Clear") { store.clearLog() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            if isExpanded {
                ScrollView {
                    Text(store.log)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .frame(height: 150)
                .padding(6)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
