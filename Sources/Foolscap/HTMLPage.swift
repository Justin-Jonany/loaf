import Foundation

/// Wraps rendered body HTML in the page shell, inlining the theme CSS. Shared by the
/// live app window and the `--dump-dashboard` CLI entry point (main.swift) used to
/// produce a standalone HTML fixture for the B1 screenshot proof.
enum HTMLPage {
    static func wrap(body: String, theme: String) -> String {
        let css = loadThemeCSS(named: theme) ?? loadThemeCSS(named: "frosted") ?? ""
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

    /// Only `frosted` ships fully styled this slice — `card`/`console` are a later slice
    /// (see ROADMAP) — so any other name falls back to it. CSS is inlined rather than
    /// linked: the theme lives next to the app bundle, not in the vault, so a `<link
    /// href>` relative to the `loadHTMLString` baseURL (the vault root) wouldn't resolve.
    private static func loadThemeCSS(named name: String) -> String? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("themes/\(name).css"))
        }
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        candidates.append(sourceDir.appendingPathComponent("../../Resources/themes/\(name).css").standardized)

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return try? String(contentsOf: candidate, encoding: .utf8)
        }
        return nil
    }
}
