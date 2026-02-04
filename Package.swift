// swift-tools-version:6.2
import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "crane",
    products: [
        .library(name: "Crane", targets: ["Crane"])
    ],
    targets: [
        .target(
            name: "Crane",
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
