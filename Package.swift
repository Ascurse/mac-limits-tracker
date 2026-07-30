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
    dependencies: [
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.3"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.4")
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
            dependencies: [
                "MacLimitsTrackerCore",
                "ViewInspector",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/MacLimitsTrackerTests"
        )
    ]
)