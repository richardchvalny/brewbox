import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateStore.self) private var store
    let onBack: () -> Void

    @AppStorage(Preferences.Key.checkFrequency) private var frequency = Preferences.defaultCheckFrequency
    @AppStorage(Preferences.Key.checkMinuteOfDay) private var minuteOfDay = Preferences.defaultCheckMinuteOfDay
    @AppStorage(Preferences.Key.autoUpdate) private var autoUpdate = false
    @AppStorage(Preferences.Key.includeCasks) private var includeCasks = true
    @AppStorage(Preferences.Key.greedy) private var greedy = false
    @AppStorage(Preferences.Key.notifications) private var notifications = true
    @AppStorage(Preferences.Key.showCountInMenuBar) private var showCountInMenuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// DatePicker works with dates; the schedule stores minutes after midnight.
    private var checkTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var nextRun: Date {
        UpdateSchedule(frequency: frequency, minuteOfDay: minuteOfDay)
            .nextRun(after: store.lastScheduledRun, anchor: store.scheduleAnchor)
    }

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
                Section {
                    Picker("Check", selection: $frequency) {
                        ForEach(CheckFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("At", selection: checkTime, displayedComponents: .hourAndMinute)
                    Toggle(isOn: $autoUpdate) {
                        Text("Install updates automatically")
                        Text("Skips pinned packages and ones you turn off in their details.")
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Next check \(nextRun.formatted(.relative(presentation: .named))), \(nextRun.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("Packages") {
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
                    about
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

    private var about: some View {
        HStack(spacing: 12) {
            Image(nsImage: BubblesIcon.image(hasUpdates: false, size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Brewbox \(AppInfo.version)")
                    .font(.system(size: 12, weight: .semibold))
                    .textSelection(.enabled)
                Text("Made by \(AppInfo.author)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let brewVersion = store.brewVersion {
                    Text(brewVersion)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Link(destination: AppInfo.repositoryURL) {
                Label("GitHub", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .help(AppInfo.repositoryURL.absoluteString)
        }
        .padding(.vertical, 2)
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
