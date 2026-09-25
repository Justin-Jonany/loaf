#!/usr/bin/env bash
# Regenerates the committed icon assets from the SVG sources in logo/:
#   logo/loaf-app.svg     -> Resources/AppIcon.icns       (Dock / Finder icon)
#   logo/loaf-menubar.svg -> Resources/MenuBarIcon{,@2x}.png (menu-bar template image)
#   logo/loaf-app.svg     -> logo/loaf-app.png             (README header; the gold tile
#                                                          reads on GitHub's light and dark themes)
# logo/loaf.svg is the plain line art both are drawn from.
# Run it after editing an SVG; build.sh only copies the results, so builds stay tool-free.
set -euo pipefail
cd "$(dirname "$0")/.."

render() { swift scripts/render-svg.swift "$1" "$2" "$3"; }

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    render logo/loaf-app.svg "$iconset/icon_${size}x${size}.png" "$size"
    render logo/loaf-app.svg "$iconset/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns

# 18pt is the standard menu-bar icon height.
render logo/loaf-menubar.svg Resources/MenuBarIcon.png 18
render logo/loaf-menubar.svg Resources/MenuBarIcon@2x.png 36

render logo/loaf-app.svg logo/loaf-app.png 256

echo "Icons regenerated."
