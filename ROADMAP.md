# Roadmap

## 0.2.0: the app
- [x] Script `api` mode, SwiftUI window, Maintenance and Leftovers screens
- [x] Uninstall: remove an app and its leftovers together, with a checkbox per item (script and app)
- [x] Script: checkboxes per item inside each cleanup category (browser caches, user caches, dev caches)
- [x] App: the same per-item checkboxes for caches (Details under each category)
- [x] Remaining screens: plug-ins, services, packages, updates, Homebrew, Time Machine, network, settings
- [x] npx tools (`~/.npm/_npx`) as a separate developer cache: one line per tool (name, size, date), never remove a tool in use
- [x] Sign the app with a stable identity, so Full Disk Access survives rebuilds
- [x] Banner when Full Disk Access is missing
- [x] Faster leftover scan (was about 23 s, now about 3 s)
- [x] Build the app in CI, attach it to the release, update the READMEs

## 0.3.0
- [x] Trash monitoring (`sentinel`) through the app, which can hold Full Disk Access
- [x] Optional cleanup when the Time Machine disk is plugged in
- [x] Known limits listed in the README (beta versions in `updates`, column alignment)

## 0.4.0
- [x] Universal app (Apple silicon and Intel): build both architectures, merge with lipo
- [x] App screens for the remaining commands: lipo-app, Spotlight, Claude Code (conversations, cache), zsh history
- [x] Time Machine screen: exclusions (list, add, remove), analysis of the largest backed-up folders, differences between backups
- [x] Settings: add a protected item from the app (file picker)
- [x] Script tables: align columns with accented characters (remove this known limitation)

## 0.5.0
- [ ] Updates: a Homebrew app that updated itself is not reported as outdated (compare the app's own version with the available one)
- [ ] Claude Code: check the `~/.claude` layout with the installed version, then update the tested version
- [ ] App, Leftovers: scan automatically when the screen opens

## Later
- [ ] Real-world check: sentinel and tm-clean run by launchd through the app; downloaded zip opens after "Open Anyway"
