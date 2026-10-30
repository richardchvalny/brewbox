import AppKit
import SwiftUI
import UserNotifications

@main
struct BrewboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: UpdateStore

    init() {
        Snapshot.runIfRequested()
        // Before the store reads its settings.
        LegacyMigration.run()
        let store = UpdateStore()
        _store = State(initialValue: store)
        OnboardingWindow.shared.store = store
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let store: UpdateStore
    @AppStorage(Preferences.Key.showCountInMenuBar) private var showCount = true

    var body: some View {
        let count = store.updatableCount
        Image(nsImage: BubblesIcon.image(hasUpdates: count > 0, frame: store.iconFrame))
        if showCount && count > 0 {
            Text("\(count)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when launched via `swift run` without an Info.plist.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        OnboardingWindow.shared.showIfNeeded()
        guard Preferences.isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
