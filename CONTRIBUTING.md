# Contributing

## Getting set up

```bash
git clone https://github.com/Justin-Jonany/loaf
cd loaf
swift build
swift run loaf-selftest
```

If `swift build` fails with `this SDK is not supported by the compiler`, your Command
Line Tools are mismatched with your macOS SDK — see *Troubleshooting* in the README.

### Local safety hooks

GitHub Free doesn't offer branch protection on private repos, so `main` has no
server-side guard against a force-push or an accidentally-committed secret. Two local
hooks in `.githooks/` close most of that gap; opt in once per clone:

```bash
git config core.hooksPath .githooks
brew install gitleaks   # optional — pre-commit scan is skipped (with a warning) if absent
```

- `pre-push` refuses to force-push `main`
- `pre-commit` runs `gitleaks` over staged changes before they enter history

Both are advisory, not a real substitute for server-side protection — `--no-verify`
skips them, and they only run on machines where the hook path is configured. CI runs
the same `gitleaks` scan on every push/PR as a backstop.

## Where things go

| Path | Rule |
|---|---|
| `Sources/LoafCore/` | **No AppKit, no SwiftUI, no WebKit.** Pure logic, fully tested. |
| `Sources/Loaf/` | Everything that touches the screen. Kept thin. |
| `Resources/themes/` | One CSS file per theme. No Swift changes needed to add one. |

The split is the point: parsing, dates, and recurrence stay testable in CI without a
GUI session. If you find yourself importing AppKit into `LoafCore`, the logic
probably belongs in the app target instead.

`scripts/check-core-boundary.sh` enforces this: CI fails if `Sources/LoafCore/`
imports `AppKit`, `Cocoa`, `UIKit`, `SwiftUI`, or `WebKit`. Run it locally with
`bash scripts/check-core-boundary.sh`.

## Tests

`swift run loaf-selftest` runs the whole suite and exits non-zero on failure.

It is a plain executable, not a `.testTarget`. XCTest and swift-testing both ship
only with Xcode, and a `.testTarget` would make a 15GB Xcode install mandatory just
to check a date parser. `LoafCore` is pure logic with no fixtures or mocks, so
the harness in `Sources/LoafSelftest/main.swift` is about twenty lines — add
cases there with `expect(actual, expected, "what this proves")`.

Anything in `LoafCore` needs a case. Date handling especially — if you touch
recurrence, add one that crosses a DST boundary and one that crosses a year end.

## Themes

A theme is one CSS file and no Swift. It must:

- Style both a rendered preview and the source view
- Define `.due-soon` and `.due-over` (semantic colours, distinct from the accent)
- Respect `prefers-reduced-motion`
- Stay legible when macOS **Reduce Transparency** is on

## Commits and PRs

- One logical change per PR; keep diffs reviewable
- Explain *why* in the commit body, not *what* — the diff already says what
- **Every PR carries human-readable proof it works** — the `Verify` section is required, not
  optional. Attach evidence matched to the ticket type: a green `swift run loaf-selftest`
  run for pure logic, a **screenshot** for rendering, a short **screen-recording / GIF** for
  behavioral changes (writes, notifications, conflicts), a run transcript + vault `git diff`
  for the morning routine. A "works on my machine" claim without evidence is not enough.

### Before pushing

- [ ] `swift build` compiles clean
- [ ] `swift run loaf-selftest` passes (see *Tests* above)
- [ ] `bash scripts/check-core-boundary.sh` reports `OK`
- [ ] Code matches the surrounding style — comment *why*, not *what*; no unrequested
      refactors mixed into a functional change
- [ ] `ROADMAP.md` updated if you completed, changed, or dropped something on it
- [ ] `CHANGELOG.md` updated under `[Unreleased]` for anything user-visible
- [ ] `DECISIONS.md` given a new entry if this makes or reverses an architectural or
      product decision — see that file's own header for the format, and its
      "Supersedes" convention when a change reverses an earlier entry

## Scope

`ROADMAP.md` has an *Out of scope for 1.0* section. Those are settled decisions, not
oversights. If you want to reopen one, file an issue before writing code.
