// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LedgerTarget",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LedgerTargetCore", targets: ["LedgerTargetCore"])
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
        )
    ]
)
