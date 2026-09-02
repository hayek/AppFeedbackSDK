import XCTest
@testable import AppFeedbackCore

/// `name` and `parameters` are the declared stable contract — adopters forward
/// them straight to Firebase/Mixpanel and build dashboards on the strings. A
/// rename has to fail a test, not surface as a silently-empty chart.
final class FeedbackEventTests: XCTestCase {

    private let allEvents: [FeedbackEvent] = [
        .sheetPresented,
        .typeSelected(.bug),
        .attachmentAdded(source: .photoLibrary),
        .attachmentRejected(.fileTooLarge(filename: "x.png", sizeBytes: 9, limit: 1)),
        .validationFailed(missingFields: [.title, .description]),
        .submissionStarted(.bug, attachmentCount: 2, hasContactEmail: true),
        .submissionSucceeded(.featureRequest, issueNumber: 123),
        .submissionFailed(.bug, error: FeedbackSubmissionError.invalidResponse),
        .cancelled,
        .ratingPromptRequested,
        .ratingPromptSuppressed(reason: .notPraise),
    ]

    func test_names_are_pinned() {
        XCTAssertEqual(FeedbackEvent.sheetPresented.name, "feedback_sheet_presented")
        XCTAssertEqual(FeedbackEvent.typeSelected(.bug).name, "feedback_type_selected")
        XCTAssertEqual(FeedbackEvent.attachmentAdded(source: .files).name, "feedback_attachment_added")
        XCTAssertEqual(FeedbackEvent.cancelled.name, "feedback_cancelled")
        XCTAssertEqual(
            FeedbackEvent.attachmentRejected(.totalSizeTooLarge(totalBytes: 9, limit: 1)).name,
            "feedback_attachment_rejected"
        )
        XCTAssertEqual(
            FeedbackEvent.validationFailed(missingFields: [.title]).name,
            "feedback_validation_failed"
        )
        XCTAssertEqual(
            FeedbackEvent.submissionStarted(.bug, attachmentCount: 0, hasContactEmail: false).name,
            "feedback_submission_started"
        )
        XCTAssertEqual(
            FeedbackEvent.submissionFailed(.bug, error: SampleError()).name,
            "feedback_submission_failed"
        )
        XCTAssertEqual(FeedbackEvent.ratingPromptRequested.name, "feedback_rating_prompt_requested")
        XCTAssertEqual(
            FeedbackEvent.ratingPromptSuppressed(reason: .notPraise).name,
            "feedback_rating_prompt_suppressed"
        )
    }

    /// Firebase rejects or truncates outside these bounds, so a name that
    /// violates them is a silently dropped event in production.
    func test_names_satisfy_firebase_constraints() {
        for event in allEvents {
            let name = event.name
            XCTAssertLessThanOrEqual(name.count, 40, name)
            XCTAssertGreaterThanOrEqual(name.count, 1, name)
            XCTAssertTrue(name.first?.isLetter == true, "must start with a letter: \(name)")
            XCTAssertTrue(
                name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                "alphanumeric + underscore only: \(name)"
            )
            for reserved in ["firebase_", "google_", "ga_"] {
                XCTAssertFalse(name.hasPrefix(reserved), name)
            }
        }
    }

    /// Firebase caps string parameter *values* at 100 characters and parameter
    /// names at 40.
    func test_parameters_satisfy_firebase_constraints() {
        for event in allEvents {
            for (key, value) in event.parameters {
                XCTAssertLessThanOrEqual(key.count, 40, key)
                XCTAssertTrue(
                    key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                    "bad parameter name: \(key)"
                )
                XCTAssertLessThanOrEqual(value.count, 100, "\(key)=\(value)")
            }
            XCTAssertLessThanOrEqual(event.parameters.count, 25, event.name)
        }
    }

    func test_parameters_are_pinned() {
        XCTAssertEqual(FeedbackEvent.typeSelected(.featureRequest).parameters, ["type": "feature-request"])
        XCTAssertEqual(FeedbackEvent.attachmentAdded(source: .paste).parameters, ["source": "paste"])
        XCTAssertEqual(
            FeedbackEvent.submissionSucceeded(.bug, issueNumber: 42).parameters,
            ["type": "bug", "issue_number": "42"]
        )
        XCTAssertEqual(
            FeedbackEvent.submissionStarted(.bug, attachmentCount: 3, hasContactEmail: false).parameters,
            ["type": "bug", "attachment_count": "3", "has_email": "false"]
        )
        XCTAssertEqual(FeedbackEvent.sheetPresented.parameters, [:])
    }

    /// Built from stable identifiers, never `theme.copy` — otherwise a German
    /// adopter reports "Titel,Beschreibung" and the funnel step fragments by
    /// locale and by theme.
    func test_validation_failure_carries_stable_identifiers_not_display_copy() {
        let event = FeedbackEvent.validationFailed(missingFields: [.title, .description])
        XCTAssertEqual(event.parameters, ["missing_fields": "title,description"])
    }

    func test_error_kind_is_stable_and_never_the_description() {
        func kind(_ error: any Error & Sendable) -> String? {
            FeedbackEvent.submissionFailed(.bug, error: error).parameters["error_kind"]
        }
        XCTAssertEqual(kind(FeedbackSubmissionError.invalidResponse), "invalid_response")
        XCTAssertEqual(kind(FeedbackSubmissionError.httpStatus(404, body: "nope")), "http_404")
        XCTAssertEqual(kind(FeedbackSubmissionError.decoding(SampleError())), "decoding")
        XCTAssertEqual(kind(FeedbackSubmissionError.transport(SampleError())), "network")
        XCTAssertEqual(
            kind(FeedbackSubmissionError.attachmentValidation(.tooManyAttachments(limit: 3, got: 9))),
            "attachment_validation"
        )
        XCTAssertEqual(
            kind(FeedbackSubmissionError.attachmentUpload(filename: "secret.pdf", underlying: SampleError())),
            "attachment_upload"
        )
        XCTAssertEqual(kind(SampleError()), "other")
    }

    /// The upload error interpolates the user's filename into its description,
    /// and the transport error can name the relay host. Neither may reach a
    /// third-party analytics vendor.
    func test_failure_event_never_leaks_the_error_description() {
        let event = FeedbackEvent.submissionFailed(
            .bug,
            error: FeedbackSubmissionError.attachmentUpload(filename: "passport-scan.pdf", underlying: SampleError())
        )
        let payload = event.parameters.values.joined(separator: " ") + " " + event.name
        XCTAssertFalse(payload.contains("passport-scan"))
        XCTAssertFalse(payload.contains("Failed to upload"))
    }

    /// Every attachment error case carries a filename. The rejection event must
    /// emit a reason token and nothing else.
    func test_attachment_rejection_never_leaks_the_filename() {
        let cases: [FeedbackAttachmentError] = [
            .tooManyAttachments(limit: 3, got: 9),
            .fileTooLarge(filename: "passport-scan.pdf", sizeBytes: 9, limit: 1),
            .totalSizeTooLarge(totalBytes: 99, limit: 1),
            .unsupportedMimeType(filename: "passport-scan.pdf", mimeType: "application/pdf"),
            .imageProcessingFailed(filename: "passport-scan.pdf"),
        ]
        let expected = [
            "too_many_attachments", "file_too_large", "total_size_too_large",
            "unsupported_mime_type", "image_processing_failed",
        ]
        for (error, reason) in zip(cases, expected) {
            let event = FeedbackEvent.attachmentRejected(error)
            XCTAssertEqual(event.parameters, ["reason": reason])
            XCTAssertFalse(event.parameters.values.joined().contains("passport-scan"))
        }
    }

    func test_equality_is_over_the_stable_contract() {
        XCTAssertEqual(FeedbackEvent.typeSelected(.bug), FeedbackEvent.typeSelected(.bug))
        XCTAssertNotEqual(FeedbackEvent.typeSelected(.bug), FeedbackEvent.typeSelected(.featureRequest))
        XCTAssertNotEqual(FeedbackEvent.cancelled, FeedbackEvent.sheetPresented)
    }
}

private struct SampleError: Error, Sendable {}
