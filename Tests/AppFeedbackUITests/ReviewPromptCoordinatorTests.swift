import XCTest
@testable import AppFeedbackUI

/// The coordinator holds every timing and short-circuit decision so they can be
/// exercised without SwiftUI, StoreKit, or Apple Intelligence. Compare
/// ``FeedbackSheet/makeReport(type:title:description:contactEmail:attachments:extraFields:)``,
/// extracted from the view for the same reason.
@MainActor
final class ReviewPromptCoordinatorTests: XCTestCase {

    private final class Recorder { var calls = 0 }

    private struct StubClassifier: PraiseClassifying {
        let answer: Bool
        var delay: Duration = .zero

        func isPurePraise(title: String, description: String) async -> Bool {
            if delay != .zero { try? await Task.sleep(for: delay) }
            return answer
        }
    }

    /// Models a wedged `respond` — busy work that never observes cancellation.
    /// `Task.sleep` is the wrong stand-in for this: it wakes the moment it is
    /// cancelled, so a sleeping stub cooperates and proves nothing about a
    /// classifier that does not.
    private struct UncooperativeStub: PraiseClassifying {
        let answer: Bool
        let duration: Duration

        func isPurePraise(title: String, description: String) async -> Bool {
            let end = ContinuousClock.now + duration
            while ContinuousClock.now < end { await Task.yield() }
            return answer
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

    func test_pure_praise_presents_the_prompt_exactly_once() async {
        let recorder = Recorder()
        await makeCoordinator().run(
            title: "Love it", description: "Best app on my phone",
            classifier: StubClassifier(answer: true),
            presentReview: { recorder.calls += 1 }
        )
        XCTAssertEqual(recorder.calls, 1)
    }

    func test_non_praise_never_presents() async {
        let recorder = Recorder()
        await makeCoordinator().run(
            title: "Crash", description: "It crashes on launch",
            classifier: StubClassifier(answer: false),
            presentReview: { recorder.calls += 1 }
        )
        XCTAssertEqual(recorder.calls, 0)
    }

    /// No Apple Intelligence resolves to a `nil` classifier, which must reproduce
    /// today's behavior exactly: nothing happens, and nothing is waited on.
    func test_absent_classifier_never_presents_and_returns_promptly() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        await makeCoordinator(minimumDelay: .seconds(30)).run(
            title: "Love it", description: "Best app on my phone",
            classifier: nil,
            presentReview: { recorder.calls += 1 }
        )
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    func test_slow_classifier_is_abandoned_at_the_deadline() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        await makeCoordinator(classificationDeadline: .milliseconds(50)).run(
            title: "Love it", description: "Best app on my phone",
            classifier: StubClassifier(answer: true, delay: .seconds(60)),
            presentReview: { recorder.calls += 1 }
        )
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    /// The deadline has to be a real bound, not a request. A task group would
    /// implicitly await this classifier before returning, so `run` would block
    /// for the stub's full duration despite the 50 ms deadline.
    func test_classifier_that_ignores_cancellation_still_returns_at_the_deadline() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        await makeCoordinator(classificationDeadline: .milliseconds(50)).run(
            title: "Love it", description: "Best app on my phone",
            classifier: UncooperativeStub(answer: true, duration: .milliseconds(800)),
            presentReview: { recorder.calls += 1 }
        )
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(500))
    }

    /// A verdict that loses the race must stay lost — it cannot arrive late and
    /// present a prompt against an already-returned `false`.
    func test_verdict_arriving_after_the_deadline_is_ignored() async {
        let recorder = Recorder()
        await makeCoordinator(classificationDeadline: .milliseconds(50)).run(
            title: "Love it", description: "Best app on my phone",
            classifier: StubClassifier(answer: true, delay: .milliseconds(400)),
            presentReview: { recorder.calls += 1 }
        )
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(recorder.calls, 0)
    }

    /// Tapping Done or swiping the sheet away cancels the `.task` driving this.
    /// A rating alert must not surface over a sheet that is already leaving.
    func test_cancellation_during_the_delay_suppresses_the_prompt() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(minimumDelay: .seconds(30))
        let task = Task { @MainActor in
            await coordinator.run(
                title: "Love it", description: "Best app on my phone",
                classifier: StubClassifier(answer: true),
                presentReview: { recorder.calls += 1 }
            )
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        XCTAssertEqual(recorder.calls, 0)
    }

    /// The prompt has to clear the form→success crossfade and the checkmark
    /// spring, so a verdict that arrives early still waits.
    func test_prompt_waits_out_the_minimum_delay() async {
        let recorder = Recorder()
        let start = ContinuousClock.now
        await makeCoordinator(minimumDelay: .milliseconds(300)).run(
            title: "Love it", description: "Best app on my phone",
            classifier: StubClassifier(answer: true),
            presentReview: { recorder.calls += 1 }
        )
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(250))
    }
}
