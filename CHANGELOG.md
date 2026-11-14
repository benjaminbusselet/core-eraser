# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Trash monitoring (`sentinel`) turned on from the app runs through the app, which holds Full Disk Access; its alert opens the app.
- `tm-clean on|off` (and a switch in the app's Settings): empties closed-browser caches and logs when the Time Machine disk is plugged in, at most once every 20 h.

## [0.2.0] - 2026-11-14

### Added

- `api` mode: tab-separated lists and direct actions without prompts, for the upcoming app.
- App (work in progress): SwiftUI window with Maintenance and Leftovers screens, built by `build-app.sh` (requires Xcode).

- App: Uninstall screen, removing an app and its leftovers together, with a checkbox per item.
- Script: `app-uninstall`, `user-clean` and `dev-clean` let you check items one by one; long lists scroll.
- `sign-setup.sh`: creates a local signing certificate once, so the app keeps Full Disk Access after each rebuild.
- App: banner when Full Disk Access is missing, with a button to open the right System Settings pane.
- npx tools (`~/.npm/_npx`) in `dev-clean` and in the app: one line per tool (name, size, date); a tool in use is never removed.
- App: Plug-ins and extensions screen; system extensions and items outside your home folder show what to do yourself.
- App: Startup services, .pkg receipts, App updates, Homebrew, Time Machine, Network and Settings screens.
- CI builds the app; a `v*` tag attaches `core-eraser-app.zip` to the release. READMEs explain how to install it.

### Changed

- Faster search of app-related files and caches (one pass instead of one process per file).
- Faster leftover scan: about 3 s instead of 21 s (keys computed in one pass, installed apps read eight at a time).

### Fixed

- core-eraser's own files are never reported as leftovers.
- Accented text is handled when no system language is set (app, background service).
- English output no longer shows French words (.pkg states, Time Machine destination, network diagnostics, DNS test).

## [0.1.0] - 2026-11-13

### Added

- Keyboard menu with categories, and a **Maintenance** screen with checkboxes.
- Applications: `app-uninstall`, `orphans`, `updates`, `brew-manage`, `plugins`, `services`, `pkg-manage`, `lipo-app`.
- Cleanup: `user-clean`, `dev-clean`, `system-clean`.
- Storage and backup: `timemachine` (status, exclusions, analysis, size of each backup, differences), `spotlight`.
- Network: `network` (diagnostics, DNS test, speed test).
- Claude Code: `conv-list`, `conv --all`, `claude-cache`, `all`; privacy: `zsh-history`.
- Settings: exclusion list (`exclude`), Trash monitoring (`sentinel`), language (`lang`).
- English (default) and French interface.
- `--dry-run` simulation, Trash instead of deletion, offer to quit open apps.
- Test suite (`tests/run-tests.sh`) and GitHub Actions workflow.
