import AppKit
import SwiftUI

/// Shown instead of quitting when macOS takes Brewbox's icon out of the menu bar
/// (it's turned off under Allow in the Menu Bar, or was ⌘-dragged out), since the
/// app has no other way to be reached.
@MainActor
final class MenuBarHiddenWindow: NSObject, NSWindowDelegate {
    static let shared = MenuBarHiddenWindow()

    private var window: NSWindow?

    /// System Settings → Menu Bar (still named Control Center in the URL).
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = MenuBarHiddenView(
            openSettings: { NSWorkspace.shared.open(Self.settingsURL) },
            quit: { AppDelegate.quit() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Brewbox is hidden"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct MenuBarHiddenView: View {
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            AppIconImage(size: 88)
            Text("Brewbox is hidden from the menu bar")
                .font(.system(size: 17, weight: .semibold))
            Text("""
                macOS isn't showing Brewbox's icon, and the menu bar is the only place to use it. \
                In System Settings → Menu Bar, turn on Brewbox under Allow in the Menu Bar.
                """)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Quit Brewbox", action: quit)
                    .buttonStyle(.bordered)
                Button("Open Menu Bar Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(.horizontal, 36)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
