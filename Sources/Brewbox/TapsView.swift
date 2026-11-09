import SwiftUI

/// Third-party taps: add one by name or URL, browse its packages, install them,
/// or remove the tap. Packages from taps also show up in Discover and Updates.
struct TapsView: View {
    @Environment(UpdateStore.self) private var store
    @Environment(\.switchTab) private var switchTab
    @State private var input = ""
    @State private var invalidInput = false
    @State private var selectedTap: String?
    @State private var selectedPackage: CatalogPackage?
    @State private var highlighted: String?
    @FocusState private var fieldFocused: Bool

    init(initialTap: String? = nil) {
        _selectedTap = State(initialValue: initialTap)
    }

    private var taps: [Tap] { store.taps ?? [] }

    var body: some View {
        Group {
            if let selectedPackage {
                PackageDetailView(package: selectedPackage, backTitle: selectedTap ?? "Taps") {
                    self.selectedPackage = nil
                }
            } else if let tap = taps.first(where: { $0.name == selectedTap }) {
                TapDetailView(tap: tap, onBack: { selectedTap = nil }) { selectedPackage = $0 }
            } else {
                VStack(spacing: 0) {
                    addField
                    content
                        .frame(height: 380)
                }
            }
        }
        .task {
            await store.loadTaps()
            if store.installed.isEmpty {
                await store.loadInstalled()
            }
        }
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("user/repo or a repository URL", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($fieldFocused)
                        .listKeyboardNavigation(taps.map(\.name), highlighted: $highlighted) { name in
                            selectedTap = name
                        }
                        .onSubmit(add)
                        .onChange(of: input) { invalidInput = false }
                        .tabSwitching(switchTab) { input.isEmpty }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.06)))
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if invalidInput {
                Text("Enter a tap as user/repo, or paste its repository URL.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // .task, so it runs after the previous tab gives up focus.
        .task { fieldFocused = true }
    }

    private func add() {
        if store.addTap(input) {
            input = ""
        } else {
            invalidInput = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.taps == nil {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading taps…")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if taps.isEmpty && store.changingTaps.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(taps) { tap in
                            TapRow(tap: tap, isHighlighted: highlighted == tap.name) {
                                selectedTap = tap.name
                            }
                            .id(tap.name)
                        }
                        ForEach(store.changingTaps.filter { name in !taps.contains { $0.name == name } }.sorted(), id: \.self) { name in
                            HStack(spacing: 8) {
                                Text(name)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                            .rowHover()
                        }
                    }
                    .padding(.bottom, 6)
                }
                .modifier(ScrollToHighlight(highlighted: highlighted, proxy: proxy))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "spigot")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("Add packages from other taps")
                .font(.system(size: 13, weight: .medium))
            Text("A tap is a repository of formulae and casks outside Homebrew's own. Once added, its packages show up in Discover and get updates like any other.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TapRow: View {
    let tap: Tap
    var isHighlighted = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tap.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(tapSummary(tap))
                            .foregroundStyle(.secondary)
                        if !tap.trusted {
                            Text("· Not trusted")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .rowHover(highlighted: isHighlighted)
        }
        .buttonStyle(.plain)
    }
}

/// "2 formulae · 1 cask", or a note for taps with nothing to install.
private func tapSummary(_ tap: Tap) -> String {
    var parts: [String] = []
    if !tap.formulaNames.isEmpty {
        parts.append(tap.formulaNames.count == 1 ? "1 formula" : "\(tap.formulaNames.count) formulae")
    }
    if !tap.caskTokens.isEmpty {
        parts.append(tap.caskTokens.count == 1 ? "1 cask" : "\(tap.caskTokens.count) casks")
    }
    return parts.isEmpty ? "No formulae or casks" : parts.joined(separator: " · ")
}

private struct TapDetailView: View {
    @Environment(UpdateStore.self) private var store
    let tap: Tap
    let onBack: () -> Void
    let onSelect: (CatalogPackage) -> Void
    @State private var confirmingRemove = false
    @State private var highlighted: String?
    @FocusState private var focused: Bool

    private var packages: [CatalogPackage] { store.packages(in: tap) }
    private var isChanging: Bool { store.changingTaps.contains(tap.name) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(systemImage: "chevron.left", help: "Back (Esc)", action: onBack)
                Text("Taps")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(tap.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(tapSummary(tap))
                        .foregroundStyle(.secondary)
                    if let url = tap.webURL {
                        Link(destination: url) {
                            Label(url.host() ?? "Repository", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                .font(.system(size: 11))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if !tap.trusted {
                trustBanner
            }

            Group {
                if packages.isEmpty {
                    Text(tap.packageCount == 0
                        ? "This repository has no formulae or casks, so there's nothing to install from it."
                        : "Loading packages…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(packages) { package in
                                    DiscoverRow(
                                        package: package,
                                        isInstalled: store.installedIDs.contains(package.id),
                                        isHighlighted: highlighted == package.id,
                                        showsTap: false
                                    ) {
                                        onSelect(package)
                                    }
                                    .id(package.id)
                                }
                            }
                            .padding(.bottom, 6)
                        }
                        .modifier(ScrollToHighlight(highlighted: highlighted, proxy: proxy))
                    }
                }
            }
            .frame(height: tap.trusted ? 288 : 224)

            Divider()
            actionBar
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .listKeyboardNavigation(packages.map(\.id), highlighted: $highlighted) { id in
            if let package = packages.first(where: { $0.id == id }) { onSelect(package) }
        }
        .onKeyPress(.escape) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onBack(); return .handled }
        .task { focused = true }
    }

    private var trustBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Homebrew doesn't trust this tap yet")
                    .font(.system(size: 12, weight: .semibold))
                Text("Until you trust it, Homebrew won't install or update its packages. Only trust taps from people you trust.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Trust") { store.trustTap(tap) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(isChanging)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.orange.opacity(0.1)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var actionBar: some View {
        Group {
            if isChanging {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tap.trusted ? "Removing…" : "Working…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if confirmingRemove {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove \(tap.name)?")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Its packages stop showing up and won't get updates. Uninstall them first; brew won't remove a tap that's in use.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") { confirmingRemove = false }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .keyboardShortcut(.cancelAction)
                        Button("Remove", role: .destructive) {
                            confirmingRemove = false
                            store.removeTap(tap)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("Remove tap") { confirmingRemove = true }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
