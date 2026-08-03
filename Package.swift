// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuotaCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuotaCore", targets: ["QuotaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "QuotaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/QuotaCore"
        ),
        .testTarget(
            name: "QuotaCoreTests",
            dependencies: ["QuotaCore"],
            path: "Tests/QuotaCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
