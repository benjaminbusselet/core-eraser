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

## Later
- [ ] Trash monitoring (`sentinel`) through the app, which can hold Full Disk Access
- [ ] Optional cleanup when the Time Machine disk is plugged in
- [ ] Known limits listed in the README (beta versions in `updates`, column alignment)
