# ``AppFeedbackUI``

A drop-in SwiftUI feedback sheet on top of ``AppFeedbackCore``.

## Overview

`AppFeedbackUI` ships a single, themeable view — ``FeedbackSheet`` — that handles the entire feedback flow: type selection, validated form, async submission, success animation, and dismissal. It runs on iOS, iPadOS, macOS, tvOS, watchOS, and visionOS with platform-appropriate styling.

If you don't want the bundled sheet — for instance, because you have your own form aesthetic — use ``AppFeedbackCore/FeedbackClient`` directly and skip this module entirely.

### Minimal integration

```swift
import AppFeedbackCore
import AppFeedbackUI

struct ContentView: View {
    let feedback: FeedbackClient
    @State private var showFeedback = false

    var body: some View {
        Button("Send Feedback") { showFeedback = true }
            .sheet(isPresented: $showFeedback) {
                FeedbackSheet(client: feedback)
            }
    }
}
```

The default theme uses red for bug reports, blue/purple for feature requests, and English copy. Both can be overridden per call — see <doc:Theming> and <doc:Localization>.

### What you get out of the box

- **Type selector** — radio-style cards for bug and feature request.
- **Validated fields** — title (required), description (required, character count up to a configurable limit), email (optional, soft-validated).
- **Privacy notice** — explicit "device information will be automatically included" line so users aren't surprised.
- **Async submission** — disables the button, shows a spinner, fires `onSubmit` or `onError` callbacks.
- **Success animation** — animated checkmark + the GitHub issue number, then dismiss via "Done".
- **Keyboard shortcuts** — ⌘↩ submits on macOS / iPadOS, default action key dismisses on success.
- **App Store rating prompt** — praise converts into a rating without leaving the app. See below.
- **Analytics** — the whole funnel, from sheet opened to rating prompt, through one optional sink. Configure it on the client via `FeedbackClient(analytics:)`; see the Analytics article in `AppFeedbackCore`.

### App Store rating prompt

When a submission turns out to be unqualified praise, the sheet follows it with the native App Store rating prompt. This is on by default; pass `requestsAppStoreReview: false` to ``FeedbackSheet/init(client:theme:descriptionLimit:extraFields:requestsAppStoreReview:onSubmit:onError:onSubmitReport:)`` to opt out.

The praise check runs entirely on-device through Apple Intelligence (Foundation Models, iOS/macOS/visionOS 26+) — the text is never sent anywhere for it, and no app ID or other configuration is required. On a device without Apple Intelligence — an older OS, ineligible hardware, the feature switched off, or the model still downloading — the check is skipped and the flow behaves exactly as it did before the option existed.

Three properties are worth relying on:

- **The report always goes out first.** The check runs after the transport has returned, so a slow, erroring, or absent model cannot affect or delay a submission.
- **The bar is pure praise.** Text mixing appreciation with a bug, complaint, criticism, question, or request does not qualify, and an uncertain verdict counts as not praise.
- **Silence is the failure mode.** A guardrail trip, a refusal, an unsupported language, or a timeout all mean "no prompt", never a broken submission.

The alert's copy and how often it appears belong to the system, so it is deliberately not part of ``FeedbackTheme/Copy``; the App Store shows it at most a few times per user per year. The option is inert on watchOS and tvOS, which have no rating prompt.

## Topics

### Essentials

- ``FeedbackSheet``

### Customization

- <doc:Theming>
- <doc:Localization>
- ``FeedbackTheme``
