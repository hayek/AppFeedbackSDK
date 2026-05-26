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

## Topics

### Essentials

- ``FeedbackSheet``

### Customization

- <doc:Theming>
- <doc:Localization>
- ``FeedbackTheme``
