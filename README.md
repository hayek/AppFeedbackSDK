# AppFeedbackSDK

[![CI](https://github.com/hayek/AppFeedbackSDK/actions/workflows/ci.yml/badge.svg)](https://github.com/hayek/AppFeedbackSDK/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A small Swift package that lets your app submit feedback (bugs / feature requests) to a GitHub repository in the exact body format the [AppFeedback](https://github.com/hayek/AppFeedback) inbox parses.

This is the **Apple** SDK and the reference implementation for the [AppFeedback family](https://hayek.github.io/appfeedback-docs/) — the [Android](https://github.com/hayek/appfeedback-android) and [Web](https://github.com/hayek/appfeedback-web) SDKs produce a byte-identical issue body, kept in lockstep by the [`appfeedback-spec`](https://github.com/hayek/appfeedback-spec) golden fixtures.

- **AppFeedbackCore** — headless: `FeedbackClient`, transports, body formatter, body parser, multi-platform device info.
- **AppFeedbackUI** — drop-in SwiftUI sheet (`FeedbackSheet`) with type selector, validation, success animation. Themeable accent + copy.

Platforms: iOS 17 · macOS 14 · watchOS 10 · tvOS 17 · visionOS 1.

📖 Docs: <https://hayek.github.io/appfeedback-docs/> · API reference: <https://hayek.github.io/appfeedback-docs/reference/swift/documentation/>

## Quick start

```swift
import AppFeedbackCore
import AppFeedbackUI

// 1. Build a client once at app start.
let feedback = FeedbackClient(
    appName: "Usage for Claude",
    transport: GitHubDirectTransport(
        owner: "hayek",
        repo: "FeedbackRepo",
        token: myStoredGitHubToken   // load from the Keychain — see "Secrets" below
    ),
    analytics: MyAnalytics()         // optional — see "Analytics" below
)

// 2. Present the sheet from any SwiftUI view.
.sheet(isPresented: $showFeedback) {
    FeedbackSheet(
        client: feedback,
        theme: .default,
        onSubmit: { issueNumber in
            Analytics.track("feedback.submitted", ["issue": issueNumber])
        },
        onError: { error in
            Analytics.track("feedback.failed", ["error": "\(error)"])
        }
    )
}
```

The sheet renders a hero header, bug/feature selector, validated form, success animation, and `Done` dismissal. All copy and accent colors come from `theme`.

### Analytics

`onSubmit` / `onError` tell you about a completed submission. They don't tell you
how many people opened the sheet and left, got blocked by validation, or were
asked to rate. Conform to `FeedbackAnalytics` for the whole funnel:

```swift
struct MyAnalytics: FeedbackAnalytics {
    func record(_ event: FeedbackEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}
```

`name` and `parameters` are the stable, vendor-shaped contract
(`feedback_submission_succeeded`, `["type": "bug", "issue_number": "123"]`), so
forwarding is one line. Configure the sink **once, on the client** — the sheet
reads it from there, so a single object receives both the submission lifecycle
and the UI funnel.

Events never carry user content: no titles, descriptions, email addresses,
attachment filenames, or bytes. `onSubmit` / `onError` / `onSubmitReport` are not
deprecated and still fire alongside events.

New cases arrive in minor releases, so forward `name`/`parameters` or always
write a `default:` — see the DocC article for the full vocabulary.

### App Store rating prompt

When a submission turns out to be unqualified praise, the sheet follows it with
the native App Store rating prompt, so a happy user can turn that praise into a
rating without leaving the app. It's on by default:

```swift
FeedbackSheet(
    client: feedback,
    requestsAppStoreReview: false   // opt out
)
```

The praise check runs entirely on-device through Apple Intelligence (Foundation
Models, iOS/macOS/visionOS 26+) — the text is never sent anywhere for it. On a
device without Apple Intelligence — older OS, ineligible hardware, the feature
switched off, or the model still downloading — the check is skipped and the flow
is exactly as it was before. No app ID or other configuration is needed.

The report is always submitted first and is never affected by the outcome, and
the bar is deliberately high: text that mixes praise with a bug, complaint,
question, or request does not qualify. The alert's copy and how often it appears
belong to the system, so it isn't part of `FeedbackTheme.Copy`, and the App Store
shows it at most a few times per user per year. The option is inert on watchOS
and tvOS, which have no rating prompt.

## Headless submission

Skip the sheet if you have your own UI:

```swift
let issueNumber = try await feedback.submit(
    FeedbackReport(
        type: .bug,
        title: "Crash on launch",
        description: "Steps to reproduce…",
        contactEmail: "user@example.com"     // optional
    )
)
```

## The body format (wire contract with the inbox)

`IssueBodyFormatter.format(report:deviceInfo:)` writes exactly:

```
<description>

---
**Device Information:**
App: <appName>
App Version: <version> (<build>)
Device: <model>
<osName> Version: <osVersion>

**Contact Email:**
<email>                 (only if provided)

---
👍 Votes: 0
```

Labels: `[type.rawValue, "user-submitted"]`. The AppFeedback inbox uses `AppFeedbackCore.IssueBodyParser` to read this back, so the two ends can never drift.

## Localizing the sheet

`FeedbackTheme.Copy` is plain `String` — pass pre-localized text from your own bundle so the SDK doesn't have to ship a strings table:

```swift
let copy = FeedbackTheme.Copy(
    headerTitle: String(localized: "feedback_header"),
    bugSubtitle: String(localized: "feedback_bug_subtitle"),
    // …
    validationPromptTemplate: String(localized: "feedback_validation_template") // contains "{fields}"
)
let theme = FeedbackTheme(
    bugAccent: Color("BugAccent"),
    featureAccent: Color("FeatureAccent"),
    copy: copy
)
```

## Secrets

`GitHubDirectTransport` takes a `token: String` and does not obfuscate it. Shipping a PAT inside an app binary is a known trade-off — anyone can extract it. Mitigations from weakest to strongest:

1. **Nothing.** Token is in plaintext. Fine for closed beta / internal tools.
2. **XOR-obfuscate at rest, decode at runtime.** Raises the bar slightly. Anyone determined still wins.
3. **Server-side relay.** Point the SDK at an endpoint you control; your server holds the PAT, rate-limits, verifies an optional CAPTCHA, and mirrors to GitHub. This is the only path that actually contains the blast radius.

The SDK ships a concrete `RelayTransport` for option 3 — wire-compatible with the same relays the AppFeedback Web and Android SDKs target:

```swift
let transport = RelayTransport(
    endpoint: URL(string: "https://your-relay.example.com/api/feedback")!
)
let feedback = FeedbackClient(appName: "AcmeApp", transport: transport)
```

Pass `captchaTokenProvider:` — an `async` closure — to forward a bot-mitigation token (e.g. Turnstile/hCaptcha) the relay requires. It's invoked **once per submission**, so mint a fresh token inside it: CAPTCHA tokens are single-use and expire in minutes, and the transport is built once at app start and held for the process lifetime, so a token captured at construction would be stale by submit time. No GitHub credential ever ships in the app binary.

## Adding the package to your project

### Local (during development)

If you have the SDK checked out alongside your app:

**XcodeGen `project.yml`:**
```yaml
packages:
  AppFeedbackSDK:
    path: ../AppFeedbackSDK
targets:
  YourApp:
    dependencies:
      - package: AppFeedbackSDK
        product: AppFeedbackCore
      - package: AppFeedbackSDK
        product: AppFeedbackUI
```

**Hand-managed Xcode project:** File → Add Package Dependencies → Add Local… → select the `AppFeedbackSDK` directory → choose `AppFeedbackCore` and (optionally) `AppFeedbackUI`, link both to your app target.

### Remote (Swift Package Manager)

```swift
.package(url: "https://github.com/hayek/AppFeedbackSDK", from: "0.1.0"),
```

## Migrating an existing in-tree implementation

If your app currently has its own `FeedbackService` + `FeedbackFormView` (like ClaudeUsage did), the migration is:

1. Add the package per the section above.
2. Delete `FeedbackService.swift`, `FeedbackModels.swift`, `DeviceInfo.swift` — `FeedbackClient`, `FeedbackType`, and `DeviceInfo.current()` replace them.
3. Delete `FeedbackFormView.swift` — `FeedbackSheet` replaces it. Map your existing localized strings into `FeedbackTheme.Copy`; map your existing accent colors into `bugAccent` / `featureAccent`.
4. Wherever you presented the form, present `FeedbackSheet(client: …)` instead. Move analytics calls from inside the form into a `FeedbackAnalytics` conformance passed to `FeedbackClient(analytics:)` — that covers the whole funnel, not just completed submissions. `onSubmit` / `onError` remain available for app-side control flow.

The body produced by the SDK is byte-for-byte the same shape as the legacy `FeedbackService.generateIssueBody` output, so existing inbox tooling and parsed issues are unaffected.

## Running the tests

```bash
DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer xcrun swift test
```

(`/usr/bin/swift` from Command Line Tools doesn't bundle XCTest.)

## Status

- **v0.1** ✓ — `AppFeedbackCore`: client, transport protocol, GitHub direct transport, formatter, parser, device info, errors.
- **v0.2** ✓ — `AppFeedbackUI`: themeable `FeedbackSheet`.
- **v0.3** ✓ — AppFeedback inbox consumes `AppFeedbackCore.IssueBodyParser` (single source of truth).
- **v1.0** — `RelayTransport` ✓ (relay-contract wire-compatible with the Web/Android SDKs). Attachments (screenshots, logs) ✓ — validated and preprocessed client-side, uploaded by `GitHubDirectTransport` (committed to a branch via the GitHub Contents API), and written into / parsed back out of the issue body's `attachments-v1` block. Remaining gap: `RelayTransport` does not yet forward attachments — relay-path uploads are tracked separately.

## License

MIT © Amir Hayek. See [LICENSE](./LICENSE).
