// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "hello-world-postgres-nio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "example", targets: ["Example"])
    ],
    dependencies: [
        .package(path: "../../"),
        .package(path: "../../../crane-postgres-nio"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Example",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crane", package: "crane"),
                .product(name: "CranePostgresNIO", package: "crane-postgres-nio"),
            ]
        )
    ]
)
