// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Foolscap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "foolscap", targets: ["Foolscap"]),
        .executable(name: "foolscap-selftest", targets: ["FoolscapSelftest"]),
        .executable(name: "foolscap-routine-check", targets: ["FoolscapRoutineCheck"]),
        .library(name: "FoolscapCore", targets: ["FoolscapCore"]),
    ],
    dependencies: [
        // Renders vault markdown to HTML. SPM-native, builds with plain `swift build`
        // (no Xcode), so it doesn't add a toolchain requirement beyond what we already have.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        // No AppKit here — see CONTRIBUTING.md. This is what the self-test covers.
        .target(name: "FoolscapCore", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
        ]),
        .executableTarget(name: "Foolscap", dependencies: ["FoolscapCore"]),
        // Not a .testTarget: XCTest and swift-testing both ship only with Xcode,
        // so a test target would make Xcode a hard requirement for contributors.
        .executableTarget(name: "FoolscapSelftest", dependencies: ["FoolscapCore"]),
        // A tiny standalone linter, not part of the app: feeds a tasks.md file through the
        // real TaskBlock parser and reports any block missing @due. Used by
        // routines/morning-brief/dry_run.sh to prove the routine's output round-trips
        // through A1's parser (ROADMAP.md -> Epic C -> C1), and usable by hand against a
        // real vault too.
        .executableTarget(name: "FoolscapRoutineCheck", dependencies: ["FoolscapCore"]),
    ]
)
