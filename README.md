# core-eraser

**A leftover and cache eraser for macOS, in a single shell script.**
A lightweight, readable alternative to the cleaning parts of apps like Pearcleaner and OnyX.

[Version française](README.fr.md)

> Status: **0.4.1**, script and app (beta). Tested on macOS 27.2.1 (Apple Silicon). Use `--dry-run` first.

## What it does

| Category | Commands |
|---|---|
| Maintenance | `maintenance`: checkboxes (caches, logs, DNS, Spotlight, Time Machine), run all at once |
| Applications | `app-uninstall`, `orphans` (leftovers of deleted apps), `updates`, `brew-manage`, `plugins`, `services`, `pkg-manage`, `lipo-app` |
| Cleanup | `user-clean`, `dev-clean`, `system-clean` |
| Storage and backup | `timemachine` (status, exclusions, size of each backup, differences), `spotlight` |
| Network | `network` (diagnostics, DNS test, speed test) |
| Claude Code | `conv-list`, `conv --all`, `claude-cache`, `all` |
| Privacy | `zsh-history` |
| Settings | `exclude`, `sentinel on/off`, `tm-clean on/off`, `lang en/fr` |

Run `./core-eraser.sh -h` for the full list.

## Safety first

- **Trash, not delete**: files go to the Trash, so you can put them back. Only caches and logs, which apps recreate, are deleted directly.
- **Nothing without your choice**: every action lists what it will touch and asks for confirmation.
- **Never runs `sudo` itself**: actions that need administrator rights print the exact command for you to run, with paths safely quoted.
- **Protected items**: `./core-eraser.sh exclude add <path>` keeps a file or folder away from every command.
- **Dry run**: `./core-eraser.sh --dry-run <command>` shows what would happen and changes nothing.
- **Open apps**: when an app involved is open, core-eraser offers to quit it (like Cmd+Q).
- **Leftover detection** is based on what is really installed (bundle identifiers, extensions, shared groups declared in app signatures), not on fixed lists.

## Requirements

- macOS with the built-in `bash` 3.2. Nothing to install.
- Optional: [Homebrew](https://brew.sh) (`brew-manage`, `updates`, `dev-clean`), `jq` (`conv-list`).
- Some folders (`~/Library/Containers`, the Trash) may require **Full Disk Access** for Terminal: System Settings > Privacy & Security > Full Disk Access.

## Install

```sh
git clone https://github.com/benjaminbusselet/core-eraser.git
cd core-eraser
./core-eraser.sh            # keyboard menu
```

Optional shortcut in `~/.zshrc`: `alias eraser='/path/to/core-eraser/core-eraser.sh'`

### App (beta)

- Download `core-eraser-app.zip` from the [Releases](https://github.com/benjaminbusselet/core-eraser/releases) page and unzip it.
- The app is not notarized by Apple: on first launch, macOS blocks it. Allow it in System Settings > Privacy & Security > "Open Anyway".
- Give it **Full Disk Access** (the app shows a banner with a button when it is missing).
- Or build it yourself (requires Xcode): `./sign-setup.sh` once, then `./build-app.sh`. With the local certificate, Full Disk Access survives rebuilds.

## Usage

```sh
./core-eraser.sh                      # menu: arrows, Enter, q to go back
./core-eraser.sh orphans              # leftovers of deleted apps
./core-eraser.sh --dry-run user-clean # simulation
./core-eraser.sh lang fr              # French interface (English by default)
```

## Known limitations

- Commands needing `sudo` are printed, not run, so they are not tested automatically.
- `sentinel` (Trash monitoring) and `tm-clean` need Full Disk Access: turn them on from the app (Settings), which holds it. Turned on from Terminal, they run with bash, which usually lacks it.
- `tm-clean` runs when the disk is mounted, at the same time as the Time Machine backup: that first backup may still include the caches.
- `updates` compares versions only for Homebrew, Sparkle and App Store apps; beta versions may be reported as outdated.
- `lipo-app` replaces the app signature with a local one: automatic updates and permissions may be affected (a warning is shown).
- The Claude Code commands read the internal layout of `~/.claude`, checked with Claude Code 2.1.323. Another version may change it (a warning is shown).

## Tests

```sh
tests/run-tests.sh
```

Every test runs in a temporary home folder with fake apps and files: your Mac is never touched. The same tests run on GitHub (macOS runner) on every push.

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## License

[MIT](LICENSE). Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions. This project is not affiliated with Apple, Pearcleaner or OnyX.
