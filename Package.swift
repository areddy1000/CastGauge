// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CastGauge",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CastGaugeKit", targets: ["CastGaugeKit"]),
        .executable(name: "CastGauge", targets: ["CastGauge"]),
    ],
    targets: [
        .target(
            name: "CastGaugeKit",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
            ]
        ),
        .executableTarget(
            name: "CastGauge",
            dependencies: ["CastGaugeKit"]
        ),
        .testTarget(
            name: "CastGaugeKitTests",
            dependencies: ["CastGaugeKit"]
        ),
    ]
)
