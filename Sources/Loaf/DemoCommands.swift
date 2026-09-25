import Foundation
import LoafCore

/// Handles the non-GUI entry points (`--dump-dashboard`, `--demo-*`). Each one does its
/// work and exits, so this must run before AppKit is touched. Returns normally only when
/// no such flag was passed and the app should launch.
func runCommandLineToolIfRequested() {
    // The `--dump-dashboard <vault> <output.html>` entry point renders the composed
    // dashboard for `vault` to a standalone HTML file and exits — no GUI, no NSApplication
    // run loop. It exists so the B1 screenshot proof (and any future tooling) can produce
    // the exact HTML the app would show without driving the real window. Must run before
    // AppKit is touched below.
    if let flagIndex = CommandLine.arguments.firstIndex(of: "--dump-dashboard"),
       CommandLine.arguments.count > flagIndex + 2 {
        let vaultPath = CommandLine.arguments[flagIndex + 1]
        let outputPath = CommandLine.arguments[flagIndex + 2]
        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        // Matches `DashboardComposer.compose`'s own default (`.today()`, not the 6am-rollover
        // `.effectiveToday()` the real app uses) — this dump is a standalone snapshot tool, so
        // composing and rendering must agree on the same "today" the composer already used.
        let today = CalendarDate.today()
        let dashboard = DashboardComposer.compose(vault: vault, today: today)
        let body = DashboardRenderer.renderBody(dashboard, today: today)
        // Reads the real config's theme (same default path the app itself loads) rather than
        // the hardcoded default — now that the live app re-reads `theme` on every repaint
        // (live theme switching, DECISIONS.md 2026-09-11), this dump tool would otherwise
        // silently stop matching "the exact HTML the app would show" for a non-default theme.
        let html = HTMLPage.wrap(body: body, theme: Config.load().theme)
        do {
            try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
            exit(0)
        } catch {
            FileHandle.standardError.write("Loaf: couldn't write dashboard HTML: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    // The `--demo-conflict-guard <dir>` entry point is X1's non-GUI proof path (mirrors
    // `--dump-dashboard` above): screencapture has no display to run against in a headless
    // sandbox, so this drives the real guard logic against a real temp vault and leaves the
    // BEFORE/AFTER files on disk as evidence instead. No GUI, no NSApplication run loop — must
    // run before AppKit is touched below.
    if let flagIndex = CommandLine.arguments.firstIndex(of: "--demo-conflict-guard"),
       CommandLine.arguments.count > flagIndex + 1 {
        let demoDir = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1])
        do {
            try runConflictGuardDemo(in: demoDir)
            exit(0)
        } catch {
            FileHandle.standardError.write("Loaf: conflict-guard demo failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    // The `--demo-archive <dir>` entry point, the archive's non-GUI proof path (mirrors
    // `--demo-conflict-guard` above) — must run before AppKit is touched below.
    if let flagIndex = CommandLine.arguments.firstIndex(of: "--demo-archive"),
       CommandLine.arguments.count > flagIndex + 1 {
        let demoDir = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1])
        do {
            try runArchiveDemo(in: demoDir)
            exit(0)
        } catch {
            FileHandle.standardError.write("Loaf: archive demo failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    // The `--demo-signal <vault>` entry point, D2's non-GUI proof path (mirrors
    // `--demo-conflict-guard` above) — must run before AppKit is touched below.
    if let flagIndex = CommandLine.arguments.firstIndex(of: "--demo-signal"),
       CommandLine.arguments.count > flagIndex + 1 {
        let demoVaultPath = CommandLine.arguments[flagIndex + 1]
        do {
            try runSignalDemo(vaultPath: demoVaultPath)
            exit(0)
        } catch {
            FileHandle.standardError.write("Loaf: signal demo failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

/// The body of `--demo-conflict-guard`, factored out so it reads top-to-bottom as the demo
/// script it is. Seeds a vault, simulates the morning run rewriting `tasks.md` while the
/// app has an in-flight checkbox toggle based on the version it originally read, runs the
/// real X1 guard logic (`ConflictGuard`/`ConflictDecision` from `LoafCore`), and prints
/// + leaves the resulting BEFORE/AFTER files under `dir` for inspection.
func runConflictGuardDemo(in dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let vault = Vault(root: dir)
    let tasksURL = dir.appendingPathComponent("tasks.md")

    let original = "- [ ] Email the landlord\n      @today · manual"
    try vault.writeAtomically(original, to: tasksURL)
    print("--- BEFORE: tasks.md, as the app read it ---")
    print(original)

    // The app's read — a checkbox toggle would base its in-flight write on this snapshot.
    let readSnapshot = FileSnapshot.current(at: tasksURL)!

    // Before that write lands, the morning run rewrites the file concurrently. Written
    // directly (bypassing Vault), exactly as a real external process would — never lands
    // in the self-write registry.
    let externalRewrite = original + "\n- [ ] Prep the deck\n      @2026-08-21 · calendar"
    try externalRewrite.write(to: tasksURL, atomically: true, encoding: .utf8)
    print("\n--- CONCURRENT WRITE: the morning run rewrites tasks.md on disk ---")
    print(externalRewrite)

    // Meanwhile the app has its own unsaved change in flight: the user ticked "Email the
    // landlord" based on the version it originally read, above.
    let dirtyBuffer = TaskBlock.toggling(
        original.components(separatedBy: "\n"), at: 0, checked: true, today: .today()
    )!.joined(separator: "\n")
    print("\n--- APP'S DIRTY BUFFER: the pending (unsaved) checkbox toggle ---")
    print(dirtyBuffer)

    let diskChanged = ConflictGuard.hasExternalChange(at: tasksURL, since: readSnapshot, vault: vault)
    let decision = ConflictDecision.decide(diskChangedSinceRead: diskChanged, bufferDirty: true)
    print("\n--- GUARD DECISION: diskChangedSinceRead=\(diskChanged), bufferDirty=true -> \(decision) ---")

    guard decision == .conflictKeepDiskSaveCopy else {
        print("Unexpected decision for this demo — nothing written.")
        return
    }

    let conflictURL = ConflictCopy.url(for: tasksURL, timestamp: Date())
    try vault.writeAtomically(dirtyBuffer, to: conflictURL)
    print(
        "\n--- NOTICE the user would see ---\n"
            + "tasks.md changed before your edit saved. Something else (likely the morning run) "
            + "rewrote tasks.md while you had an unsaved change. The on-disk version was kept; "
            + "your change was saved separately as \(conflictURL.lastPathComponent) so nothing was lost."
    )

    print("\n--- AFTER: on-disk tasks.md (kept, never overwritten by the app's write) ---")
    print(try vault.read(tasksURL))
    print("\n--- AFTER: \(conflictURL.lastPathComponent) (the app's saved-aside change) ---")
    print(try vault.read(conflictURL))
    print("\nVault directory listing:")
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() {
        print("  \(name)")
    }
}

/// The body of `--demo-archive`, factored out so it reads top-to-bottom as the demo
/// script it is (mirrors `runConflictGuardDemo` above). Seeds a vault with one open and
/// one already-completed task, archives the completed one — exercising the same
/// archive-shard-first-then-strip write ORDER `archiveTask` uses in the real app
/// (DECISIONS.md 2026-09-11: a crash between the two writes must leave a recoverable
/// duplicate, never a loss) — then restores it back, the symmetric mirror. Also archives
/// the still-open task (DECISIONS.md 2026-09-11, widened: archiving is no longer gated
/// on done), proving that path lands in the shard with no `✓done` rather than a done
/// task's `✓done` surviving unchanged. Prints `tasks.md`/the archive shard at each step
/// so the two-file write and its ordering are inspectable without a GUI.
func runArchiveDemo(in dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let vault = Vault(root: dir)
    let tasksURL = dir.appendingPathComponent("tasks.md")

    let original = """
    - [ ] Email the landlord
          @today · manual
    - [x] Prep the client deck
          @2026-08-20 · calendar · !high · #schoolwork · ✓2026-08-20
    """
    try vault.writeAtomically(original, to: tasksURL)
    print("--- BEFORE: tasks.md ---")
    print(original)

    // The done task is the second block, starting at (0-based) line index 2.
    let archivedAt = Date()
    guard let (archivedBlockText, remainingLines) = TaskBlock.archiving(
        original.components(separatedBy: "\n"), at: 2, archivedAt: archivedAt
    ) else {
        print("Unexpected: line 2 isn't an archivable checkbox — nothing written.")
        return
    }

    let archiveURL = Archive.archiveShardURL(for: archivedAt, vault: vault)

    // STEP 1: the archive shard is written FIRST.
    try vault.writeAtomically(archivedBlockText, to: archiveURL)
    print("\n--- STEP 1: archive shard written first (\(archiveURL.lastPathComponent)) ---")
    print(try vault.read(archiveURL))

    // STEP 2: tasks.md is only stripped once step 1 has actually landed.
    try vault.writeAtomically(remainingLines.joined(separator: "\n"), to: tasksURL)
    print("\n--- STEP 2: tasks.md stripped of the archived block ---")
    print(try vault.read(tasksURL))

    // STEP 2b: archive the still-OPEN task too (DECISIONS.md 2026-09-11, widened —
    // archiving is no longer gated on done). Same shard-first-then-strip order as above;
    // the point of this step is what the archived block DOESN'T carry — no ✓done.
    guard let (openArchivedText, afterOpenArchive) = TaskBlock.archiving(
        remainingLines, at: 0, archivedAt: archivedAt
    ) else {
        print("Unexpected: the open task isn't an archivable checkbox — nothing written.")
        return
    }
    let shardWithBoth = try vault.read(archiveURL) + "\n" + openArchivedText
    try vault.writeAtomically(shardWithBoth, to: archiveURL)
    try vault.writeAtomically(afterOpenArchive.joined(separator: "\n"), to: tasksURL)
    print("\n--- STEP 2b: the still-open task archived too, with no ✓done ---")
    print(try vault.read(archiveURL))
    let openArchivedParsed = TaskBlock.parse(openArchivedText, today: .today())!
    print(
        "isDone: \(openArchivedParsed.isDone), done: \(String(describing: openArchivedParsed.done)), "
            + "archivedAt: \(String(describing: openArchivedParsed.archivedAt))"
    )

    // Restore: the symmetric mirror — append to tasks.md FIRST, strip the shard SECOND.
    let archiveLines = try vault.read(archiveURL).components(separatedBy: "\n")
    guard let (restoredBlockText, archiveRemaining) = TaskBlock.restoring(archiveLines, at: 0) else {
        print("Unexpected: the archived block didn't parse back — nothing restored.")
        return
    }

    let beforeRestore = try vault.read(tasksURL)
    let restoredTasks = beforeRestore.isEmpty ? restoredBlockText : beforeRestore + "\n" + restoredBlockText

    // STEP 3: tasks.md gets the restored, reopened block FIRST.
    try vault.writeAtomically(restoredTasks, to: tasksURL)
    print("\n--- STEP 3: restored block appended to tasks.md first ---")
    print(try vault.read(tasksURL))

    // STEP 4: the archive shard is only stripped once step 3 has actually landed.
    try vault.writeAtomically(archiveRemaining.joined(separator: "\n"), to: archiveURL)
    let afterRestoreShard = try vault.read(archiveURL)
    print("\n--- STEP 4: archive shard stripped of the restored block ---")
    print(afterRestoreShard.isEmpty ? "(empty — the shard held only that one block)" : afterRestoreShard)

    let restoredParsed = TaskBlock.parse(restoredBlockText, today: .today())!
    print("\n--- CHECK: the restored task is reopened, not just un-archived ---")
    print("isDone: \(restoredParsed.isDone), done: \(String(describing: restoredParsed.done)), archivedAt: \(String(describing: restoredParsed.archivedAt))")

    print("\nVault directory listing:")
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() {
        print("  \(name)")
    }
    print("archive/ directory listing:")
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("archive").path).sorted() {
        print("  \(name)")
    }
}

/// The body of `--demo-signal`, factored out so it reads top-to-bottom as the demo script
/// it is. Reads `.routine-signal.md` from `vaultPath` (if present at all) through the real
/// `RoutineSignal.parse`/`SignalNudge.decide` logic from `LoafCore` and prints which
/// nudge it would fire — title/body — without touching `UNUserNotificationCenter` or
/// AppKit. This is D2's non-GUI proof path (mirrors `--demo-conflict-guard` above): the
/// sandbox has no display to capture a real notification banner in.
func runSignalDemo(vaultPath: String) throws {
    let vault = Vault(root: URL(fileURLWithPath: vaultPath))
    let signalURL = vault.root.appendingPathComponent(routineSignalFileName)
    let text = (try? vault.read(signalURL)) ?? ""
    let signal = RoutineSignal.parse(text)
    let nudge = SignalNudge.decide(for: signal)

    print("--- \(signalURL.path) ---")
    print(text.isEmpty ? "(absent — no signal file)" : text)

    print("\n--- PARSED ---")
    if let signal {
        print("status: \(signal.status.rawValue), reason: \"\(signal.reason)\", questions: \(signal.questions)")
    } else {
        print("nil — clear day")
    }

    print("\n--- NUDGE ---")
    switch nudge {
    case .none:
        print("none — silent, no notification posted")
    case .decision(let reason, let questions):
        print("title: \(routineDecisionTitle)")
        print("body:  \(routineDecisionBody(reason: reason, questions: questions))")
    case .failure(let reason):
        print("title: \(routineFailureTitle)")
        print("body:  \(reason)")
    }
}
