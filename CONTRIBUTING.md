# Contributing

## Getting set up

```bash
git clone https://github.com/Justin-Jonany/foolscap
cd foolscap
swift build
swift run foolscap-selftest
```

If `swift build` fails with `this SDK is not supported by the compiler`, your Command
Line Tools are mismatched with your macOS SDK — see *Troubleshooting* in the README.

## Where things go

| Path | Rule |
|---|---|
| `Sources/FoolscapCore/` | **No AppKit, no SwiftUI, no WebKit.** Pure logic, fully tested. |
| `Sources/Foolscap/` | Everything that touches the screen. Kept thin. |
| `Resources/themes/` | One CSS file per theme. No Swift changes needed to add one. |

The split is the point: parsing, dates, and recurrence stay testable in CI without a
GUI session. If you find yourself importing AppKit into `FoolscapCore`, the logic
probably belongs in the app target instead.

## Tests

`swift run foolscap-selftest` runs the whole suite and exits non-zero on failure.

It is a plain executable, not a `.testTarget`. XCTest and swift-testing both ship
only with Xcode, and a `.testTarget` would make a 15GB Xcode install mandatory just
to check a date parser. `FoolscapCore` is pure logic with no fixtures or mocks, so
the harness in `Sources/FoolscapSelftest/main.swift` is about twenty lines — add
cases there with `expect(actual, expected, "what this proves")`.

Anything in `FoolscapCore` needs a case. Date handling especially — if you touch
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
- Update `ROADMAP.md` if you complete something on it
- Update `CHANGELOG.md` under `[Unreleased]` for anything user-visible

## Scope

`ROADMAP.md` has an *Out of scope for 1.0* section. Those are settled decisions, not
oversights. If you want to reopen one, file an issue before writing code.
