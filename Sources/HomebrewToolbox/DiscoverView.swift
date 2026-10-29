import SwiftUI

/// Search the whole Homebrew catalog and open a package's detail to install it.
struct DiscoverView: View {
    @Environment(UpdateStore.self) private var store
    @State private var query: String
    @State private var results: [CatalogPackage] = []
    @State private var selected: CatalogPackage?
    @FocusState private var searchFocused: Bool

    private let suggestions = ["wget", "docker", "visual-studio-code", "ripgrep"]

    init(initialQuery: String = "", initialSelection: CatalogPackage? = nil) {
        _query = State(initialValue: initialQuery)
        _selected = State(initialValue: initialSelection)
    }

    var body: some View {
        Group {
            if let selected {
                PackageDetailView(package: selected) { self.selected = nil }
            } else {
                VStack(spacing: 0) {
                    searchField
                    content
                        .frame(height: 380)
                }
            }
        }
        .task {
            await store.loadCatalog()
            if store.installed.isEmpty {
                await store.loadInstalled()
            }
        }
        // Debounced so typing stays smooth over ~16k packages.
        .task(id: SearchKey(query: query, catalogSize: store.catalog.count)) {
            if !results.isEmpty || query.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            results = store.catalog.search(query)
        }
    }

    private struct SearchKey: Equatable {
        let query: String
        let catalogSize: Int
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search formulae and casks", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { selected = first }
                }
            if !query.isEmpty {
                Button {
                    query = ""
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        if store.catalog.isEmpty {
            VStack(spacing: 10) {
                if let error = store.catalogError {
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await store.loadCatalog() } }
                        .controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Loading the Homebrew catalog…")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyQuery
        } else if results.isEmpty {
            Text("No packages match “\(query)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { package in
                        DiscoverRow(package: package, isInstalled: store.installedIDs.contains(package.id)) {
                            selected = package
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var emptyQuery: some View {
        VStack(spacing: 8) {
            Image(nsImage: BubblesIcon.image(hasUpdates: false, size: 40))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("Find something new to brew")
                .font(.system(size: 13, weight: .medium))
            Text("Search \(store.catalog.count.formatted()) formulae and casks.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { query = suggestion }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.primary.opacity(0.06)))
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiscoverRow: View {
    let package: CatalogPackage
    let isInstalled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(package.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        KindGlyph(kind: package.kind)
                        if package.deprecated {
                            Text("deprecated")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }
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
                Spacer(minLength: 4)
                if isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .help("Installed")
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .rowHover()
        }
        .buttonStyle(.plain)
    }
}

struct PackageDetailView: View {
    @Environment(UpdateStore.self) private var store
    let package: CatalogPackage
    let onBack: () -> Void
    @State private var copied = false

    private var isInstalled: Bool { store.installedIDs.contains(package.id) }
    private var isInstalling: Bool { store.installing.contains(package.id) }
    private var installedVersion: String? {
        store.installed.first { $0.id == package.id }?.version
    }
    private var outdated: OutdatedPackage? {
        store.outdatedPackage(id: package.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(systemImage: "chevron.left", help: "Back to results", action: onBack)
                Text("Results")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if package.deprecated {
                        Label("Homebrew has deprecated this package.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    links
                    details
                    if let caveats = package.caveats {
                        section("Caveats") {
                            Text(caveats.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    commandBox
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(height: 326)

            Divider()
            actionBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(package.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(package.kind == .cask ? "App" : "Formula")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.primary.opacity(0.07)))
            }
            if package.title != package.name {
                Text(package.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if let summary = package.summary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var links: some View {
        HStack(spacing: 14) {
            if let homepage = package.homepage {
                Link(destination: homepage) {
                    Label(homepage.host() ?? "Homepage", systemImage: "globe")
                }
            }
            Link(destination: package.brewPageURL) {
                Label("formulae.brew.sh", systemImage: "arrow.up.right.square")
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Version", displayVersion(package.version))
            if let installedVersion {
                detailRow("Installed", displayVersion(installedVersion))
            }
            if let license = package.license {
                detailRow("License", license)
            }
            detailRow("Tap", package.tap)
            if package.kind == .cask && package.autoUpdates {
                detailRow("Updates", "Updates itself")
            }
            if package.kind == .formula {
                detailRow("Dependencies", package.dependencies.isEmpty
                    ? "None"
                    : package.dependencies.joined(separator: ", "))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.04)))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var commandBox: some View {
        HStack {
            Text(package.installCommand)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(package.installCommand, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy command")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.04)))
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            if isInstalling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.activity == "Installing \(package.title)…" ? "Installing…" : "Waiting for brew…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(lastLogLines)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isInstalled {
                HStack {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                    Spacer()
                    if let outdated, !outdated.pinned {
                        Button("Update to \(displayVersion(outdated.currentVersion))") { store.upgrade(outdated) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
            } else {
                Button {
                    store.install(package)
                } label: {
                    Text("Install")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var lastLogLines: String {
        store.log.split(separator: "\n").suffix(3).joined(separator: "\n")
    }
}
