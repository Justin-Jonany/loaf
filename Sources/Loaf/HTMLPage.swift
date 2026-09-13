import Foundation

/// Wraps rendered body HTML in the page shell, inlining the theme CSS. Shared by the
/// live app window and the `--dump-dashboard` CLI entry point (main.swift) used to
/// produce a standalone HTML fixture for the B1 screenshot proof.
enum HTMLPage {
    static func wrap(body: String, theme: String) -> String {
        let css = themeCSS(named: theme)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// The resolved stylesheet for `theme` — the exact CSS `wrap` inlines into `<style>`,
    /// with the same `frosted` fallback. Exposed so an in-place repaint (`NoteWindow.refresh`)
    /// can swap the live `<style>` to match a menu-picked theme without a full reload.
    static func themeCSS(named theme: String) -> String {
        loadThemeCSS(named: theme) ?? loadThemeCSS(named: "frosted") ?? ""
    }

    /// Every theme is `base.css` (structural rules, shared by all three) plus its own
    /// palette + signature extras — base first, so a theme's `:root` overrides base's
    /// fallback token values. Mirrors the old single-file loader's contract: `nil` only
    /// when `name`'s own file is missing, so `wrap`'s `?? loadThemeCSS(named: "frosted")`
    /// fallback still triggers exactly when it used to. A missing `base.css` means the
    /// theme alone renders, unstyled, rather than nothing at all.
    private static func loadThemeCSS(named name: String) -> String? {
        guard let theme = loadCSSFile(named: name) else { return nil }
        let base = loadCSSFile(named: "base") ?? ""
        return base + theme
    }

    /// CSS is inlined rather than linked: the theme lives next to the app bundle, not in
    /// the vault, so a `<link href>` relative to the `loadHTMLString` baseURL (the vault
    /// root) wouldn't resolve.
    private static func loadCSSFile(named name: String) -> String? {
        for directory in themeDirectoryCandidates() {
            let candidate = directory.appendingPathComponent("\(name).css")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }

    /// The selectable palette themes — every `Resources/themes/*.css` file except
    /// `base.css` (structural, shared by all themes, not itself a choice) — for the
    /// menu-bar theme picker (main.swift → `buildThemeMenu`). Enumerated rather than
    /// hardcoded so a new palette file shows up in the menu on its own. Uses the same
    /// bundle/dev-tree resource location `loadCSSFile` does, and stops at the first
    /// directory that actually has theme files, matching `loadCSSFile`'s first-match
    /// behavior.
    static func availableThemeNames() -> [String] {
        for directory in themeDirectoryCandidates() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            let names = entries
                .filter { $0.pathExtension.lowercased() == "css" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .filter { $0 != "base" }
                .sorted()
            if !names.isEmpty { return names }
        }
        return []
    }

    private static func themeDirectoryCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("themes"))
        }
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        candidates.append(sourceDir.appendingPathComponent("../../Resources/themes").standardized)
        return candidates
    }
}
