import XCTest
import AppFeedbackCore
@testable import AppFeedbackUI

/// The coordinator holds every timing and short-circuit decision so they can be
/// exercised without SwiftUI, StoreKit, or Apple Intelligence. Compare
/// ``FeedbackSheet/makeReport(type:title:description:contactEmail:attachments:extraFields:)``,
/// extracted from the view for the same reason.
///
/// It returns an outcome rather than recording anything: an adopter's analytics
/// sink is never called from inside the rating path, so a sink that traps cannot
/// crash it, and these tests need no analytics dependency.
@MainActor
final class ReviewPromptCoordinatorTests: XCTestCase {

    private final class Recorder { var calls = 0 }

    private struct StubClassifier: PraiseClassifying {
        let outcome: PraiseOutcome
        var delay: Duration = .zero

        func classify(title: String, description: String) async -> PraiseOutcome {
            if delay != .zero { try? await Task.sleep(for: delay) }
            return outcome
        }
    }

    /// Models a wedged `respond` — busy work that never observes cancellation.
    /// `Task.sleep` is the wrong stand-in: it wakes the moment it is cancelled,
    /// so a sleeping stub cooperates and proves nothing about one that doesn't.
    private struct UncooperativeStub: PraiseClassifying {
        let duration: Duration
        func classify(title: String, description: String) async -> PraiseOutcome {
            let end = ContinuousClock.now + duration
            while ContinuousClock.now < end { await Task.yield() }
            return .praise
        }
    }

    private func makeCoordinator(
        minimumDelay: Duration = .zero,
        classificationDeadline: Duration = .seconds(1)
    ) -> ReviewPromptCoordinator {
        ReviewPromptCoordinator(
            minimumDelay: minimumDelay,
            classificationDeadline: classificationDeadline
        )
    }

    @discardableResult
    private func run(
        _ coordinator: ReviewPromptCoordinator,
        classifier: (any PraiseClassifying)?,
        presented: Bool = true,
        recorder: Recorder
    ) async -> ReviewPromptOutcome {
        await coordinator.run(
            title: "Love it",
            description: "Best app on my phone",
            classifier: classifier,
            presentReview: { recorder.calls += 1; return presented }
        )
    }

    func test_pure_praise_presents_the_prompt_exactly_once() async {
        let recorder = Recorder()
        let outcome = await run(makeCoordinator(), classifier: StubClassifier(outcome: .praise), recorder: recorder)
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertEqual(outcome, .requested)
    }

    func test_each_classifier_outcome_maps_to_its_own_suppression_reason() async {
        let expected: [(PraiseOutcome, RatingPromptSuppressionReason)] = [
            (.notPraise, .notPraise),
            (.unavailable, .appleIntelligenceUnavailable),
            (.failed, .classifierFailed),
        ]
        for (outcome, reason) in expected {
            let recorder = Recorder()
            let result = await run(makeCoordinator(), classifier: StubClassifier(outcome: outcome), recorder: recorder)
            XCTAssertEqual(result, .suppressed(reason), "\(outcome)")
            XCTAssertEqual(recorder.calls, 0, "\(outcome)")
        }
    }

    /// No Apple Intelligence resolves to a `nil` classifier, which must reproduce
    /// the pre-feature behavior: nothing happens, and nothing is waited on.
    func test_absent_classifier_reports_unavailable_promptly() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        let outcome = await run(makeCoordinator(minimumDelay: .seconds(30)), classifier: nil, recorder: recorder)
        XCTAssertEqual(outcome, .suppressed(.appleIntelligenceUnavailable))
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    func test_slow_classifier_is_abandoned_at_the_deadline() async {
        let recorder = Recorder()
        let outcome = await run(
            makeCoordinator(classificationDeadline: .milliseconds(50)),
            classifier: StubClassifier(outcome: .praise, delay: .seconds(60)),
            recorder: recorder
        )
        XCTAssertEqual(outcome, .suppressed(.classificationTimedOut))
        XCTAssertEqual(recorder.calls, 0)
    }

    /// The deadline has to be a real bound, not a request. A task group would
    /// implicitly await this classifier before returning, so `run` would block
    /// for the stub's full duration despite the 50 ms deadline.
    func test_classifier_that_ignores_cancellation_still_returns_at_the_deadline() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        let outcome = await run(
            makeCoordinator(classificationDeadline: .milliseconds(50)),
            classifier: UncooperativeStub(duration: .milliseconds(800)),
            recorder: recorder
        )
        XCTAssertEqual(outcome, .suppressed(.classificationTimedOut))
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(500))
    }

    /// Tapping Done or swiping the sheet away cancels the `.task` driving this.
    /// Dismissal outranks whatever the model was about to say.
    func test_cancellation_during_the_delay_reports_dismissed() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(minimumDelay: .seconds(30))
        let task = Task { @MainActor in
            await self.run(coordinator, classifier: StubClassifier(outcome: .praise), recorder: recorder)
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .suppressed(.dismissed))
        XCTAssertEqual(recorder.calls, 0)
    }

    /// A verdict that loses the race must stay lost — it cannot arrive late and
    /// present a prompt against an already-returned timeout. Structural (the
    /// stream is finished in `defer`), but worth pinning.
    func test_verdict_arriving_after_the_deadline_never_presents() async {
        let recorder = Recorder()
        let outcome = await run(
            makeCoordinator(classificationDeadline: .milliseconds(50)),
            classifier: StubClassifier(outcome: .praise, delay: .milliseconds(400)),
            recorder: recorder
        )
        XCTAssertEqual(outcome, .suppressed(.classificationTimedOut))
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(recorder.calls, 0)
    }

    /// The sheet declines to present when it is already dismissing. The
    /// coordinator must report that, not claim a prompt was requested.
    func test_declined_presentation_reports_dismissed() async {
        let recorder = Recorder()
        let outcome = await run(
            makeCoordinator(),
            classifier: StubClassifier(outcome: .praise),
            presented: false,
            recorder: recorder
        )
        XCTAssertEqual(outcome, .suppressed(.dismissed))
        XCTAssertEqual(recorder.calls, 1)
    }

    /// The prompt has to clear the form→success crossfade and the checkmark
    /// spring, so a verdict that arrives early still waits.
    func test_prompt_waits_out_the_minimum_delay() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        await run(
            makeCoordinator(minimumDelay: .milliseconds(300)),
            classifier: StubClassifier(outcome: .praise),
            recorder: recorder
        )
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(250))
    }
}
