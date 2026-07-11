// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "mac-limits-tracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacLimitsTracker", targets: ["MacLimitsTracker"])
    ],
    targets: [
        .target(
            name: "MacLimitsTrackerCore",
            path: "Sources/MacLimitsTrackerCore"
        ),
        .executableTarget(
            name: "MacLimitsTracker",
            dependencies: ["MacLimitsTrackerCore"],
            path: "Sources/MacLimitsTracker"
        ),
        .executableTarget(
            name: "VerifyCli",
            dependencies: ["MacLimitsTrackerCore"],
            path: "Sources/VerifyCli"
        ),
        .testTarget(
            name: "MacLimitsTrackerTests",
            dependencies: ["MacLimitsTrackerCore"],
            path: "Tests/MacLimitsTrackerTests"
        )
    ]
)