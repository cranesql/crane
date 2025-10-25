// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "crane",
    products: [
        .library(name: "Crane", targets: ["Crane"])
    ],
    targets: [
        .target(name: "Crane"),
        .testTarget(
            name: "CraneTests",
            dependencies: [
                .target(name: "Crane")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
