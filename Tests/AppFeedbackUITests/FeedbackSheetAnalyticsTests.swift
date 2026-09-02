import Foundation
import XCTest
import AppFeedbackCore
@testable import AppFeedbackUI

final class FeedbackSheetAnalyticsTests: XCTestCase {

    /// `cancelled` fires from the root view's `.onDisappear`, which also runs on
    /// a successful submission and on a mid-flight dismissal. The guard is the
    /// whole feature, so it gets a truth table.
    func test_cancellation_truth_table() {
        // Left without submitting — the only real cancellation.
        XCTAssertTrue(FeedbackSheet.isCancellation(submitted: false, isSubmitting: false))

        // Success: `formContent` is replaced by `successView`, so a naive
        // onDisappear would report every completed submission as a cancel.
        XCTAssertFalse(FeedbackSheet.isCancellation(submitted: true, isSubmitting: false))

        // Swiped away while the request is in flight: reporting a cancel here
        // would be followed moments later by the client's success event.
        XCTAssertFalse(FeedbackSheet.isCancellation(submitted: false, isSubmitting: true))

        XCTAssertFalse(FeedbackSheet.isCancellation(submitted: true, isSubmitting: true))
    }

    /// Gating on "no message shown yet" swallowed real rejections: the message
    /// is also set by photo-loading failures, and a change of reason while a
    /// message is already up went unreported.
    func test_rejection_is_reported_per_reason_not_per_message() {
        let oversized = FeedbackAttachmentError.fileTooLarge(filename: "a.png", sizeBytes: 9, limit: 1)
        let badType = FeedbackAttachmentError.unsupportedMimeType(filename: "b.zip", mimeType: "application/zip")

        // First rejection of an episode.
        XCTAssertTrue(FeedbackSheet.shouldReportRejection(previous: nil, current: oversized))

        // Re-validating with the same failure — every keystroke calls through
        // here — must stay quiet.
        XCTAssertFalse(FeedbackSheet.shouldReportRejection(previous: oversized, current: oversized))

        // Remove the oversized file and the next offender is a different reason:
        // a new dead end, and it has to be reported.
        XCTAssertTrue(FeedbackSheet.shouldReportRejection(previous: oversized, current: badType))

        // Same reason, different file, is still the same dead end.
        let otherOversized = FeedbackAttachmentError.fileTooLarge(filename: "c.png", sizeBytes: 8, limit: 1)
        XCTAssertTrue(FeedbackSheet.shouldReportRejection(previous: oversized, current: otherOversized))
    }

    /// Built from stable identifiers so the funnel step doesn't fragment across
    /// locales and adopter themes.
    func test_missing_fields_are_stable_identifiers_in_field_order() {
        XCTAssertEqual(FeedbackSheet.missingFields(title: "", description: ""), [.title, .description])
        XCTAssertEqual(FeedbackSheet.missingFields(title: "", description: "d"), [.title])
        XCTAssertEqual(FeedbackSheet.missingFields(title: "t", description: ""), [.description])
        XCTAssertEqual(FeedbackSheet.missingFields(title: "t", description: "d"), [])

        XCTAssertEqual(
            FeedbackEvent.validationFailed(
                missingFields: FeedbackSheet.missingFields(title: "", description: "")
            ).parameters,
            ["missing_fields": "title,description"]
        )
    }

    /// The sheet reads the sink off the client — there is no sheet-level
    /// parameter — so a client built without analytics must stay a no-op.
    func test_sheet_instantiates_with_and_without_an_analytics_sink() {
        let plain = FeedbackClient(transport: NoOpTransport(), deviceInfo: .stub)
        let instrumented = FeedbackClient(
            transport: NoOpTransport(), deviceInfo: .stub, analytics: RecordingAnalytics()
        )
        _ = FeedbackSheet(client: plain).body
        _ = FeedbackSheet(client: instrumented).body
    }
}

private struct NoOpTransport: FeedbackTransport {
    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int { 0 }
}

extension DeviceInfo {
    static var stub: DeviceInfo {
        DeviceInfo(
            appName: "AcmeApp", appVersion: "1.0", buildNumber: "1",
            model: "Mac15,11", osName: "macOS", osVersion: "15.1"
        )
    }
}

/// Mirrors the Core test spy; the UI test target can't see it across modules.
final class RecordingAnalytics: FeedbackAnalytics, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FeedbackEvent] = []
    var events: [FeedbackEvent] { lock.lock(); defer { lock.unlock() }; return storage }
    func record(_ event: FeedbackEvent) {
        lock.lock(); defer { lock.unlock() }
        storage.append(event)
    }
}
