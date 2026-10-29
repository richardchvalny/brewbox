import SwiftUI

struct InstalledListView: View {
    @Environment(UpdateStore.self) private var store
    @State private var searchText = ""
    @State private var kindFilter = KindFilter.all
    @AppStorage("showDependencies") private var showDependencies = false

    private enum KindFilter: String, CaseIterable {
        case all = "All"
        case formulae = "Formulae"
        case casks = "Casks"
    }

    private var filtered: [InstalledPackage] {
        store.installed.filter { package in
            switch kindFilter {
            case .all: break
            case .formulae: guard package.kind == .formula else { return false }
            case .casks: guard package.kind == .cask else { return false }
            }
            guard showDependencies || package.installedOnRequest else { return false }
            guard !searchText.isEmpty else { return true }
            return package.title.localizedCaseInsensitiveContains(searchText)
                || package.name.localizedCaseInsensitiveContains(searchText)
                || (package.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var hiddenDependencyCount: Int {
        showDependencies ? 0 : store.installed.filter { !$0.installedOnRequest }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
                .frame(height: 360)
        }
        .task {
            if store.installed.isEmpty {
                await store.loadInstalled()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

            Menu {
                Picker("Show", selection: $kindFilter) {
                    ForEach(KindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Show Dependencies", isOn: $showDependencies)
                Divider()
                Button("Reload") { Task { await store.loadInstalled() } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filter")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.installed.isEmpty {
            VStack(spacing: 8) {
                if store.isLoadingInstalled {
                    ProgressView().controlSize(.small)
                    Text("Loading installed packages…")
                } else {
                    Text("No packages loaded")
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { package in
                        InstalledRow(package: package)
                    }
                    footnote
                }
            }
        }
    }

    private var footnote: some View {
        VStack(spacing: 2) {
            Text("\(filtered.count) of \(store.installed.count) packages")
            if hiddenDependencyCount > 0 {
                Button("Show \(hiddenDependencyCount) hidden dependencies") { showDependencies = true }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
    }
}

private struct InstalledRow: View {
    @Environment(UpdateStore.self) private var store
    @Environment(\.openURL) private var openURL
    let package: InstalledPackage

    var body: some View {
        HStack(spacing: 10) {
            PackageIcon(kind: package.kind)
                .opacity(package.installedOnRequest ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(displayVersion(package.version))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !package.installedOnRequest {
                        Text("dependency")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let summary = package.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help(package.summary ?? package.name)
        .contextMenu {
            if let homepage = package.homepage {
                Button("Open Homepage") { openURL(homepage) }
            }
            if package.kind == .formula {
                Button(package.pinned ? "Unpin" : "Pin Current Version") {
                    store.togglePin(name: package.name, isPinned: package.pinned)
                }
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(package.name, forType: .string)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if store.upgrading.contains(package.id) {
            ProgressView().controlSize(.small)
        } else if let outdated = store.outdatedPackage(for: package), !outdated.pinned {
            Button("Update to \(displayVersion(outdated.currentVersion))") { store.upgrade(outdated) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .lineLimit(1)
        } else if package.pinned {
            Image(systemName: "pin.fill")
                .foregroundStyle(.secondary)
                .help("Pinned — brew won't upgrade it")
        }
    }
}
