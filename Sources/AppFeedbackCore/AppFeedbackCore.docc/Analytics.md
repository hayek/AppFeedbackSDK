# Analytics

Observe the whole feedback funnel through one optional sink.

## Overview

`FeedbackSheet`'s `onSubmit` / `onError` callbacks report a completed
submission. They cannot tell you how many people opened the sheet and left, how
many were blocked by validation, or how many were asked to rate the app.

``FeedbackAnalytics`` is a single optional sink that receives all of it. Conform,
pass it to the client, and forward:

```swift
struct MyAnalytics: FeedbackAnalytics {
    func record(_ event: FeedbackEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}

let feedback = FeedbackClient(
    appName: "AcmeApp",
    transport: GitHubDirectTransport(owner: "acme", repo: "feedback", token: token),
    analytics: MyAnalytics()
)
```

That is the whole integration. ``FeedbackEvent/name`` and
``FeedbackEvent/parameters`` are already shaped for Firebase, Mixpanel,
Amplitude, PostHog, and TelemetryDeck — `[String: String]` converts implicitly to
`[String: Any]`.

Pass nothing and the SDK behaves exactly as it did before this API existed.

## Configure it once, on the client

There is deliberately **no** `analytics:` parameter on `FeedbackSheet`. The
sheet reads the sink from the client it was given, so one object receives the
submission lifecycle *and* the UI funnel.

A sheet-level parameter would let you configure a sink that silently never
receives ``FeedbackEvent/submissionStarted(_:attachmentCount:hasContactEmail:)``
or ``FeedbackEvent/submissionSucceeded(_:issueNumber:)`` — the exact questions
you added analytics to answer — with no compiler help.

Each event has exactly one emitter, so nothing is ever double-counted: the client
owns the submission lifecycle, the sheet owns everything else.

## The vocabulary

| Event | `name` | Parameters |
|---|---|---|
| ``FeedbackEvent/sheetPresented`` | `feedback_sheet_presented` | — |
| ``FeedbackEvent/typeSelected(_:)`` | `feedback_type_selected` | `type` |
| ``FeedbackEvent/attachmentAdded(source:)`` | `feedback_attachment_added` | `source` |
| ``FeedbackEvent/attachmentRejected(_:)`` | `feedback_attachment_rejected` | `reason` |
| ``FeedbackEvent/validationFailed(missingFields:)`` | `feedback_validation_failed` | `missing_fields` |
| ``FeedbackEvent/submissionStarted(_:attachmentCount:hasContactEmail:)`` | `feedback_submission_started` | `type`, `attachment_count`, `has_email` |
| ``FeedbackEvent/submissionSucceeded(_:issueNumber:)`` | `feedback_submission_succeeded` | `type`, `issue_number` |
| ``FeedbackEvent/submissionFailed(_:error:)`` | `feedback_submission_failed` | `type`, `error_kind` |
| ``FeedbackEvent/cancelled`` | `feedback_cancelled` | — |
| ``FeedbackEvent/ratingPromptRequested`` | `feedback_rating_prompt_requested` | — |
| ``FeedbackEvent/ratingPromptSuppressed(reason:)`` | `feedback_rating_prompt_suppressed` | `reason` |

A few of these are easy to misread:

- **``FeedbackEvent/cancelled``** means *left without a successful submission*.
  The sheet has no Cancel button — this covers swipe, Escape, and the host app
  dismissing it. An app terminated with the sheet open emits nothing.
- **``FeedbackEvent/typeSelected(_:)``** fires only when the type actually
  changes. The initial `.bug` default is not a selection, so read the submitted
  type from the submission events rather than inferring it here.
- **``FeedbackEvent/ratingPromptRequested``** means the SDK asked the system.
  Whether a prompt appeared is not observable — see below.
- **``FeedbackEvent/attachmentAdded(source:)``** fires per file, *before*
  validation. An oversized file emits this and then
  ``FeedbackEvent/attachmentRejected(_:)``, so it is not a count of accepted
  files. The rejection fires per *reason*, not per file.

Equality on ``FeedbackEvent`` is over `name`/`parameters`, so it is coarser than
the associated values: two failures of the same kind are equal even with
different underlying errors. Match the case if your test needs the carried
`Error` itself.

## What you cannot know

There is no `userRated` event, and no `ratingPromptShown`.

`RequestReviewAction` returns `Void`. It has no completion handler and no result.
The system decides on its own whether to show anything — it rate-limits to a few
prompts per user per year and stays silent otherwise — and Apple exposes no API
for whether the alert appeared or whether the person rated. Shipping either event
would mean shipping something that can never fire correctly.

``FeedbackEvent/ratingPromptSuppressed(reason:)`` is the useful half: it tells you
*why* a happy user was not asked, which is otherwise invisible because the praise
check is on-device and silent. See ``RatingPromptSuppressionReason``.

On watchOS and tvOS no rating events are emitted at all — neither the rating
prompt nor Apple Intelligence exists there, so the code is compiled out.

## Privacy

No event ever carries user-authored content. Not titles, not descriptions, not
email addresses, not attachment filenames, not attachment bytes.

``FeedbackEvent/submissionFailed(_:error:)`` carries the `Error` for your own
logging but projects only a short, stable `error_kind` token into
``FeedbackEvent/parameters`` — `network`, `http_422`, `attachment_upload`, and so
on. This is not cosmetic: `FeedbackSubmissionError.attachmentUpload` interpolates
the user's filename into its `localizedDescription`, and `.transport` forwards a
`URLError` description that can name your relay host. Neither belongs in a
third-party analytics vendor.

`attachment_count` and `has_email` answer "do people attach things, do they leave
an address" without carrying either.

## Isolation

``FeedbackAnalytics/record(_:)`` is synchronous and `nonisolated`. It is called on
whichever context the event happened on: the main actor for sheet events, and
whatever context called ``FeedbackClient/submit(_:)`` for submission events. Keep
it cheap and non-blocking, and do not assume the main actor.

That choice is deliberate. An `async` requirement would push every emission site
into a detached task, and `submissionStarted` could then be delivered *after*
`submissionSucceeded` for the same submission — event order is worth more here
than the convenience.

Most vendor SDKs are callable from any thread, so the conformance above works
as-is. If your analytics wrapper is `@MainActor`-isolated, note that a
`@MainActor` method cannot satisfy a `nonisolated` requirement, and an isolated
conformance is rejected because ``FeedbackAnalytics`` refines `Sendable`. Hop
explicitly — accepting that the hop gives up the ordering the synchronous
requirement was protecting, so buffer in `record` if order matters to you:

```swift
struct MyAnalytics: FeedbackAnalytics {
    nonisolated func record(_ event: FeedbackEvent) {
        Task { @MainActor in
            MyTracker.shared.track(event.name, event.parameters)
        }
    }
}
```

``FeedbackAnalytics/record(_:)`` is called synchronously and inline. Most events
are reported after the fact and can only waste time, but
``FeedbackEvent/submissionStarted(_:attachmentCount:hasContactEmail:)`` is emitted
*before* the transport is awaited — on the main actor when the sheet is driving —
so a slow implementation there delays the request and blocks the UI.

`record` is non-throwing, so a trap crashes your app with nothing for the SDK to
swallow; a trap in ``FeedbackEvent/submissionSucceeded(_:issueNumber:)`` crashes
*after* the issue was filed, so the user sees no confirmation and files it again.
Keep `record` to a synchronous hand-off and do the real work asynchronously.

What the SDK does guarantee: nothing you do here changes what is submitted or
whether it succeeds, and the App Store rating flow never calls `record` from
inside itself.

## New cases arrive in minor releases

The vocabulary will grow. This package is distributed as source rather than as a
library-evolution-enabled binary framework, so a `switch` over ``FeedbackEvent``
**without** a `default:` becomes a *compile error* on the next minor release —
not a warning, and `@unknown default` is not the right tool here.

Either forward ``FeedbackEvent/name`` and ``FeedbackEvent/parameters``, which is
what most integrations want and never breaks:

```swift
func record(_ event: FeedbackEvent) {
    Analytics.logEvent(event.name, parameters: event.parameters)
}
```

…or match exhaustively *with* a `default:`:

```swift
func record(_ event: FeedbackEvent) {
    switch event {
    case .submissionSucceeded(let type, let issueNumber):
        celebrate(type, issueNumber)
    case .cancelled:
        noteDropOff()
    default:
        break
    }
}
```

The `name` strings are covered by tests that fail on a rename, so a dashboard
built on them will not silently go empty.

## Relationship to the sheet's callbacks

`onSubmit`, `onError`, and `onSubmitReport` are **not** deprecated and fire
alongside events. They serve a different purpose: they are control-flow hooks for
your app — show a toast, refresh a list — and they run on the main actor with
that in mind. Analytics is observation. Use whichever fits; using both is fine.
