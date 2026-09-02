# AppFeedback SDK — Analytics Event Triggers

- **Date:** 2026-09-02
- **Status:** Approved design (revised after adversarial review) — implementing
- **Scope:** An optional, opt-in analytics surface so adopters can observe the feedback funnel: sheet opened, type chosen, attachments, validation blocks, submission outcome, cancellation, and App Store rating-prompt decisions.
- **Release:** v0.8.0 — purely additive, every new parameter defaulted.

---

## 1. Context

`AppFeedbackSDK` ships two targets: `AppFeedbackCore` (headless — `FeedbackClient`, transports, wire format) and `AppFeedbackUI` (the SwiftUI `FeedbackSheet`). As of v0.7.0 the sheet also asks Apple Intelligence whether the feedback is praise and, if so, presents the native App Store rating prompt.

Adopters currently observe the SDK only through `FeedbackSheet`'s `onSubmit` / `onError` / `onSubmitReport` callbacks. Those are *control-flow* hooks for the host app, they exist only on the UI path, and they cover exactly one moment: a completed submission. They answer none of the funnel questions — how many people opened the sheet and left, how many were blocked by validation, how many were prompted to rate.

**Goal:** one optional sink that receives the whole funnel, forwards to any analytics vendor in one line, and can never alter or delay SDK behavior.

## 2. Decisions (with rationale)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `FeedbackAnalytics` protocol + `FeedbackEvent` enum, with `name`/`parameters` projection | Type-safe and exhaustively switchable for adopters who want it; `Firebase.logEvent(e.name, parameters: e.parameters)` for adopters who don't. Rejected a bare closure (can't be shared by client and sheet) and a bare name+parameters API (no type safety). |
| 2 | Types live in `AppFeedbackCore` | Headless adopters get submission analytics without importing the UI target. `FeedbackEvent` references `FeedbackType`, which is already in Core. |
| 3 | **The client is the single sink.** No `analytics:` parameter on `FeedbackSheet` | An adopter setting a sink only on the sheet would silently never receive submission events — the exact question they are asking — with no compiler help. One configuration point cannot split a funnel across two destinations. |
| 4 | `FeedbackClient.analytics` is `package`, not `public` | UI needs to read it; adopters never do. Keeps it out of the public API forever. |
| 5 | New enum cases may ship in minor releases | The vocabulary will grow. The stable contract is `name`/`parameters`, which the common forwarding usage relies on exclusively. |
| 6 | `record` is synchronous and `nonisolated` | Preserves event ordering. An `async` requirement forces `Task { await … }` at every emit site, letting `submissionStarted` arrive after `submissionSucceeded`. Every major vendor SDK is callable from any thread. |
| 7 | Events carry no user content, ever | Titles, descriptions, emails, filenames, and attachment bytes never enter the analytics stream. Pinned by test. |
| 8 | No `userRated` / `ratingPromptShown` | `RequestReviewAction` returns `Void`, the system may silently show nothing, and Apple exposes no way to learn either. Shipping them would guarantee events that never fire. |

## 3. Public API (`AppFeedbackCore`)

```swift
public protocol FeedbackAnalytics: Sendable {
    func record(_ event: FeedbackEvent)
}

public enum FeedbackField: String, Sendable, Hashable, CaseIterable {
    case title, description
}

public enum AttachmentSource: String, Sendable, Hashable {
    case files, photoLibrary, paste, drop
}

public enum RatingPromptSuppressionReason: String, Sendable, Hashable {
    case disabled                      // requestsAppStoreReview == false
    case appleIntelligenceUnavailable  // OS < 26, no SDK, ineligible, off, downloading
    case notPraise                     // the model judged it not pure praise
    case classifierFailed              // guardrail, refusal, unsupported language, overflow
    case classificationTimedOut        // deadline won the race
    case dismissed                     // the sheet left before the prompt could show
}

public enum FeedbackEvent: Sendable {
    case sheetPresented
    case typeSelected(FeedbackType)
    case attachmentAdded(source: AttachmentSource)
    case attachmentRejected(FeedbackAttachmentError)
    case validationFailed(missingFields: [FeedbackField])
    case submissionStarted(FeedbackType, attachmentCount: Int, hasContactEmail: Bool)
    case submissionSucceeded(FeedbackType, issueNumber: Int)
    case submissionFailed(FeedbackType, error: any Error & Sendable)
    case cancelled
    case ratingPromptRequested
    case ratingPromptSuppressed(reason: RatingPromptSuppressionReason)

    public var name: String
    public var parameters: [String: String]
}
```

`FeedbackEvent` is `Equatable` via a manual `==` over `name`/`parameters` — the `any Error & Sendable` payload blocks synthesis, and equality over the stable contract is what tests actually want.

### 3.1 Name and parameter table

All names are `feedback_`-prefixed snake_case. Verified against Firebase (1–40 chars, alphanumeric + underscore, must start with a letter, no `firebase_`/`google_`/`ga_` prefix, not a reserved name, ≤25 params, param names ≤40 chars, **string values ≤100 chars**) and Mixpanel (≤255 chars, no `$`/`mp_` prefix).

| Case | `name` (len) | `parameters` |
|---|---|---|
| `sheetPresented` | `feedback_sheet_presented` (24) | — |
| `typeSelected` | `feedback_type_selected` (22) | `type` |
| `attachmentAdded` | `feedback_attachment_added` (25) | `source` |
| `attachmentRejected` | `feedback_attachment_rejected` (28) | `reason` |
| `validationFailed` | `feedback_validation_failed` (26) | `missing_fields` (comma-joined raw values) |
| `submissionStarted` | `feedback_submission_started` (27) | `type`, `attachment_count`, `has_email` |
| `submissionSucceeded` | `feedback_submission_succeeded` (29) | `type`, `issue_number` |
| `submissionFailed` | `feedback_submission_failed` (26) | `type`, `error_kind` |
| `cancelled` | `feedback_cancelled` (18) | — |
| `ratingPromptRequested` | `feedback_rating_prompt_requested` (32) | — |
| `ratingPromptSuppressed` | `feedback_rating_prompt_suppressed` (33) | `reason` |

`error_kind` is a stable short token derived from `FeedbackSubmissionError`, never `localizedDescription`: `invalid_response`, `http_<code>`, `decoding`, `network`, `attachment_validation`, `attachment_upload`, and `other` for any non-`FeedbackSubmissionError`. This is a privacy requirement, not a cosmetic one — `.attachmentUpload` interpolates the user's filename into `errorDescription`, and `.transport` forwards `URLError.localizedDescription`, which can name the relay host.

`issue_number` is a string, so Firebase cannot aggregate it numerically. Accepted: `[String: String]` is the settled contract and issue numbers are identifiers, not measures.

## 4. Emission sites

**One emitter per event.** `FeedbackClient` owns the submission lifecycle; `FeedbackSheet` owns everything else. Nothing is emitted twice.

### 4.1 `FeedbackClient` (Core)

Both inits gain `analytics: (any FeedbackAnalytics)? = nil`. `submit(_:)` emits `submissionStarted` before awaiting the transport, then exactly one of `submissionSucceeded` / `submissionFailed`. `attachmentCount` and `hasContactEmail` come from the report, so "do people attach things / leave an email" is answered without per-keystroke events.

### 4.2 `FeedbackSheet` (UI)

| Event | Site |
|---|---|
| `sheetPresented` | root `.task` — runs once per view identity, unlike `.onAppear`, which can re-fire on re-layout |
| `typeSelected` | the type-card action, guarded by `type != selectedType` so re-tapping the selected card is silent |
| `attachmentAdded` | `ingest(urls:)` (files / macOS drop, distinguished by caller), `ingest(picks:)` (photos), `pasteImage()` |
| `attachmentRejected` | `revalidate()`, when the validator sets `attachmentError` — today a user blocked this way produces no signal at all |
| `validationFailed` | `submit()`, from the same two `isEmpty` checks that drive the alert — built from `FeedbackField`, never `theme.copy` |
| `cancelled` | root `.onDisappear`, guarded by `submittedIssueNumber == nil && !isSubmitting` |
| `ratingPromptRequested` | the `presentReview` closure, after the `isDismissing` guard passes |
| `ratingPromptSuppressed` | every other terminal path of the rating flow |

**`cancelled` is the subtle one.** It cannot live on `formContent`: the `submittedIssueNumber == nil` branch removes that view on *success*, so it would fire for every completed submission. It goes on the root `ZStack`. The `!isSubmitting` half of the guard covers a user who taps Submit and swipes the sheet away mid-flight, which would otherwise emit `cancelled` and then `submissionSucceeded` a second later. We additionally add `.interactiveDismissDisabled(isSubmitting)`, which closes a genuine UX hole — today a swipe can abandon an in-flight submission.

The truth table (`submitted`, `isSubmitting`) → emit-or-not is extracted as a pure `static func` so it is unit-testable, following the `makeReport` precedent. `cancelled` means *left without a successful submission*, not *tapped Cancel* — there is no cancel button. An app killed with the sheet open emits nothing.

## 5. Making the suppression reasons real

Today `FoundationModelsPraiseClassifier.isPurePraise` returns `Bool`, collapsing "Apple Intelligence unavailable" and every thrown error into `false`; `ReviewPromptCoordinator` streams `Bool`, and its timeout and caller-cancellation paths also yield `false`. At the `guard isPraise` all six reasons are indistinguishable.

Changes, all to **internal** types (no public churn):

- `PraiseClassifying.classify(title:description:) async -> PraiseOutcome`, where `PraiseOutcome` is `.praise` / `.notPraise` / `.unavailable` / `.failed`.
- `ReviewPromptCoordinator` streams `PraiseOutcome`; the timer yields `.timedOut`; `run` returns a `ReviewPromptOutcome` (`.requested` / `.suppressed(RatingPromptSuppressionReason)`) instead of `Void`.
- `FeedbackSheet` maps that outcome to an event and records it.

**`record` is never called from inside the coordinator or the classifier.** Two reasons: an adopter's `record` that traps would then crash from within the rating path, and `ReviewPromptCoordinatorTests` would acquire an analytics dependency it does not need. Emission stays in the sheet.

This does not weaken the v0.7.0 guarantee that a model failure cannot affect submission: the coordinator still runs only inside `successView.task`, after the transport has returned, and every path still ends in present-or-skip.

**Precedence** when several reasons apply at once: `dismissed` > `disabled` > `appleIntelligenceUnavailable` > `classificationTimedOut` > `classifierFailed` > `notPraise`. Dismissal is terminal and outranks whatever the model was going to say.

**watchOS / tvOS emit no rating events at all** — the entire block is compiled out. Documented rather than modelled as a reason, since there is no code path left to emit from.

## 6. Threading

`record` is synchronous and `nonisolated`, invoked on whatever context the event occurs on: the main actor for sheet events; whatever context called `FeedbackClient.submit`, which is a nonisolated `async` function, for client events. The documented contract is *cheap and non-blocking, and do not assume the main actor*.

The friction case must be spelled out verbatim in the DocC article: an adopter whose analytics wrapper is `@MainActor`-isolated cannot satisfy a `nonisolated` requirement, and an isolated conformance is rejected because the protocol refines `Sendable`. They write:

```swift
nonisolated func record(_ event: FeedbackEvent) {
    Task { @MainActor in MyAnalytics.shared.track(event.name, event.parameters) }
}
```

If an adopter's `record` traps, their app crashes and the SDK cannot contain it — `record` is non-throwing, so there is nothing to swallow. Stated plainly in the docs.

## 7. Testing

- `RecordingAnalytics` spy in test support.
- **Name/parameter snapshot** for every case — `name` is the declared stable contract, so a rename must fail a test.
- **Privacy invariant:** submit a report whose title, description, email, and attachment filename are unique sentinels; assert no emitted event's `name` or `parameters` contains any of them.
- `error_kind` mapping across all six `FeedbackSubmissionError` cases plus a foreign error.
- One-emitter-per-event: a sheet-driven submission produces exactly one `submissionSucceeded`.
- `nil` analytics is a genuine no-op.
- Terminal-event truth table for `cancelled`.
- Coordinator outcome tests for all six suppression reasons, using stub classifiers.

## 8. Documentation

- `README.md` — the quick-start currently puts analytics inside `onSubmit`/`onError` (~:33-41) and the migration section tells adopters to move analytics calls there (~:185). Both rewritten. State that `onSubmit`/`onError`/`onSubmitReport` are **not** deprecated and fire alongside events.
- `AppFeedbackCore.docc/Analytics.md` — new article in the style of `CustomTransports.md`, plus a Topics group for the four new symbols. Carries the `@MainActor` recipe, the growth caveat, and the "we cannot know if they rated" note.
- `AppFeedbackUI.docc/AppFeedbackUI.md` — a paragraph pointing at it.
- The `FeedbackEvent` doc comment must be precise about growth: this is a non-resilient SwiftPM package, so an adopter's exhaustive `switch` without `default:` becomes a **compile error** on the next minor — not a warning, and `@unknown default` is not the right tool.
- `CHANGELOG.md` `[Unreleased] → Added`.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Adopters write exhaustive switches and break on 0.9.0 | Documented growth policy; `name`/`parameters` offered as the stable path and used in every example. |
| A trapping or blocking `record` degrades the host app | Documented contract; emission is always after-the-fact and off every critical path. |
| Event vocabulary drifts from what dashboards expect | `name` snapshot test makes any rename a build failure. |
| PII leaking into a third-party analytics vendor | `error_kind` instead of descriptions; no user content in any payload; pinned by the privacy invariant test. |

## 10. Deferred

`attachmentRemoved`, field-level/keystroke events, timing and duration metrics, a sheet-level sink override, and numeric parameter values. All additive later under the growth policy.
