# Releasing

Apple's SwiftPM distributes packages by **git tag** — there's no registry to
publish to. Consumers point at the repo and pin a version:

```swift
.package(url: "https://github.com/hayek/AppFeedbackSDK", from: "0.1.0"),
```

## Cut a release

```sh
# 1. Make sure tests pass:
swift test
# 2. Tag a semantic version (bare or v-prefixed both work) and push it:
git tag 0.1.0
git push origin 0.1.0
```

Pushing the tag triggers `.github/workflows/release.yml`, which re-verifies the
build on macOS and creates a GitHub Release with auto-generated notes. No secret
is required — it uses the workflow's built-in `GITHUB_TOKEN`.

## Swift Package Index

To list the package on [Swift Package Index](https://swiftpackageindex.com),
submit the repo URL once via their [add-a-package](https://swiftpackageindex.com/add-a-package)
form. SPI picks up new tags automatically thereafter.

## CocoaPods

Not currently published as a pod. SwiftPM is the supported channel; open an issue
if CocoaPods support would help you.
