APP := build/Brewbox.app

.PHONY: run app open install release snapshots icon clean

# Quick dev loop (no notifications / launch at login).
run:
	swift run

app:
	./scripts/bundle.sh

open: app
	open "$(APP)"

install: app
	rm -rf "/Applications/Brewbox.app" "/Applications/Homebrew Toolbox.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Brewbox.app"

# Universal, Developer ID-signed and notarized build/Brewbox.dmg for the website.
release:
	./scripts/release.sh

# Render the panel with sample data to build/snapshots/*.png for design review.
snapshots:
	swift build
	.build/debug/Brewbox --snapshot build/snapshots

# Redraw Support/AppIcon.icns (and AppIcon.png) from scripts/make-icon.swift.
icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
