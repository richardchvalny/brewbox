import SwiftUI

/// Strip above the panel footer while a new Brewbox release is waiting.
struct AppUpdateBanner: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        if let release = updater.newRelease {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Brewbox \(release.version) is available")
                        .font(.system(size: 12, weight: .medium))
                    Link("What's new", destination: release.pageURL)
                        .font(.system(size: 11))
                }
                Spacer()
                AppUpdateButton()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// Update status and actions in Settings.
struct AppUpdateRow: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            switch updater.status {
            case .checking:
                ProgressView().controlSize(.small)
            case .available, .installing:
                AppUpdateButton()
            case .idle, .upToDate, .checkFailed:
                Button("Check now") {
                    Task { await updater.check(userInitiated: true) }
                }
            }
        }
    }

    private var title: String {
        switch updater.status {
        case .idle: "Brewbox updates"
        case .checking: "Checking for updates…"
        case .upToDate: "Brewbox is up to date"
        case .available(let release): "Brewbox \(release.version) is available"
        case .installing(let release): "Installing Brewbox \(release.version)…"
        case .checkFailed: "Couldn't check for updates"
        }
    }

    private var detail: String? {
        switch updater.status {
        case .checkFailed(let message):
            message
        case .installing:
            "Brewbox restarts when it's done."
        default:
            updater.lastChecked.map { "Checked \($0.formatted(.relative(presentation: .named)))" }
        }
    }
}

/// Installs the waiting release; waits while brew is busy, since quitting would cut it off.
private struct AppUpdateButton: View {
    @Environment(AppUpdater.self) private var updater
    @Environment(UpdateStore.self) private var store

    var body: some View {
        if updater.isInstalling {
            ProgressView().controlSize(.small)
        } else {
            Button("Update") { updater.install(reportingTo: store) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(store.activity != nil)
                .help(store.activity != nil ? "Available when Homebrew finishes" : "Download, install and restart Brewbox")
        }
    }
}
