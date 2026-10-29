# Homebrew Toolbox

A menu bar app for Homebrew in the spirit of JetBrains Toolbox: it checks for
outdated formulae and casks in the background and upgrades them with one click.

## Features

- Subtle bubbles menu bar icon: a filled dot and count when updates are waiting,
  rising bubbles while brew works
- Periodic `brew update` + `brew outdated` (interval configurable, 1–24 h)
- Per-package **Update** and **Update All**, queued so brew never runs twice at once
- Live `brew upgrade` output
- **Installed** tab: searchable list of everything installed, filter by formulae/casks,
  dependencies hidden by default, update straight from the list; open a package
  for its details and to uninstall it (with confirmation)
- **Discover** tab: instant search over the whole Homebrew catalog (formulae and casks),
  package detail with homepage and formulae.brew.sh links, one-click install
- Pin / unpin formulae, open homepage (right-click a row)
- Errors show the failing command and can be copied as plain text or as a ready-made
  prompt for an AI agent (with full output and your macOS/Homebrew versions);
  Settings → Troubleshooting → Simulate an error lets you try it safely
- Notifications for new updates, launch at login
- Optional: include self-updating casks (`--greedy`)

## Requirements

- macOS 14+
- Swift 6 toolchain (Command Line Tools are enough, Xcode isn't needed)
- Homebrew in `/opt/homebrew` or `/usr/local`

## Usage

```bash
make run       # dev run straight from SwiftPM
make open      # build "build/Homebrew Toolbox.app" and open it
make install   # copy the app to /Applications and launch it
make snapshots # render the panel with sample data to build/snapshots/
```

Notifications and launch at login only work from the bundled app.

## Layout

| File | Role |
| --- | --- |
| `BrewService.swift` | Runs `brew` with a clean environment, streams output |
| `Models.swift` | Parses `brew outdated --json=v2` |
| `UpdateStore.swift` | State, scheduler, serial command queue, notifications |
| `MenuView.swift` | The menu bar panel and Updates tab |
| `InstalledListView.swift` | Installed tab with search and filters |
| `Catalog.swift` | Downloads and caches the formulae.brew.sh catalog, ranks search results |
| `DiscoverView.swift` | Discover tab, package detail and install |
| `ErrorReport.swift` | Error context and the copy-for-AI prompt |
| `SettingsView.swift` | In-panel settings |

## Known limitations

- Casks whose installer asks for an administrator password can't be upgraded from
  the app; the error tells you to run them in Terminal.
