import AppKit
import SwiftUI

extension View {
    /// Keeps the hosting window the size of this view.
    ///
    /// The MenuBarExtra panel grows when its content does, but it doesn't shrink back:
    /// going from a tall tab (Taps, Installed) to a short one (Updates) left the short
    /// content floating in the old, larger panel. This resizes the window to the content,
    /// keeping its top edge under the menu bar.
    func fitWindowToContent() -> some View {
        modifier(FitWindowToContent())
    }
}

private struct FitWindowToContent: ViewModifier {
    @State private var window: NSWindow?
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0 })
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                size = newSize
                fit()
            }
            .onChange(of: window) { fit() }
    }

    private func fit() {
        guard let window, size.width > 0, size.height > 0 else { return }
        let current = window.contentRect(forFrameRect: window.frame)
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
        let target = NSRect(
            x: current.minX,
            y: current.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(window.frameRect(forContentRect: target), display: true)
    }
}

/// Hands back the window a SwiftUI view ends up in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onWindow = onWindow
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            // Not during the view update that inserted us.
            DispatchQueue.main.async { [onWindow] in onWindow?(window) }
        }
    }
}
