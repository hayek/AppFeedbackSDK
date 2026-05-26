# Getting Started

Build a ``FeedbackClient``, submit a ``FeedbackReport``, and the SDK does the rest.

## Overview

`AppFeedbackCore` is designed to drop into any Apple-platform app with three lines of setup and one async call to submit. There are no global singletons, no compile-time configuration steps, and no UI dependencies.

## Step 1 — Add the package

In your `Package.swift`:

```swift
.package(path: "../AppFeedbackSDK"),
// or, when published:
// .package(url: "https://github.com/hayek/AppFeedbackSDK", from: "0.2.0"),
```

Link `AppFeedbackCore` to your app target. The SwiftUI sheet lives in the separate `AppFeedbackUI` product — link that too if you want the drop-in form.

## Step 2 — Build a client

Construct a ``FeedbackClient`` once at app start and hold a reference. Device info is collected lazily on every submission, so a long-lived client always reports the *current* app version even after updates.

```swift
import AppFeedbackCore

@MainActor
let feedback = FeedbackClient(
    appName: "AcmeApp",
    transport: GitHubDirectTransport(
        owner: "acme-co",
        repo: "feedback",
        token: SecretLoader.gitHubToken
    )
)
```

The `appName` parameter overrides the auto-detected app name (otherwise the SDK reads `CFBundleDisplayName` / `CFBundleName` from your bundle).

## Step 3 — Submit a report

```swift
do {
    let issueNumber = try await feedback.submit(
        FeedbackReport(
            type: .bug,
            title: "Crash on launch",
            description: "Happens immediately after sign-in.",
            contactEmail: "user@example.com"
        )
    )
    print("Filed issue #\(issueNumber)")
} catch {
    // See ``FeedbackSubmissionError`` for the error cases the GitHub transport throws.
    print("Failed: \(error)")
}
```

That's it. The transport renders the body, applies labels, calls GitHub, and returns the issue number.

## Step 4 — Inject device info (optional)

If you want to override what ``DeviceInfo/current(appName:)`` collects — for example, to distinguish iPad from iPhone or to inject test data — build a ``DeviceInfo`` directly and pass it to the alternate ``FeedbackClient/init(transport:deviceInfo:)`` initializer:

```swift
let device = DeviceInfo(
    appName: "AcmeApp",
    appVersion: "1.2.3",
    buildNumber: "456",
    model: "iPad14,1",
    osName: "iPadOS",
    osVersion: "Version 18.2 (Build 22C150)"
)
let feedback = FeedbackClient(transport: transport, deviceInfo: device)
```

With this initializer the `deviceInfo` value is frozen for the lifetime of the client. Use it for tests, screenshots, or when you need full control of the metadata column.

## Next steps

- <doc:BodyFormat> — see exactly what gets written to the GitHub issue body.
- <doc:CustomTransports> — replace ``GitHubDirectTransport`` with a server-side relay.
- <doc:SecretsAndTokens> — how to handle the GitHub PAT honestly.
