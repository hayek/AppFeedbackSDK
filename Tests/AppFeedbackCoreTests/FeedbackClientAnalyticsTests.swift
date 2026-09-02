import XCTest
@testable import AppFeedbackCore

/// `FeedbackClient` is the single sink and the only emitter of submission
/// events; the sheet never re-emits them, so a submission can't be double-counted.
final class FeedbackClientAnalyticsTests: XCTestCase {

    private func makeClient(
        transport: any FeedbackTransport,
        analytics: any FeedbackAnalytics
    ) -> FeedbackClient {
        FeedbackClient(
            transport: transport,
            deviceInfo: DeviceInfo(
                appName: "AcmeApp", appVersion: "1.0", buildNumber: "1",
                model: "Mac15,11", osName: "macOS", osVersion: "15.1"
            ),
            analytics: analytics
        )
    }

    private func report(
        type: FeedbackType = .bug,
        email: String? = nil,
        attachments: [FeedbackAttachment] = []
    ) -> FeedbackReport {
        FeedbackReport(
            type: type, title: "t", description: "d",
            contactEmail: email, extraFields: [:], attachments: attachments
        )
    }

    func test_successful_submission_emits_started_then_succeeded() async throws {
        let sink = RecordingAnalytics()
        let client = makeClient(transport: StubTransport(result: .success(7)), analytics: sink)

        _ = try await client.submit(report())

        XCTAssertEqual(sink.names, ["feedback_submission_started", "feedback_submission_succeeded"])
        XCTAssertEqual(sink.events.last?.parameters, ["type": "bug", "issue_number": "7"])
    }

    func test_failed_submission_emits_started_then_failed() async {
        let sink = RecordingAnalytics()
        let client = makeClient(
            transport: StubTransport(result: .failure(FeedbackSubmissionError.httpStatus(422, body: nil))),
            analytics: sink
        )

        _ = try? await client.submit(report(type: .featureRequest))

        XCTAssertEqual(sink.names, ["feedback_submission_started", "feedback_submission_failed"])
        XCTAssertEqual(
            sink.events.last?.parameters,
            ["type": "feature-request", "error_kind": "http_422"]
        )
    }

    /// Answers "do people attach things / leave an email" without per-keystroke
    /// events, and without carrying the address itself.
    func test_started_event_summarises_the_report_without_carrying_its_content() async throws {
        let sink = RecordingAnalytics()
        let client = makeClient(transport: StubTransport(result: .success(1)), analytics: sink)

        _ = try await client.submit(report(
            email: "person@example.com",
            attachments: [
                FeedbackAttachment(filename: "a.png", mimeType: "image/png", data: Data([1])),
                FeedbackAttachment(filename: "b.png", mimeType: "image/png", data: Data([2])),
            ]
        ))

        let started = try XCTUnwrap(sink.events.first)
        XCTAssertEqual(started.parameters["attachment_count"], "2")
        XCTAssertEqual(started.parameters["has_email"], "true")
        let payload = started.parameters.values.joined(separator: " ")
        XCTAssertFalse(payload.contains("person@example.com"))
        XCTAssertFalse(payload.contains("a.png"))
    }

    /// The invariant is "no event ever carries user content". Asserted with
    /// sentinels distinctive enough that a substring hit means a real leak —
    /// unlike "t"/"d", which appear inside words like "true".
    func test_no_emitted_event_carries_user_content() async {
        let sink = RecordingAnalytics()
        let client = makeClient(
            transport: StubTransport(result: .failure(
                FeedbackSubmissionError.attachmentUpload(
                    filename: "ZZFILENAMEZZ.pdf", underlying: SampleError()
                )
            )),
            analytics: sink
        )

        _ = try? await client.submit(FeedbackReport(
            type: .bug,
            title: "ZZTITLEZZ",
            description: "ZZDESCRIPTIONZZ",
            contactEmail: "ZZEMAILZZ@example.com",
            extraFields: ["k": "ZZEXTRAZZ"],
            attachments: [FeedbackAttachment(
                filename: "ZZFILENAMEZZ.pdf", mimeType: "application/pdf", data: Data([1, 2, 3])
            )]
        ))

        XCTAssertFalse(sink.events.isEmpty, "nothing was recorded, so nothing was proven")
        let sentinels = ["ZZTITLEZZ", "ZZDESCRIPTIONZZ", "ZZEMAILZZ", "ZZEXTRAZZ", "ZZFILENAMEZZ"]
        for event in sink.events {
            let payload = ([event.name] + event.parameters.keys + event.parameters.values)
                .joined(separator: " ")
            for sentinel in sentinels {
                XCTAssertFalse(payload.contains(sentinel), "\(sentinel) leaked into \(event.name)")
            }
        }
    }

    /// A submission drives exactly one success event — the sheet does not
    /// re-emit what the client already reported, so nothing is double-counted.
    func test_a_submission_produces_exactly_one_terminal_event() async throws {
        let sink = RecordingAnalytics()
        let client = makeClient(transport: StubTransport(result: .success(5)), analytics: sink)
        _ = try await client.submit(report())

        XCTAssertEqual(sink.names.filter { $0 == "feedback_submission_succeeded" }.count, 1)
        XCTAssertEqual(sink.names.filter { $0 == "feedback_submission_failed" }.count, 0)
        XCTAssertEqual(sink.names.filter { $0 == "feedback_submission_started" }.count, 1)
    }

    func test_no_analytics_is_a_no_op() async throws {
        let client = FeedbackClient(
            transport: StubTransport(result: .success(3)),
            deviceInfo: DeviceInfo(
                appName: "A", appVersion: "1", buildNumber: "1",
                model: "m", osName: "macOS", osVersion: "15.1"
            )
        )
        let issue = try await client.submit(report())
        XCTAssertEqual(issue, 3)
    }
}

private struct SampleError: Error, Sendable {}

private struct StubTransport: FeedbackTransport {
    let result: Result<Int, any Error & Sendable>
    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int {
        try result.get()
    }
}
