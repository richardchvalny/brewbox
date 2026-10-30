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

/// Native-menu-like hover highlight for list rows.
struct RowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .padding(.horizontal, 6)
    }
}

extension View {
    func rowHover() -> some View { modifier(RowHover()) }
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
