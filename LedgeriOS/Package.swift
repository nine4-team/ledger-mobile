// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LedgerTarget",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LedgerTargetCore", targets: ["LedgerTargetCore"]),
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
