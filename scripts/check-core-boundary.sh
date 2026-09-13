#!/usr/bin/env bash
# Fitness function for the hexagonal boundary: LoafCore is the domain core and must
# never depend on a UI adapter (AppKit/WebKit/etc). This is a denylist, not an allowlist,
# so legitimate imports (Foundation, CoreServices, Markdown, Dispatch, ...) don't trip it.
set -euo pipefail

CORE_DIR="Sources/LoafCore"
DENYLIST_PATTERN='^[[:space:]]*import[[:space:]]+(AppKit|Cocoa|UIKit|SwiftUI|WebKit)\b'

offenders=$(grep -rEln "$DENYLIST_PATTERN" "$CORE_DIR" --include='*.swift' || true)

if [ -n "$offenders" ]; then
    echo "Core-boundary violation: LoafCore must not import UI frameworks." >&2
    echo "$offenders" >&2
    exit 1
fi

echo "OK"
exit 0
