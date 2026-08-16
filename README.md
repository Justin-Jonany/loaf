# Foolscap

A note widget that floats on your macOS desktop, backed by plain markdown in a folder
you own — **with a storage format designed so a coding agent can edit your notes using
ordinary file tools.** No API, no plugin, no sync service.

> **Status: pre-release.** It builds, launches, and puts a floating panel and a
> menu-bar item on screen. It does not read your notes yet — the vault, the markdown
> renderer, and the date fields land in v0.1. See [ROADMAP.md](ROADMAP.md).

---

## Why this exists

Desktop sticky-note apps are a solved and crowded problem. This one is different in
exactly one way: **the file format is the API.**

Point Claude Code, or any agent that can read and write files, at `~/Notes` and it can
add a task, tick one off, restructure a page, or drop in a diagram. The widget watches
the folder and repaints. There is nothing to integrate — the integration is that both
sides agree to use markdown.

```
you  ──write──►  ~/Notes/todo.md  ◄──write──  Claude
                       │
                   FSEvents
                       ▼
                 the widget repaints
```

## The vault

```
~/Notes/
├── todo.md
├── thesis.md            # ```mermaid fences render in preview
├── daily/
│   └── 2026-08-12.md    # today, created on first write
├── attachments/
│   └── filtration.png
└── CLAUDE.md            # the format, documented for agents
```

`CLAUDE.md` is written into the vault on first run, so any future Claude session picks
up the conventions without being briefed.

## Dates

Dates are plain inline text, not frontmatter and not a database — greppable, typeable,
and still readable if this app disappears.

```markdown
- [ ] Ask about compactness   due:2026-08-12
- [ ] Send Mei the sketch     due:2026-08-10
- [ ] Water the plants        every:week
- [x] Re-read §3.2            done:2026-08-11
```

| Field | Accepts | Behaviour |
|---|---|---|
| `due:` | `2026-08-19`, `2026-08-19T14:00`, `friday`, `+3d` | Sorts the Today view; amber within 2 days, red once overdue |
| `done:` | `2026-08-11` | Written for you when you tick the box |
| `every:` | `day`, `week`, `2weeks`, `month`, `mon,thu` | On completion the line is rewritten with the next `due:` |

Write `due:friday` and it normalises to the ISO date on save, so both you and an agent
can be loose while the file stays canonical.

**Dates are date-only and timezone-naive.** A task due the 19th is due the 19th in
Melbourne and in Reykjavík. This is deliberate.

## Themes

The panel renders in a `WKWebView`, so a theme is one CSS file.

| Theme | Ground | Feels like |
|---|---|---|
| `frosted` *(default)* | Translucent, retints to the wallpaper | Part of the OS |
| `card` | Opaque paper, ruled lines, slight tilt | An object on your desk |
| `console` | Near-opaque dark, monospaced | Another pane of your editor |

Drop any `*.css` into `~/.config/foolscap/themes/` and it appears in the menu.
See [design/mockup.html](design/mockup.html) for all three rendered against three wallpapers.

## Configuration

Everything is optional. Copy [`config.example.toml`](config.example.toml) to
`~/.config/foolscap/config.toml` and change what you care about.

```toml
vault      = "~/Notes"
theme      = "frosted"
start_mode = "preview"
hotkey     = "cmd+shift+space"
```

`$FOOLSCAP_VAULT` overrides the vault path at launch.

## Building

Requires macOS 14+ and a working Swift toolchain.

```bash
git clone https://github.com/Justin-Jonany/foolscap
cd foolscap
./build.sh
cp -R dist/Foolscap.app ~/Applications/
```

Foolscap is an `LSUIElement` agent app: it lives in the menu bar, never in the Dock.

### Troubleshooting

**`error: this SDK is not supported by the compiler`** — your Command Line Tools
compiler and macOS SDK are from mismatched builds, which usually happens after a macOS
upgrade. Nothing Swift will compile, including `import Foundation`. Reinstall:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
sudo xcode-select --install
```

If it persists, install Xcode from the App Store and run
`sudo xcode-select -s /Applications/Xcode.app`.

**"Foolscap is damaged and can't be opened"** — Gatekeeper on an unsigned build:

```bash
xattr -d com.apple.quarantine ~/Applications/Foolscap.app
```

## Repository layout

```
Sources/FoolscapCore/    Vault, task lines, dates, recurrence — no AppKit import
Sources/Foolscap/        NSPanel, WKWebView, menu bar, config loading
Sources/FoolscapSelftest/ The logic suite — a plain executable, no Xcode needed
Resources/themes/        frosted.css, card.css, console.css
templates/CLAUDE.md      Written into a new vault on first run
design/mockup.html       The design, rendered
```

`FoolscapCore` deliberately imports no AppKit, so all parsing and date logic is
testable without a GUI session:

```bash
swift run foolscap-selftest     # exits non-zero on failure
```

This is a plain executable rather than a `.testTarget` on purpose: XCTest and
swift-testing both ship only with Xcode, and requiring a 15GB install to check a
date parser is a bad trade.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). [ROADMAP.md](ROADMAP.md) has a
*Good first issues* section that needs no architectural context.

## License

MIT — see [LICENSE](LICENSE).
