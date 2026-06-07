# The Body Format

A fixed, structured shape for the GitHub issue body that the AppFeedback inbox can parse back into typed fields.

## Overview

When ``FeedbackClient/submit(_:)`` runs, it asks the active ``FeedbackTransport`` to deliver a ``FeedbackReport``. For ``GitHubDirectTransport``, that means a `POST /repos/{owner}/{repo}/issues` with a JSON payload whose `body` is rendered by ``IssueBodyFormatter``.

The body is a *wire contract* — it is the only way structured fields travel between the submitting app and the AppFeedback inbox. Any drift between the two halves silently loses columns in the inbox.

## The exact shape

For a report with description, contact email, and an `extraFields` entry of `"Branch": "release/1.4"`:

```text
<description>

---
**Device Information:**
App: AcmeApp
App Version: 1.2.3 (456)
Device: MacBookPro18,1
macOS Version: Version 14.5 (Build 23F79)

**Branch:**
release/1.4

**Contact Email:**
user@example.com

---
👍 Votes: 0
```

If `contactEmail` is `nil` or empty, the entire `**Contact Email:**` block is omitted. `extraFields` are emitted in alphabetical key order, each rendered as `**Key:**\nValue`. The trailing `👍 Votes: 0` line is preserved for compatibility with vote-counting tooling.

## OS labels per platform

The line above the email block uses the platform-specific label `osName Version:`. The parser regex `^(OS|macOS|iOS|iPadOS|watchOS|tvOS|visionOS|Android|Windows|Linux|Web|ChromeOS) Version:` recognises all of these:

- `macOS Version: …`
- `iOS Version: …`
- `iPadOS Version: …`
- `watchOS Version: …`
- `tvOS Version: …`
- `visionOS Version: …`
- `Android Version: …`
- `Windows Version: …`
- `Linux Version: …`
- `Web Version: …`
- `ChromeOS Version: …`

So whichever value you put in ``DeviceInfo/osName``, the inbox parses it correctly.

## Labels

``IssueBodyFormatter/labels(for:)`` returns the two label strings that get applied to the GitHub issue:

```swift
IssueBodyFormatter.labels(for: .bug)
// ["bug", "user-submitted"]

IssueBodyFormatter.labels(for: .featureRequest)
// ["feature-request", "user-submitted"]
```

These are also part of the contract: the inbox filters and groups by them.

## Parsing it back

``IssueBodyParser/parse(_:)`` is the inverse:

```swift
let body = IssueBodyFormatter.format(report: report, deviceInfo: info)
let parsed = IssueBodyParser.parse(body)

parsed.appName       // "AcmeApp"
parsed.appVersion    // "1.2.3 (456)"
parsed.device        // "MacBookPro18,1"
parsed.osVersion     // "Version 14.5 (Build 23F79)"
parsed.email         // "user@example.com"
parsed.description   // "<description>"
```

The roundtrip is verified by the SDK's test suite, so any change to the format gets caught at build time.

## Resilience

The parser accepts a few variations seen in hand-written bodies:

- Bold markers in any position (`**Contact Email:** foo@bar.com` on one line, or `**Contact Email:**\nfoo@bar.com` on two).
- `OS Version:` as a generic label (treated like `macOS Version:`).
- `Horizontal rule (---)` separators are stripped from the description.
- Lines outside the `**Device Information:**` block are treated as description content.

It does *not* parse arbitrary YAML, JSON, or HTML — keep submissions plain text and the contract holds.

## Topics

- ``IssueBodyFormatter``
- ``IssueBodyParser``
- ``ParsedFeedbackBody``
