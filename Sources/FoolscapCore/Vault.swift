import Foundation

/// The markdown vault: a directory of notes on disk.
///
/// Every write goes through `writeAtomically` (temp file + `rename(2)`, never truncate
/// in place — see ROADMAP for the corruption hazard that guards against) and is recorded
/// in a self-write registry so `VaultWatcher` can tell the difference between a change we
/// just made and one the user (or another app) made, and skip repainting on our own echo.
public final class Vault {
    public let root: URL

    private let registryQueue = DispatchQueue(label: "dev.jonany.foolscap.vault.registry")
    private var selfWrites: [String: (mtime: Date, size: Int)] = [:]

    public init(root: URL) {
        self.root = root
    }

    public enum VaultError: Error {
        case templateNotFound
        case writeFailed(URL, errno: Int32)
    }

    // MARK: - Root resolution

    /// `$FOOLSCAP_VAULT` → config `vault` → `~/Notes`. Tilde is expanded in all three.
    public static func resolveRoot(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let envPath = environment["FOOLSCAP_VAULT"], !envPath.isEmpty {
            return expand(envPath)
        }
        if let configPath = config.vault, !configPath.isEmpty {
            return expand(configPath)
        }
        return expand("~/Notes")
    }

    private static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: - Bootstrap

    /// Creates the vault directory if missing, and seeds it with the vault-side `CLAUDE.md`
    /// contract if that file isn't already there. Safe to call on every launch: it never
    /// overwrites a `CLAUDE.md` the user has since edited.
    @discardableResult
    public func bootstrapIfEmpty() throws -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let claudePath = root.appendingPathComponent("CLAUDE.md")
        guard !fm.fileExists(atPath: claudePath.path) else { return false }

        let template = try Self.loadBundledTemplate()
        try writeAtomically(template, to: claudePath)
        return true
    }

    /// Locates the vault-side `templates/CLAUDE.md` contract, either from the app bundle's
    /// `Resources/templates` (packaged app, via `build.sh`) or, in dev, relative to the repo
    /// this source file lives in (`swift run`/`swift run foolscap-selftest` from the repo root).
    private static func loadBundledTemplate() throws -> String {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("templates/CLAUDE.md"))
        }
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        candidates.append(
            sourceDir.appendingPathComponent("../../templates/CLAUDE.md").standardized
        )

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        throw VaultError.templateNotFound
    }

    // MARK: - Listing

    /// All `*.md` notes under the vault root, recursing into subdirectories (e.g. `daily/`)
    /// but skipping dotfiles/dot-directories and `attachments/`, which holds images.
    public func notePaths() -> [URL] {
        var results: [URL] = []
        collectNotePaths(in: root, into: &results)
        return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func collectNotePaths(in directory: URL, into results: inout [URL]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        for entry in entries {
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { continue }

            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                guard name != "attachments" else { continue }
                collectNotePaths(in: entry, into: &results)
            } else if entry.pathExtension.lowercased() == "md" {
                results.append(entry)
            }
        }
    }

    // MARK: - Reading and writing

    public func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes via a temp file + `rename(2)` so a reader (or the watcher) never observes a
    /// half-written file, then records the resulting `(mtime, size)` so `wasSelfWrite`
    /// can recognise this exact write later.
    public func writeAtomically(_ content: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try content.write(to: tempURL, atomically: false, encoding: .utf8)

        let result = tempURL.path.withCString { tempPath in
            url.path.withCString { destPath in
                rename(tempPath, destPath)
            }
        }
        guard result == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: tempURL)
            throw VaultError.writeFailed(url, errno: code)
        }

        recordSelfWrite(at: url)
    }

    private func recordSelfWrite(at url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int
        else { return }
        registryQueue.sync {
            selfWrites[url.path] = (mtime, size)
        }
    }

    /// `true` if `path` currently on disk matches the `(mtime, size)` of a write we made
    /// ourselves. Consumes the registry entry either way, so a genuine external edit that
    /// happens to land at the same path afterwards is never mistaken for our own echo.
    public func wasSelfWrite(path: String) -> Bool {
        registryQueue.sync {
            guard let expected = selfWrites.removeValue(forKey: path) else { return false }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let mtime = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int
            else { return false }
            return mtime == expected.mtime && size == expected.size
        }
    }
}
