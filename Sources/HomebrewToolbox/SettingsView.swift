import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateStore.self) private var store
    let onBack: () -> Void

    @AppStorage(Preferences.Key.checkIntervalHours) private var checkIntervalHours = Preferences.defaultCheckIntervalHours
    @AppStorage(Preferences.Key.includeCasks) private var includeCasks = true
    @AppStorage(Preferences.Key.greedy) private var greedy = false
    @AppStorage(Preferences.Key.notifications) private var notifications = true
    @AppStorage(Preferences.Key.showCountInMenuBar) private var showCountInMenuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let intervals = [1, 2, 4, 8, 12, 24]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                IconButton(systemImage: "chevron.left", help: "Back", action: onBack)
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Form {
                Section("Updates") {
                    Picker("Check every", selection: $checkIntervalHours) {
                        ForEach(intervals, id: \.self) { hours in
                            Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                        }
                    }
                    Toggle("Include casks (apps)", isOn: $includeCasks)
                    Toggle(isOn: $greedy) {
                        Text("Include self-updating casks")
                        Text("Apps that update themselves or use version :latest")
                    }
                    .disabled(!includeCasks)
                }

                Section {
                    Toggle("Show update count", isOn: $showCountInMenuBar)
                    Toggle("Notify about new updates", isOn: $notifications)
                        .disabled(!Preferences.isBundled)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .disabled(!Preferences.isBundled)
                        .onChange(of: launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                } header: {
                    Text("Menu bar")
                } footer: {
                    if !Preferences.isBundled {
                        Text("Notifications and launch at login need the bundled app (make app).")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulate an error")
                            Text("Runs a brew command that fails on purpose, so you can try the error banner.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Run") {
                            store.simulateError()
                            onBack()
                        }
                    }
                } header: {
                    Text("Troubleshooting")
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .controlSize(.small)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
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
            store.error = ErrorReport(title: "Couldn't change launch at login", error: error)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
