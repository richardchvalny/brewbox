import AppKit
import SwiftUI
import UserNotifications

@main
struct HomebrewToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = UpdateStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(store)
        } label: {
            let count = store.updatableCount
            Image(systemName: count > 0 ? "shippingbox.fill" : "shippingbox")
            if count > 0 {
                Text("\(count)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when launched via `swift run` without an Info.plist.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
