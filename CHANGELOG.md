# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.5.0] - 2026-11-15

### Changed

- Actions needing administrator rights now run directly, after confirmation, through the macOS password or Touch ID prompt, instead of printing a command to paste: system caches and logs, DNS cache, Spotlight index, `/Library` plug-ins and services, package receipts, Time Machine exclusions and backups.
- App, Maintenance: system caches and logs are switches like the other tasks, instead of commands to copy.

### Added

- Test: every text of the app has an English translation.

### Fixed

- Mixed languages: plug-in types and system extension states are translated; the app shows sizes in the language chosen in the app (Ko, Mo, Go in French), not the Mac's.
- Plug-ins: a system extension is removed with administrator rights when System Integrity Protection is off; otherwise core-eraser shows "Protected by SIP". The System Settings path shown before no longer exists.
- Uninstall: a warning when the app has active system extensions, which macOS keeps after the app is deleted, with the app's own removal command when known (ProtonVPN: Clear Application Data).
- Uninstall: an app installed by a .pkg (owned by root) goes to the Trash with administrator rights, instead of failing with a wrong Full Disk Access message.
- Startup services: a service that is not loaded can be removed; stopping it no longer blocks the move to the Trash.

## [0.4.1] - 2026-11-15

### Changed

- Keyboard menu: after a task, back to the main menu; a new Quit entry leaves the script.

## [0.4.0] - 2026-11-14

### Added

- App: Spotlight, Strip the Intel part, Claude Code (conversations, caches) and terminal history screens.
- App: Time Machine tabs for exclusions (list, add, remove) and the largest folders still backed up; differences with the previous backup.
- App: add protected items from Settings with a file picker.

### Changed

- The app is universal (Apple silicon and Intel).

### Fixed

- Script tables stay aligned with accented characters.

## [0.3.0] - 2026-11-14

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
