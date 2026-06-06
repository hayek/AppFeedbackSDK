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
    dependencies: [
        // Build-tool plugin only: generates DocC API reference. Does not affect
        // library consumers or change the package's products.
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
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
