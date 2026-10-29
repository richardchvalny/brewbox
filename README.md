# Homebrew Toolbox

A menu bar app for Homebrew in the spirit of JetBrains Toolbox: it checks for
outdated formulae and casks in the background and upgrades them with one click.

## Features

- Menu bar icon with the number of available updates
- Periodic `brew update` + `brew outdated` (interval configurable, 1–24 h)
- Per-package **Update** and **Update All**, queued so brew never runs twice at once
- Live `brew upgrade` output
- **Installed** tab: searchable list of everything installed, filter by formulae/casks,
  dependencies hidden by default, update straight from the list
- Pin / unpin formulae, open homepage (right-click a row)
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
| `SettingsView.swift` | In-panel settings |

## Known limitations

- Casks whose installer asks for an administrator password can't be upgraded from
  the app; the error tells you to run them in Terminal.
