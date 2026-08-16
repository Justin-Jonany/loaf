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

Nothing is released yet. See [ROADMAP.md](ROADMAP.md) for what v0.1 requires.
