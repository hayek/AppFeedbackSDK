/// Receives ``FeedbackEvent`` values as the user moves through the feedback flow.
///
/// Analytics are entirely optional. Pass a conformance to
/// ``FeedbackClient/init(appName:transport:analytics:)`` and both the client and
/// `FeedbackSheet` report through it; pass nothing and the SDK
/// behaves exactly as it did before this API existed.
///
/// Most conformances are one line, because ``FeedbackEvent`` projects itself
/// into the shape every analytics vendor already takes:
///
/// ```swift
/// struct MyAnalytics: FeedbackAnalytics {
///     func record(_ event: FeedbackEvent) {
///         Analytics.logEvent(event.name, parameters: event.parameters)
///     }
/// }
/// ```
///
/// ## Isolation
///
/// `record` is synchronous and `nonisolated`. It is called on whichever context
/// the event happened on — the main actor for sheet events, and whatever context
/// called ``FeedbackClient/submit(_:)`` for submission events. Keep it cheap and
/// non-blocking, and do not assume the main actor.
///
/// Isolation is deliberate rather than incidental: an `async` requirement would
/// force every emission site into a detached task, and
/// ``FeedbackEvent/submissionStarted(_:attachmentCount:hasContactEmail:)`` could
/// then be delivered *after* the success event for the same submission.
///
/// If your analytics wrapper is `@MainActor`-isolated, a `@MainActor` method
/// cannot satisfy this requirement and an isolated conformance is rejected
/// because the protocol refines `Sendable`. Hop explicitly instead:
///
/// ```swift
/// nonisolated func record(_ event: FeedbackEvent) {
///     Task { @MainActor in MyAnalytics.shared.track(event.name, event.parameters) }
/// }
/// ```
///
/// ## Guarantees, and what is not guaranteed
///
/// `record` is called synchronously and inline. Most events are reported after
/// the fact and can only waste time, but
/// ``FeedbackEvent/submissionStarted(_:attachmentCount:hasContactEmail:)`` is
/// emitted *before* the transport is awaited — on the main actor when the sheet
/// is driving — so a slow implementation there delays the request and blocks the
/// UI. ``FeedbackEvent/submissionSucceeded(_:issueNumber:)`` lands between the
/// transport returning and your caller receiving the identifier.
///
/// `record` is also non-throwing, so if your implementation traps the SDK has
/// nothing to swallow and your app crashes — and a trap in the success event
/// crashes *after* the issue was already filed, so the user sees no confirmation
/// and files it again. Keep it to a synchronous hand-off; do any real work
/// asynchronously.
///
/// What the SDK does guarantee: nothing you do here changes what is submitted or
/// whether it succeeds, and the App Store rating flow never calls `record` from
/// inside itself.
///
/// No event ever carries user content: titles, descriptions, email addresses,
/// attachment filenames, and attachment bytes stay out of the analytics stream.
public protocol FeedbackAnalytics: Sendable {

    /// Called once per event. See ``FeedbackEvent`` for the vocabulary.
    func record(_ event: FeedbackEvent)
}
