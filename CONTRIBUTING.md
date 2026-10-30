# Contributing to Brewbox

Thanks for wanting to help. Bug reports, fixes and small improvements are very welcome.

## What Brewbox is (and isn't)

Brewbox is a small menu bar app that keeps Homebrew packages up to date and lets you
find, install and remove them. It should stay small, fast and dependency-free.

In scope:

- Bug fixes, crashes, wrong or confusing behavior
- Better handling of brew errors and edge cases
- Accessibility, keyboard support, localization
- Small quality-of-life improvements to existing features

Usually out of scope:

- Features that duplicate the Homebrew CLI wholesale (taps management, services,
  bundle files, …) or turn the panel into a full window app
- Third-party Swift packages or other new dependencies
- Telemetry, accounts, network calls to anything but Homebrew and GitHub
- Large refactors or style-only rewrites

Not sure? Open an issue first and ask.

## Before you open a pull request

- **New features need an issue first.** Describe the problem, not just the solution, and
  wait for a go-ahead. Feature PRs without an agreed issue may be closed without review.
- Keep each PR to one change. Small PRs get merged; big ones tend to stall.
- No new dependencies.
- Match the surrounding code: naming, comment style and SwiftUI idioms.
- Build and try it: `make run` for a quick check, `make open` for the bundled app.
  For UI changes, attach a screenshot (`make snapshots` renders the panel).
- Update the README when you change user-facing behavior.

## Merging

The maintainer reviews and merges every PR, squashed into a single commit. Saying no
to a well-made PR that doesn't fit the scope above isn't a judgment of the work.

By contributing, you agree that your contribution is licensed under the MIT License.
