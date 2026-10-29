APP := build/Homebrew Toolbox.app

.PHONY: run app open install clean

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

clean:
	rm -rf .build build
