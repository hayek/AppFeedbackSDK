# ``AppFeedbackCore``

Submit feedback from any Apple platform to a GitHub repository in the exact body format the AppFeedback inbox parses.

## Overview

`AppFeedbackCore` is the headless half of the AppFeedback SDK. It packages four pieces:

- ``FeedbackClient`` — the entry point you build once and submit through.
- ``FeedbackTransport`` — the protocol that decides *where* feedback goes. Two implementations ship built in: ``GitHubDirectTransport`` POSTs straight to GitHub Issues, and ``RelayTransport`` POSTs to an adopter-operated relay (the recommended production path — no GitHub credential in the app binary).
- ``IssueBodyFormatter`` and ``IssueBodyParser`` — the two ends of the wire contract with the AppFeedback inbox app.
- ``DeviceInfo`` — per-platform device + app metadata that gets attached to every submission.

The companion library ``AppFeedbackUI`` provides a drop-in SwiftUI sheet on top of this core; you can use either independently.

### A submission in five lines

```swift
import AppFeedbackCore

let client = FeedbackClient(
    appName: "AcmeApp",
    transport: GitHubDirectTransport(owner: "acme", repo: "feedback", token: token)
)

let issueNumber = try await client.submit(
    FeedbackReport(type: .bug, title: "Crash on launch", description: "…")
)
```

The transport renders the report into a structured issue body, attaches device info, applies the conventional labels (`bug` / `feature-request`, plus `user-submitted`), and returns the created issue number.

### The wire contract

The body format that ``IssueBodyFormatter`` writes is the same shape that ``IssueBodyParser`` reads back. Both sides of the contract ship in this module so the SDK and the inbox can never silently drift apart. See <doc:BodyFormat> for the full spec.

### Cross-platform device info

``DeviceInfo/current(appName:)`` auto-detects:

| Platform | `model` | `osName` |
| --- | --- | --- |
| macOS | `sysctlbyname("hw.model")` → `"MacBookPro18,1"` | `"macOS"` |
| iOS / iPadOS | `utsname.machine` → `"iPhone15,2"` | `"iOS"` (override for iPad) |
| watchOS | `utsname.machine` | `"watchOS"` |
| tvOS | `utsname.machine` | `"tvOS"` |
| visionOS | `utsname.machine` | `"visionOS"` |

Construct your own ``DeviceInfo`` if you need to override any field.

## Topics

### Essentials

- <doc:GettingStarted>
- ``FeedbackClient``
- ``FeedbackReport``
- ``FeedbackType``

### Transports

- <doc:CustomTransports>
- <doc:SecretsAndTokens>
- ``FeedbackTransport``
- ``GitHubDirectTransport``
- ``RelayTransport``

### The wire contract

- <doc:BodyFormat>
- ``IssueBodyFormatter``
- ``IssueBodyParser``
- ``ParsedFeedbackBody``

### Device information

- ``DeviceInfo``

### Errors

- ``FeedbackSubmissionError``
