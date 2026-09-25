import Foundation
import LoafCore

// A standalone linter, not part of the app. Feeds a tasks.md (or longterm.md) file
// through the real `TaskBlock` parser from `Sources/LoafCore/TaskBlock.swift` and
// reports every block found, flagging any that's missing the required `@due` token.
//
// This is what `routines/morning-brief/dry_run.sh` runs against the morning routine's
// output to prove it round-trips through the real task parser. It
// takes no dependency on the routine itself — it only knows the metadata-below format,
// same as the parser it's driving.
//
//     swift run loaf-routine-check <path/to/tasks.md> [more paths...]
//
// Exits 0 if every checkbox block parses and carries a valid @due; exits 1 (with a
// listing of the offending blocks) otherwise.

let paths = CommandLine.arguments.dropFirst()
guard !paths.isEmpty else {
    print("usage: loaf-routine-check <path/to/tasks.md> [more paths...]")
    exit(2)
}

var totalBlocks = 0
var invalidBlocks = 0

for path in paths {
    guard let contents = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
        print("\(path): could not read file")
        exit(2)
    }

    let lines = contents.components(separatedBy: "\n")
    var index = 0
    var blocksInFile = 0

    print("\(path):")
    while index < lines.count {
        guard let (block, consumed) = TaskBlock.parse(lines, at: index) else {
            index += 1
            continue
        }

        blocksInFile += 1
        totalBlocks += 1

        let status = block.isValid ? "ok" : "INVALID (missing @due)"
        let due = block.due.map(String.init(describing:)) ?? "—"
        print("  [\(status)] \(block.text)")
        print("      @due=\(due) · source=\(block.source.rawValue)" +
              (block.priority.map { " · !\($0.rawValue)" } ?? "") +
              (block.type.map { " · #\($0)" } ?? "") +
              (block.done.map { " · ✓\($0)" } ?? ""))

        if !block.isValid { invalidBlocks += 1 }
        index += consumed
    }

    if blocksInFile == 0 { print("  (no checkbox blocks found)") }
}

print("")
if invalidBlocks == 0 {
    print("PASS — \(totalBlocks) task block(s) parsed, all valid (@due present)")
    exit(0)
} else {
    print("FAIL — \(invalidBlocks) of \(totalBlocks) task block(s) missing @due")
    exit(1)
}
