# Roadmap

## 0.2.0: the app
- [x] Script `api` mode, SwiftUI window, Maintenance and Leftovers screens
- [x] Uninstall: remove an app and its leftovers together, with a checkbox per item (script and app)
- [x] Script: checkboxes per item inside each cleanup category (browser caches, user caches, dev caches)
- [x] App: the same per-item checkboxes for caches (Details under each category)
- [ ] Remaining screens: plug-ins, services, packages, updates, Homebrew, Time Machine, network, settings
- [ ] npx tools (`~/.npm/_npx`) as a separate developer cache: one line per tool (name, size, date), never remove a tool in use
- [x] Sign the app with a stable identity, so Full Disk Access survives rebuilds
- [ ] Banner when Full Disk Access is missing
- [ ] Faster leftover scan (still about 23 s)
- [ ] Build the app in CI, attach it to the release, update the READMEs

## Later
- [ ] Trash monitoring (`sentinel`) through the app, which can hold Full Disk Access
- [ ] Optional cleanup when the Time Machine disk is plugged in
- [ ] Known limits listed in the README (beta versions in `updates`, column alignment)
