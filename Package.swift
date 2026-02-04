// swift-tools-version:6.2
import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "crane",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v16),
    ],
    products: [
        .library(name: "Crane", targets: ["Crane"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"5.0.0")
    ],
    targets: [
        .target(
            name: "Crane",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "CraneTests",
            dependencies: [
                .target(name: "Crane")
            ],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)

if Context.environment["CRANE_ENABLE_BENCHMARKS"] != nil {
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
