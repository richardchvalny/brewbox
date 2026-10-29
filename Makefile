APP := build/Homebrew Toolbox.app

.PHONY: run app open install snapshots clean

# Quick dev loop (no notifications / launch at login).
run:
	swift run

app:
	./scripts/bundle.sh

open: app
	open "$(APP)"

install: app
	rm -rf "/Applications/Homebrew Toolbox.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Homebrew Toolbox.app"

# Render the panel with sample data to build/snapshots/*.png for design review.
snapshots:
	swift build
	.build/debug/HomebrewToolbox --snapshot build/snapshots

clean:
	rm -rf .build build
