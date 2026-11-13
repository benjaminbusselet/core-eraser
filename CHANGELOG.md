# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `api` mode: tab-separated lists and direct actions without prompts, for the upcoming app.

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
