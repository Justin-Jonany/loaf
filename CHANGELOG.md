# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository scaffold, vault format specification, and theme system design.
- `FoolscapCore`: `CalendarDate` (timezone-naive), `Recurrence`, and `TaskLine`
  parsing for `due:`, `done:`, and `every:`, covered by 60 self-test checks.
- `NotePanel`: non-activating floating panel, plus a menu-bar item.
- `build.sh` assembles `dist/Foolscap.app` without Xcode.
- `Vault`: resolves the notes directory (`$FOOLSCAP_VAULT` → config → `~/Notes`), bootstraps
  it with the vault-side `CLAUDE.md` contract on first run, lists notes (ignoring dotfiles
  and `attachments/`), and writes atomically (temp file + `rename(2)`) with a self-write
  registry so the watcher can ignore its own echoes.
- `VaultWatcher`: `FSEvents`-based watcher that reports changed `.md` paths, filtered
  through the self-write registry.
- `MarkdownRenderer`: markdown → HTML via `swift-markdown` (new SPM dependency), with
  GFM task-list items special-cased into the `.task`/checkbox/`.due` markup `frosted.css`
  expects, driven by `TaskLine.urgency`.
- `Config`: hand-rolled reader for the documented subset of `~/.config/foolscap/config.toml`.
- The app now actually renders a note: on launch it loads config, bootstraps the vault,
  picks `todo.md` (or the first note alphabetically), renders it into the panel's `WKWebView`,
  and repaints on file changes via `VaultWatcher`. Added "Open Vault in Finder" to the menu.
- Self-test suite grown from 60 to 84 checks covering the above.

Nothing is released yet. See [ROADMAP.md](ROADMAP.md) for what v0.1 requires.
