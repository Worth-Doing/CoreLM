// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoreLM",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
    ],
    targets: [
        .executableTarget(
            name: "CoreLM",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/CoreLM",
            resources: [
                .copy("../../Resources")
            ]
        ),
    ]
)
