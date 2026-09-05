// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LedgerTarget",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LedgerTargetCore", targets: ["LedgerTargetCore"]),
        .library(name: "LedgerTargetAppModel", targets: ["LedgerTargetAppModel"]),
        .library(
            name: "LedgerTargetPowerSync",
            targets: ["LedgerTargetPowerSync"]
        ),
        .library(
            name: "LedgerTargetMigrationCore",
            targets: ["LedgerTargetMigrationCore"]
        ),
        .library(
            name: "LedgerTargetTestSupport",
            targets: ["LedgerTargetTestSupport"]
        ),
        .library(
            name: "LedgerTargetComposition",
            targets: ["LedgerTargetComposition"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/powersync-ja/powersync-swift.git",
            exact: "1.16.1"
        ),
        .package(
            url: "https://github.com/powersync-ja/CSQLite.git",
            exact: "3.51.2",
            traits: ["Encryption"]
        )
    ],
    targets: [
        .target(
            name: "LedgerTargetCore",
            path: "LedgerTargetCore"
        ),
        .testTarget(
            name: "LedgerTargetCoreTests",
            dependencies: ["LedgerTargetCore"],
            path: "LedgerTargetCoreTests"
        ),
        .target(
            name: "LedgerTargetAppModel",
            dependencies: ["LedgerTargetCore"],
            path: "LedgerTargetAppModel"
        ),
        .testTarget(
            name: "LedgerTargetAppModelTests",
            dependencies: ["LedgerTargetCore", "LedgerTargetAppModel"],
            path: "LedgerTargetAppModelTests"
        ),
        .target(
            name: "LedgerTargetPowerSync",
            dependencies: [
                "LedgerTargetCore",
                .product(name: "PowerSync", package: "powersync-swift"),
                .product(name: "CSQLite", package: "CSQLite")
            ],
            path: "LedgerTargetPowerSync"
        ),
        .testTarget(
            name: "LedgerTargetPowerSyncTests",
            dependencies: [
                "LedgerTargetCore",
                "LedgerTargetPowerSync",
                .product(name: "PowerSync", package: "powersync-swift")
            ],
            path: "LedgerTargetPowerSyncTests"
        ),
        .target(
            name: "LedgerTargetMigrationCore",
            dependencies: ["LedgerTargetCore"],
            path: "LedgerTargetMigrationCore"
        ),
        .testTarget(
            name: "LedgerTargetMigrationCoreTests",
            dependencies: ["LedgerTargetCore", "LedgerTargetMigrationCore"],
            path: "LedgerTargetMigrationCoreTests"
        ),
        .target(
            name: "LedgerTargetTestSupport",
            dependencies: ["LedgerTargetCore"],
            path: "LedgerTargetTestSupport"
        ),
        .testTarget(
            name: "LedgerTargetTestSupportTests",
            dependencies: ["LedgerTargetCore", "LedgerTargetTestSupport"],
            path: "LedgerTargetTestSupportTests"
        ),
        .target(
            name: "LedgerTargetComposition",
            dependencies: ["LedgerTargetCore"],
            path: "LedgerTargetComposition"
        ),
        .testTarget(
            name: "LedgerTargetCompositionTests",
            dependencies: [
                "LedgerTargetCore",
                "LedgerTargetComposition",
                "LedgerTargetTestSupport"
            ],
            path: "LedgerTargetCompositionTests"
        )
    ]
)
