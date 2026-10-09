// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpaceStateKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        // Generic SpaceAPI client, meant to move into its own repository once stable.
        .library(name: "SpaceAPI", targets: ["SpaceAPI"]),
        // Extra rooms and states of Mainframe Oldenburg, specific to the SpaceState apps.
        .library(name: "MainframeStatus", targets: ["MainframeStatus"]),
        // Talks to the SpacePush service: device registration, and reading states with a direct fallback.
        .library(name: "SpacePushClient", targets: ["SpacePushClient"]),
    ],
    targets: [
        .target(name: "SpaceAPI"),
        .target(name: "MainframeStatus", dependencies: ["SpaceAPI"]),
        .target(name: "SpacePushClient", dependencies: ["SpaceAPI", "MainframeStatus"]),
        .testTarget(
            name: "SpaceAPITests",
            dependencies: ["SpaceAPI"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MainframeStatusTests",
            dependencies: ["MainframeStatus", "SpaceAPI"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SpacePushClientTests",
            dependencies: ["SpacePushClient", "SpaceAPI", "MainframeStatus"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
