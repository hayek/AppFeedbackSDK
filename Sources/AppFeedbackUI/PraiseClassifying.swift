/// What a classifier concluded about a piece of feedback.
///
/// The distinctions exist so ``FeedbackSheet`` can tell an adopter *why* no
/// rating prompt appeared. Collapsing them into a `Bool` — as this seam did
/// before analytics — makes "the model said no" and "the model fell over"
/// indistinguishable, which is exactly the question you need answered when
/// tuning the prompt.
enum PraiseOutcome: Sendable, Equatable {

    /// Nothing but appreciation for the app.
    case praise

    /// The model read the text and judged it not to be unqualified praise.
    case notPraise

    /// Apple Intelligence could not be reached at all.
    case unavailable

    /// The model failed rather than answered — guardrail, refusal, unsupported
    /// language, or context overflow.
    case failed

    /// No verdict before the deadline. Produced by ``ReviewPromptCoordinator``'s
    /// timer; a classifier never returns it.
    case timedOut
}

/// Decides whether submitted feedback is unqualified praise for the app.
///
/// Deliberately non-throwing: this sits on a purely optional path that runs
/// *after* a report has already been delivered, so there is no failure a caller
/// could usefully handle. Implementations translate every error into
/// ``PraiseOutcome/failed`` — the effect is that no rating prompt appears, which
/// is exactly the behavior on a device without Apple Intelligence.
///
/// The seam exists so ``ReviewPromptCoordinator`` can be tested with a stub on
/// platforms and toolchains where Foundation Models does not exist.
protocol PraiseClassifying: Sendable {

    /// - Returns: ``PraiseOutcome/praise`` only when the text is exclusively
    ///   positive, with no bug, complaint, question, or request mixed in.
    func classify(title: String, description: String) async -> PraiseOutcome
}
