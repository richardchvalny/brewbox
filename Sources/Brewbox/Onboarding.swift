import AppKit
import ServiceManagement
import SwiftUI

/// The welcome window shown on first launch, and again from the panel when
/// Homebrew is missing.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()

    /// Set by the app at startup so the window can be shown once launching finishes.
    var store: UpdateStore?
    private var window: NSWindow?

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: Preferences.Key.hasCompletedOnboarding)
    }

    func showIfNeeded() {
        guard !Self.hasCompleted else { return }
        show(startingAt: .welcome)
    }

    func show(startingAt step: OnboardingView.Step) {
        guard let store else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(initialStep: step) { [weak self] in self?.window?.close() }
            .environment(store)
        let hosting = NSHostingController(rootView: view)
        // The view has a fixed size; don't let the controller shrink the window to a minimum.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.setContentSize(OnboardingView.size)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Brewbox"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early counts too: the panel still offers Homebrew setup if needed.
        UserDefaults.standard.set(true, forKey: Preferences.Key.hasCompletedOnboarding)
        window = nil
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case features
        case homebrew
        case done
    }

    static let size = CGSize(width: 540, height: 470)

    @Environment(UpdateStore.self) private var store
    @State private var step: Step
    let onFinish: () -> Void

    init(initialStep: Step = .welcome, onFinish: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .features: FeaturesStep()
                case .homebrew: HomebrewStep()
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step != .welcome {
                Button("Back") { move(by: -1) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
            primaryButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            prominent("Get started") { move(by: 1) }
        case .features:
            prominent("Continue") { move(by: 1) }
        case .homebrew where store.brew == nil:
            Button("Skip for now") { move(by: 1) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        case .homebrew:
            prominent("Continue") { move(by: 1) }
        case .done:
            prominent("Start using Brewbox", action: onFinish)
        }
    }

    private func prominent(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }
}

/// The bundled app icon, or the bubbles mark when running without a bundle.
struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(nsImage: BubblesIcon.image(hasUpdates: true, size: size * 0.7))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AppIconImage(size: 128)
            StepHeader(
                title: "Welcome to Brewbox",
                subtitle: "Keep your Homebrew packages up to date, right from the menu bar."
            )
            Spacer()
        }
    }
}

private struct FeaturesStep: View {
    private let features: [(icon: String, title: String, detail: String)] = [
        ("arrow.triangle.2.circlepath", "Stay up to date",
         "Checks for updates on your schedule and can install them for you."),
        ("shippingbox", "See what's installed",
         "Browse your packages, then pin, update, or uninstall them."),
        ("magnifyingglass", "Discover new tools",
         "Search more than 15,000 formulae and apps and install them in a click."),
        ("sparkles", "Fix problems faster",
         "Copy any error as a ready-made prompt for an AI agent."),
    ]

    var body: some View {
        VStack(spacing: 26) {
            StepHeader(title: "Everything Homebrew, in one place", subtitle: "Here's what Brewbox does for you.")
            VStack(alignment: .leading, spacing: 18) {
                ForEach(features, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(feature.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: 380)
            Spacer(minLength: 0)
        }
    }
}

/// Checks for Homebrew and, when it's missing, offers the official ways to install it.
struct HomebrewStep: View {
    @Environment(UpdateStore.self) private var store
    @State private var copied = false
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 22) {
            if let brew = store.brew {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                StepHeader(
                    title: "Homebrew is ready",
                    subtitle: "\(store.brewVersion ?? "Homebrew") is installed at \(brew.brewURL.deletingLastPathComponent().deletingLastPathComponent().path)."
                )
                Spacer()
            } else {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
                StepHeader(
                    title: "Brewbox needs Homebrew",
                    subtitle: "Homebrew is the package manager Brewbox works with. Installing it takes a few minutes and asks for your Mac password."
                )
                installOptions
                waiting
                Spacer(minLength: 0)
            }
        }
        // Notices the moment the installer finishes, without a manual refresh.
        .task(id: store.brew == nil) {
            while store.brew == nil && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                store.locateBrew()
            }
        }
    }

    private var installOptions: some View {
        VStack(spacing: 10) {
            Button {
                do {
                    try HomebrewInstaller.installInTerminal()
                    launchError = nil
                } catch {
                    launchError = "Couldn't open Terminal. Copy the command and run it yourself."
                }
            } label: {
                Label("Install in Terminal", systemImage: "terminal")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            HStack(spacing: 16) {
                Link(destination: HomebrewInstaller.packageURL) {
                    Label("Download installer (.pkg)", systemImage: "arrow.down.circle")
                }
                Button {
                    HomebrewInstaller.copyCommand()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.link)
                Link("brew.sh", destination: HomebrewInstaller.websiteURL)
            }
            .font(.system(size: 12))

            if let launchError {
                Text(launchError)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var waiting: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Brewbox will continue as soon as Homebrew is installed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DoneStep: View {
    @AppStorage(Preferences.Key.notifications) private var notifications = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 22) {
            menuBarPreview
            StepHeader(
                title: "Find Brewbox in your menu bar",
                subtitle: "Click the bubbles anytime to see updates. A small dot means new versions are waiting."
            )
            VStack(spacing: 0) {
                toggleRow("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Divider().padding(.horizontal, 12)
                toggleRow("Notify me about new updates", isOn: $notifications)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
            .frame(maxWidth: 340)
            .disabled(!Preferences.isBundled)
            Spacer(minLength: 0)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// A sketch of the menu bar with the Brewbox icon highlighted.
    private var menuBarPreview: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            HStack(spacing: 3) {
                Image(nsImage: BubblesIcon.image(hasUpdates: true, size: 18))
                Text("3").font(.system(size: 13))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.18)))
            Text("9:41").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.06)))
        .padding(.top, 18)
    }
}
