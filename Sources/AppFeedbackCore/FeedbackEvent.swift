/// Something that happened inside the SDK, reported to a ``FeedbackAnalytics`` sink.
///
/// ## The stable contract is `name` and `parameters`
///
/// ``name`` and ``parameters`` are what adopters build dashboards on, and they
/// are covered by tests that fail on a rename. Forwarding is one line:
///
/// ```swift
/// func record(_ event: FeedbackEvent) {
///     Analytics.logEvent(event.name, parameters: event.parameters)
/// }
/// ```
///
/// ## New cases arrive in minor releases
///
/// The vocabulary grows. This package is distributed as source, so a `switch`
/// over `FeedbackEvent` **without** a `default:` becomes a *compile error* on the
/// next minor release — not a warning, and `@unknown default` does not apply,
/// since that is for library-evolution-enabled binary frameworks. Either forward
/// `name`/`parameters` as above, or always write a `default:`:
///
/// ```swift
/// switch event {
/// case .submissionSucceeded(let type, let issue): …
/// default: break
/// }
/// ```
///
/// ## What is deliberately absent
///
/// There is no `userRated` and no `ratingPromptShown`. `RequestReviewAction`
/// returns `Void`, the system decides silently whether to show anything, and
/// Apple exposes no way to learn either fact. ``ratingPromptRequested`` means the
/// SDK asked; it does not mean a prompt appeared. Do not build a conversion
/// metric on it.
public enum FeedbackEvent: Sendable {

    /// The sheet appeared. Emitted once per presentation.
    case sheetPresented

    /// The user changed the feedback type. Re-tapping the selected card is silent,
    /// and the initial default is not a selection — read the type from
    /// ``submissionStarted(_:attachmentCount:hasContactEmail:)`` instead of
    /// inferring it here.
    case typeSelected(FeedbackType)

    /// An attachment was added to the pending list. Emitted once per file, and
    /// *before* validation runs — an oversized file produces this and then
    /// ``attachmentRejected(_:)``, so this is not a count of accepted files.
    case attachmentAdded(source: AttachmentSource)

    /// An attachment was refused by validation, which blocks the submit button.
    /// Carries the reason only — every ``FeedbackAttachmentError`` case holds a
    /// filename, and filenames stay out of analytics.
    ///
    /// Emitted per *rejection*, not per file: re-validating with the same
    /// failure stays quiet, while a change of reason — remove the oversized file
    /// and an unsupported type is next — reports again.
    case attachmentRejected(FeedbackAttachmentError)

    /// Submit was tapped with required fields empty.
    case validationFailed(missingFields: [FeedbackField])

    /// A submission is about to be handed to the transport.
    case submissionStarted(FeedbackType, attachmentCount: Int, hasContactEmail: Bool)

    /// The transport accepted the report.
    case submissionSucceeded(FeedbackType, issueNumber: Int)

    /// The transport threw. The error is carried for your own logging; only a
    /// stable `error_kind` token reaches ``parameters``, because
    /// `localizedDescription` can contain an attachment filename or a host name.
    case submissionFailed(FeedbackType, error: any Error & Sendable)

    /// The sheet closed without a successful submission.
    ///
    /// There is no Cancel button — this means *left without submitting*, whether
    /// by swipe, Escape, or the host app dismissing the sheet. An app terminated
    /// with the sheet open emits nothing.
    case cancelled

    /// The SDK asked the system to show the App Store rating prompt. Whether one
    /// appeared is not observable; see the type-level note.
    case ratingPromptRequested

    /// A successful submission did not lead to a rating prompt.
    case ratingPromptSuppressed(reason: RatingPromptSuppressionReason)

    /// The vendor-facing event name: `feedback_`-prefixed snake_case, within
    /// Firebase's 40-character limit and character set.
    public var name: String {
        switch self {
        case .sheetPresented: return "feedback_sheet_presented"
        case .typeSelected: return "feedback_type_selected"
        case .attachmentAdded: return "feedback_attachment_added"
        case .attachmentRejected: return "feedback_attachment_rejected"
        case .validationFailed: return "feedback_validation_failed"
        case .submissionStarted: return "feedback_submission_started"
        case .submissionSucceeded: return "feedback_submission_succeeded"
        case .submissionFailed: return "feedback_submission_failed"
        case .cancelled: return "feedback_cancelled"
        case .ratingPromptRequested: return "feedback_rating_prompt_requested"
        case .ratingPromptSuppressed: return "feedback_rating_prompt_suppressed"
        }
    }

    /// The vendor-facing payload. Values are strings so the dictionary stays
    /// `Sendable` and converts implicitly to `[String: Any]`; all are within
    /// Firebase's 100-character value limit.
    ///
    /// Never contains user-authored content.
    public var parameters: [String: String] {
        switch self {
        case .sheetPresented, .cancelled, .ratingPromptRequested:
            return [:]
        case .typeSelected(let type):
            return ["type": type.rawValue]
        case .attachmentAdded(let source):
            return ["source": source.rawValue]
        case .attachmentRejected(let error):
            return ["reason": Self.reason(for: error)]
        case .validationFailed(let fields):
            return ["missing_fields": fields.map(\.rawValue).joined(separator: ",")]
        case .submissionStarted(let type, let count, let hasEmail):
            return [
                "type": type.rawValue,
                "attachment_count": String(count),
                "has_email": hasEmail ? "true" : "false",
            ]
        case .submissionSucceeded(let type, let issueNumber):
            return ["type": type.rawValue, "issue_number": String(issueNumber)]
        case .submissionFailed(let type, let error):
            return ["type": type.rawValue, "error_kind": Self.kind(for: error)]
        case .ratingPromptSuppressed(let reason):
            return ["reason": reason.rawValue]
        }
    }

    /// A short, stable token per failure mode.
    ///
    /// Deliberately not `localizedDescription`: `attachmentUpload` interpolates
    /// the user's filename into its description and `transport` forwards
    /// `URLError.localizedDescription`, which can name the relay host. Neither
    /// belongs in a third-party analytics vendor, and both would exceed
    /// Firebase's 100-character value limit.
    private static func kind(for error: any Error) -> String {
        guard let error = error as? FeedbackSubmissionError else { return "other" }
        switch error {
        case .invalidResponse: return "invalid_response"
        case .httpStatus(let code, _): return "http_\(code)"
        case .decoding: return "decoding"
        case .transport: return "network"
        case .attachmentValidation: return "attachment_validation"
        case .attachmentUpload: return "attachment_upload"
        }
    }

    private static func reason(for error: FeedbackAttachmentError) -> String {
        switch error {
        case .tooManyAttachments: return "too_many_attachments"
        case .fileTooLarge: return "file_too_large"
        case .totalSizeTooLarge: return "total_size_too_large"
        case .unsupportedMimeType: return "unsupported_mime_type"
        case .imageProcessingFailed: return "image_processing_failed"
        }
    }
}

/// Equality is over ``name`` and ``parameters`` — the stable contract, and what
/// a test asserting "these events fired" actually means. The
/// `any Error & Sendable` payload rules out a synthesized conformance anyway.
///
/// It is deliberately coarser than the associated values: two failures of the
/// same kind compare equal even with different underlying errors, and two
/// rejections of the same kind compare equal even for different files. If your
/// test needs the carried `Error` itself, match the case rather than comparing
/// events.
extension FeedbackEvent: Equatable {
    public static func == (lhs: FeedbackEvent, rhs: FeedbackEvent) -> Bool {
        lhs.name == rhs.name && lhs.parameters == rhs.parameters
    }
}
