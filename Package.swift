// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kurrenchi",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Kurrenchi", targets: ["Kurrenchi"])
    ],
    targets: [
        .target(
            name: "KurrenchiShared",
            path: "Sources/KurrenchiShared",
            exclude: ["LICENSE-MIT.txt"]
        ),
        .executableTarget(
            name: "Kurrenchi",
            dependencies: ["KurrenchiShared"],
            path: "Sources/ChargePilot",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "KurrenchiHelper",
            dependencies: ["KurrenchiShared"],
            path: "Sources/KurrenchiHelper",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(name: "KurrenchiTests", dependencies: ["Kurrenchi", "KurrenchiShared"], path: "Tests/ChargePilotTests")
    ]
)
