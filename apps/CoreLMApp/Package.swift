// swift-tools-version: 5.9
import PackageDescription

let engineBuildDir = "../../engine/build"

let package = Package(
    name: "CoreLMApp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "CCoreLM",
            path: "Sources/CCoreLM",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(engineBuildDir)",
                    "-lcorelm",
                    "-lc++",
                ]),
                .linkedFramework("Accelerate"),
            ]
        ),
        .executableTarget(
            name: "CoreLMApp",
            dependencies: ["CCoreLM"],
            path: "Sources",
            exclude: ["CCoreLM"]
        )
    ]
)
