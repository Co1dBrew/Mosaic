// swift-tools-version:5.9
import PackageDescription

// MosaicKit is the platform-agnostic core of 万象记 / Mosaic.
// It deliberately avoids SwiftData (@Model macro) and UIKit so it can be
// compiled and run with the macOS toolchain, while still being usable from the
// iOS app target. The iOS app adapts its SwiftData models into MosaicKit value
// types at the boundary.
//
// NOTE: The Command Line Tools toolchain ships neither XCTest nor Swift Testing,
// so the core test suite is an executable (`mosaic-checks`) using a tiny
// assertion harness. Run it with `swift run mosaic-checks`. It returns a
// non-zero exit code on failure, so it works as a CI gate. Equivalent XCTest
// coverage runs inside Xcode via the app's test target.
let package = Package(
    name: "MosaicKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MosaicKit", targets: ["MosaicKit"]),
        .executable(name: "mosaic-checks", targets: ["MosaicKitChecks"])
    ],
    targets: [
        .target(
            name: "MosaicKit",
            path: "Sources/MosaicKit"
        ),
        .executableTarget(
            name: "MosaicKitChecks",
            dependencies: ["MosaicKit"],
            path: "Sources/MosaicKitChecks",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
