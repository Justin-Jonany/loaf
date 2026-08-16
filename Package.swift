// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Foolscap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "foolscap", targets: ["Foolscap"]),
        .executable(name: "foolscap-selftest", targets: ["FoolscapSelftest"]),
        .library(name: "FoolscapCore", targets: ["FoolscapCore"]),
    ],
    targets: [
        // No AppKit here — see CONTRIBUTING.md. This is what the self-test covers.
        .target(name: "FoolscapCore"),
        .executableTarget(name: "Foolscap", dependencies: ["FoolscapCore"]),
        // Not a .testTarget: XCTest and swift-testing both ship only with Xcode,
        // so a test target would make Xcode a hard requirement for contributors.
        .executableTarget(name: "FoolscapSelftest", dependencies: ["FoolscapCore"]),
    ]
)
