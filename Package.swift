// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFeedbackSDK",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AppFeedbackCore", targets: ["AppFeedbackCore"]),
        .library(name: "AppFeedbackUI", targets: ["AppFeedbackUI"]),
    ],
    targets: [
        .target(name: "AppFeedbackCore"),
        .target(
            name: "AppFeedbackUI",
            dependencies: ["AppFeedbackCore"]
        ),
        .testTarget(
            name: "AppFeedbackCoreTests",
            dependencies: ["AppFeedbackCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AppFeedbackUITests",
            dependencies: ["AppFeedbackUI"]
        ),
    ]
)
