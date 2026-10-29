import SwiftUI

struct InstalledListView: View {
    @Environment(UpdateStore.self) private var store
    @State private var searchText = ""
    @State private var kindFilter = KindFilter.all
    @AppStorage("showDependencies") private var showDependencies = false
    @State private var selected: CatalogPackage?

    init(initialSelection: CatalogPackage? = nil) {
        _selected = State(initialValue: initialSelection)
    }

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
        Group {
            if let selected {
                PackageDetailView(package: selected, backTitle: "Installed") { self.selected = nil }
            } else {
                VStack(spacing: 0) {
                    toolbar
                    content
                        .frame(height: 380)
                }
            }
        }
        .task {
            if store.installed.isEmpty {
                await store.loadInstalled()
            }
        }
        // Details read licenses, dependencies and caveats from the catalog.
        .task { await store.loadCatalog() }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search packages", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.06)))

            Menu {
                Picker("Show", selection: $kindFilter) {
                    ForEach(KindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Show dependencies", isOn: $showDependencies)
                Divider()
                Button("Reload list") { Task { await store.loadInstalled() } }
            } label: {
                Image(systemName: isFiltered
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isFiltered ? Color.accentColor : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filter")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var isFiltered: Bool {
        kindFilter != .all || showDependencies
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
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            Text("No packages match “\(searchText)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { package in
                        InstalledRow(package: package) {
                            selected = store.catalogPackage(for: package)
                        }
                    }
                    footnote
                }
            }
        }
    }

    private var footnote: some View {
        HStack(spacing: 4) {
            Text("\(filtered.count) of \(store.installed.count) packages")
            if hiddenDependencyCount > 0 {
                Text("·")
                Button(hiddenDependencyCount == 1 ? "Show 1 dependency" : "Show \(hiddenDependencyCount) dependencies") {
                    showDependencies = true
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.vertical, 12)
    }
}

private struct InstalledRow: View {
    @Environment(UpdateStore.self) private var store
    @Environment(\.openURL) private var openURL
    let package: InstalledPackage
    let onSelect: () -> Void

    private var outdated: OutdatedPackage? {
        store.outdatedPackage(id: package.id).flatMap { $0.pinned ? nil : $0 }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(package.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(package.installedOnRequest ? .primary : .secondary)
                        .lineLimit(1)
                    KindGlyph(kind: package.kind)
                    if package.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .help("Pinned")
                    }
                    if !package.installedOnRequest {
                        Text("dependency")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let outdated {
                    VersionChange(from: package.version, to: outdated.currentVersion)
                } else {
                    HStack(spacing: 6) {
                        Text(displayVersion(package.version))
                            .monospacedDigit()
                        if let summary = package.summary {
                            Text(summary)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if store.upgrading.contains(package.id) || store.uninstalling.contains(package.id) {
                ProgressView().controlSize(.small)
            } else if let outdated {
                RowUpdateButton { store.upgrade(outdated) }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .rowHover()
        .onTapGesture(perform: onSelect)
        .help(package.summary ?? package.name)
        .contextMenu {
            Button("Show details", action: onSelect)
            if let homepage = package.homepage {
                Button("Open homepage") { openURL(homepage) }
            }
            if package.kind == .formula {
                Button(package.pinned ? "Unpin" : "Pin current version") {
                    store.togglePin(name: package.name, isPinned: package.pinned)
                }
            }
            Button("Copy name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(package.name, forType: .string)
            }
        }
    }
}
