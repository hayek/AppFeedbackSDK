import AppFeedbackCore

/// What the rating flow ended up doing.
///
/// Returned rather than recorded: keeping ``FeedbackAnalytics`` out of this type
/// means an adopter's `record` — which is non-throwing and could trap — is never
/// called from inside the rating path, and these decisions stay testable without
/// an analytics dependency.
enum ReviewPromptOutcome: Sendable, Equatable {

    /// The system was asked to show the prompt. Whether it did is not observable.
    case requested

    /// No prompt, for this reason.
    case suppressed(RatingPromptSuppressionReason)
}

/// Decides whether — and when — the native App Store rating prompt follows a
/// successful submission.
///
/// All of the timing and short-circuit logic lives here rather than in
/// ``FeedbackSheet`` so it can be exercised against a stub classifier, with no
/// SwiftUI, no StoreKit, and no Apple Intelligence. That is the same reason
/// `makeReport` was lifted out of the view.
///
/// The one guarantee worth stating: this type runs strictly *after* the report
/// has been delivered, and every path through it ends in either "present the
/// prompt" or "do nothing". A slow, erroring, or absent model cannot affect the
/// submission that already happened.
@MainActor
struct ReviewPromptCoordinator {

    /// How long to let the success screen settle before a system alert may
    /// appear over it. Covers the 0.45 s form→success crossfade plus the
    /// checkmark spring and content fade behind it.
    var minimumDelay: Duration = .seconds(1.5)

    /// How long to wait on a verdict before giving up on the prompt entirely.
    var classificationDeadline: Duration = .seconds(5)

    /// - Parameters:
    ///   - classifier: `nil` when Apple Intelligence is unreachable, which
    ///     returns immediately and reproduces the pre-feature behavior exactly.
    ///   - presentReview: Invoked at most once, on the main actor. Returns
    ///     `false` if it declined — the sheet is already dismissing — which is
    ///     reported as ``RatingPromptSuppressionReason/dismissed`` rather than a
    ///     prompt that never appeared.
    func run(
        title: String,
        description: String,
        classifier: (any PraiseClassifying)?,
        presentReview: () -> Bool
    ) async -> ReviewPromptOutcome {
        // Dismissal is terminal and outranks every other reason, including the
        // absence of a classifier.
        guard !Task.isCancelled else { return .suppressed(.dismissed) }
        guard let classifier else { return .suppressed(.appleIntelligenceUnavailable) }

        // The delay and the classification overlap, so the model's latency is
        // usually free — the prompt lands as soon as the slower of the two ends.
        async let settled: Void = Self.sleep(for: minimumDelay)
        let outcome = await verdict(title: title, description: description, from: classifier)
        await settled

        // Dismissal is terminal and outranks whatever the model was going to say.
        guard !Task.isCancelled else { return .suppressed(.dismissed) }

        switch outcome {
        case .praise:
            return presentReview() ? .requested : .suppressed(.dismissed)
        case .notPraise:
            return .suppressed(.notPraise)
        case .unavailable:
            return .suppressed(.appleIntelligenceUnavailable)
        case .failed:
            return .suppressed(.classifierFailed)
        case .timedOut:
            return .suppressed(.classificationTimedOut)
        }
    }

    /// Races the classifier against ``classificationDeadline``. Whichever
    /// answers first wins; a timeout answers ``PraiseOutcome/timedOut``.
    ///
    /// Both racers are *unstructured* tasks on purpose. A task group implicitly
    /// awaits every child before it returns, and `cancelAll()` only *requests*
    /// cancellation — so a classifier that never observed cancellation (a wedged
    /// `respond`, or any future implementation doing uninterruptible work) would
    /// pin the group open long past the deadline and leak the `.task` driving
    /// it. Nothing below is awaited, so abandoning the loser genuinely abandons
    /// it and the deadline is a real bound.
    private func verdict(
        title: String,
        description: String,
        from classifier: any PraiseClassifying
    ) async -> PraiseOutcome {
        let deadline = classificationDeadline
        let (answers, send) = AsyncStream<PraiseOutcome>.makeStream()

        let work = Task.detached(priority: .utility) {
            send.yield(await classifier.classify(title: title, description: description))
        }
        let timer = Task.detached(priority: .utility) {
            await Self.sleep(for: deadline)
            send.yield(.timedOut)
        }
        defer {
            work.cancel()
            timer.cancel()
            send.finish()
        }

        // Also yields `nil` if the caller is cancelled; `run` maps that to
        // `.dismissed` via its own `Task.isCancelled` check.
        for await answer in answers { return answer }
        return .timedOut
    }

    /// `Task.sleep` throws only on cancellation, which callers detect via
    /// `Task.isCancelled` — so waking early is the correct response, not an
    /// error. `nonisolated` so the racers above can start sleeping without
    /// first hopping to the main actor.
    nonisolated private static func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
