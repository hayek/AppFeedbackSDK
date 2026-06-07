// swift-tools-version: 6.0
import PackageDescription
import class Foundation.ProcessInfo

// swift-docc-plugin is a build-tool plugin used only to generate the DocC API
// reference. A top-level package dependency is resolved into EVERY consumer's
// graph (SwiftPM doesn't prune the resolution closure), so gate it behind an env
// var — set APPFEEDBACK_BUILD_DOCS=1 in the docs-generation step — to keep it out
// of adopters' checkouts. The docs site's regen script
// (appfeedback-docs/scripts/regen-api-refs.sh) sets this when generating DocC.
let buildingDocs = ProcessInfo.processInfo.environment["APPFEEDBACK_BUILD_DOCS"] != nil
let doccPluginDependencies: [Package.Dependency] = buildingDocs
    ? [.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0")]
    : []

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
    dependencies: doccPluginDependencies,
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
