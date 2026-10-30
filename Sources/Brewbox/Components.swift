import SwiftUI

/// Small borderless icon button with a soft hover circle, used in panel headers.
struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.primary.opacity(isHovered ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Native-menu-like hover highlight for list rows; `isHighlighted` marks the keyboard selection.
struct RowHover: ViewModifier {
    var isHighlighted = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .padding(.horizontal, 6)
    }
}

extension View {
    func rowHover(highlighted: Bool = false) -> some View { modifier(RowHover(isHighlighted: highlighted)) }

    /// Up and down arrows move `highlighted` through `ids`; Return activates it.
    func listKeyboardNavigation<ID: Hashable>(
        _ ids: [ID],
        highlighted: Binding<ID?>,
        onActivate: @escaping (ID) -> Void
    ) -> some View {
        modifier(ListKeyboardNavigation(ids: ids, highlighted: highlighted, onActivate: onActivate))
    }
}

private struct ListKeyboardNavigation<ID: Hashable>: ViewModifier {
    let ids: [ID]
    @Binding var highlighted: ID?
    let onActivate: (ID) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.downArrow) { move(by: 1) }
            .onKeyPress(.upArrow) { move(by: -1) }
            .onKeyPress(.return) {
                guard let highlighted, ids.contains(highlighted) else { return .ignored }
                onActivate(highlighted)
                return .handled
            }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !ids.isEmpty else { return .ignored }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + offset, 0), ids.count - 1) } ?? (offset > 0 ? 0 : ids.count - 1)
        highlighted = ids[next]
        return .handled
    }
}

/// Moves to the previous or next tab of the panel.
struct TabSwitcher: Sendable {
    var action: @MainActor @Sendable (Int) -> Void = { _ in }
}

private struct TabSwitcherKey: EnvironmentKey {
    static let defaultValue = TabSwitcher()
}

extension EnvironmentValues {
    var switchTab: TabSwitcher {
        get { self[TabSwitcherKey.self] }
        set { self[TabSwitcherKey.self] = newValue }
    }
}

extension View {
    /// Left and right arrows switch tabs; `when` lets a search field keep them while it has text.
    func tabSwitching(_ switcher: TabSwitcher, when enabled: @escaping () -> Bool = { true }) -> some View {
        onKeyPress(.leftArrow) {
            guard enabled() else { return .ignored }
            switcher.action(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard enabled() else { return .ignored }
            switcher.action(1)
            return .handled
        }
    }
}

/// Keeps the keyboard-highlighted row of a list in view.
struct ScrollToHighlight<ID: Hashable>: ViewModifier {
    let highlighted: ID?
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content.onChange(of: highlighted) { _, id in
            if let id { proxy.scrollTo(id) }
        }
    }
}

/// Tiny glyph telling formulae (command-line) from casks (apps).
struct KindGlyph: View {
    let kind: PackageKind

    var body: some View {
        Image(systemName: kind == .cask ? "macwindow" : "terminal")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .help(kind == .cask ? "App (cask)" : "Command-line tool (formula)")
    }
}

/// "2.103.3 → 2.104.0", with the new version emphasized.
struct VersionChange: View {
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: 4) {
            Text(displayVersion(from))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(displayVersion(to))
                .foregroundStyle(.primary)
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
    }
}

/// Quiet per-row update action; the panel keeps one prominent button ("Update all").
struct RowUpdateButton: View {
    let action: () -> Void

    var body: some View {
        Button("Update", action: action)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
    }
}
