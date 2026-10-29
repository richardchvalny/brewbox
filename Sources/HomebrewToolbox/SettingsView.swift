import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateStore.self) private var store
    let onBack: () -> Void

    @AppStorage(Preferences.Key.checkIntervalHours) private var checkIntervalHours = Preferences.defaultCheckIntervalHours
    @AppStorage(Preferences.Key.includeCasks) private var includeCasks = true
    @AppStorage(Preferences.Key.greedy) private var greedy = false
    @AppStorage(Preferences.Key.notifications) private var notifications = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let intervals = [1, 2, 4, 8, 12, 24]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                // Balances the Back button so the title stays centered.
                Label("Back", systemImage: "chevron.left").hidden()
            }
            .padding(12)
            Divider()

            Form {
                Picker("Check every", selection: $checkIntervalHours) {
                    ForEach(intervals, id: \.self) { hours in
                        Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                    }
                }

                Toggle("Include casks (apps)", isOn: $includeCasks)
                Toggle(isOn: $greedy) {
                    Text("Include self-updating casks")
                    Text("Casks with auto_updates or version :latest")
                }
                .disabled(!includeCasks)

                Toggle("Notify about new updates", isOn: $notifications)
                    .disabled(!Preferences.isBundled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!Preferences.isBundled)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }

                if !Preferences.isBundled {
                    Text("Notifications and launch at login need the bundled app (make app).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: includeCasks) { refresh() }
            .onChange(of: greedy) { refresh() }
        }
    }

    private func refresh() {
        Task { await store.check() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            store.errorMessage = "Couldn't change launch at login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
