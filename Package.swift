// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RunOrRaise",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RunOrRaise", targets: ["RunOrRaiseApp"])
    ],
    targets: [
        .executableTarget(
            name: "RunOrRaiseApp",
            path: "Sources/RunOrRaiseApp",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "RunOrRaiseAppTests",
            dependencies: ["RunOrRaiseApp"],
            path: "Tests/RunOrRaiseAppTests"
        )
    ]
)
