// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexRouter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexRouterCore", targets: ["CodexRouterCore"]),
        .library(name: "CodexRouterDB", targets: ["CodexRouterDB"]),
        .executable(name: "CodexRouterApp", targets: ["CodexRouterApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "CodexRouterCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/CodexRouterCore"
        ),
        .target(
            name: "CodexRouterDB",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "CodexRouterCore",
            ],
            path: "Sources/CodexRouterDB"
        ),
        .executableTarget(
            name: "CodexRouterApp",
            dependencies: [
                "CodexRouterCore",
                "CodexRouterDB",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/CodexRouterApp"
        ),
        .testTarget(
            name: "CodexRouterCoreTests",
            dependencies: ["CodexRouterCore"],
            path: "Tests/CodexRouterCoreTests"
        ),
        .testTarget(
            name: "CodexRouterDBTests",
            dependencies: ["CodexRouterDB"],
            path: "Tests/CodexRouterDBTests"
        ),
        .testTarget(
            name: "CodexRouterAppTests",
            dependencies: ["CodexRouterApp"],
            path: "Tests/CodexRouterAppTests"
        ),
    ]
)
