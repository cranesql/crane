// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "crane",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "Crane", targets: ["Crane"])
    ],
    traits: [
        .default(enabledTraits: ["Logging"]),
        .trait(name: "Logging"),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.2.0"),
    ],
    targets: [
        .target(
            name: "Crane",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log", condition: .when(traits: ["Logging"])),
            ]
        ),
        .testTarget(
            name: "CraneTests",
            dependencies: [
                .target(name: "Crane")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

if Context.environment["CRANE_ENABLE_BENCHMARKS"] != nil {
    package.platforms = [.macOS(.v13)]
    package.dependencies.append(
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.0.0")
    )
    package.targets.append(
        .executableTarget(
            name: "CraneBenchmarks",
            dependencies: [
                "Crane",
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: "Benchmarks/CraneBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    )
}
