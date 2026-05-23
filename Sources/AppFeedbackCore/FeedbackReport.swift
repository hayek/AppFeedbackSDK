import Foundation

/// A single user-supplied feedback submission.
///
/// Reports are value types — build one per submission and hand it to
/// ``FeedbackClient/submit(_:)``. The transport renders this together with
/// the active ``DeviceInfo`` into the on-wire issue body (see <doc:BodyFormat>).
///
/// ```swift
/// let report = FeedbackReport(
///     type: .bug,
///     title: "Crash on launch",
///     description: "Steps to reproduce…",
///     contactEmail: "user@example.com"
/// )
/// let issueNumber = try await feedback.submit(report)
/// ```
public struct FeedbackReport: Sendable, Equatable {

    /// Whether this submission is a bug report or a feature request.
    ///
    /// Drives the issue's label set: see ``IssueBodyFormatter/labels(for:)``.
    public var type: FeedbackType

    /// One-line summary, used as the GitHub issue title.
    public var title: String

    /// Free-form body content. Appears at the top of the issue, above the
    /// auto-generated device-information block.
    public var description: String

    /// Optional reply-to address. When non-`nil` and non-empty, the formatter
    /// emits a `**Contact Email:**` block in the issue body so the inbox can
    /// surface it as a column.
    public var contactEmail: String?

    /// Additional named fields to include in the body.
    ///
    /// Each entry is rendered as a `**Key:**\nValue` block, sorted by key,
    /// between the device-info block and the email block. The AppFeedback
    /// inbox does not currently extract custom keys into typed columns, but
    /// they remain visible in the issue body for triage.
    public var extraFields: [String: String]

    /// Files attached to this submission. The SDK validates count + size + MIME
    /// type, image-preprocesses, then uploads to a `feedback-attachments` branch
    /// of the inbox repo. URLs are embedded in the issue body inside a
    /// `<!-- attachments-v1 -->` marker block.
    public var attachments: [FeedbackAttachment]

    /// Builds a report.
    ///
    /// - Parameters:
    ///   - type: Bug or feature request — see ``FeedbackType``.
    ///   - title: GitHub issue title.
    ///   - description: Free-form body content.
    ///   - contactEmail: Optional reply-to address. Defaults to `nil`.
    ///   - extraFields: Optional dictionary of custom k/v rendered after the
    ///     device-info block. Defaults to empty.
    ///   - attachments: Optional array of files to attach. Defaults to empty.
    public init(
        type: FeedbackType,
        title: String,
        description: String,
        contactEmail: String? = nil,
        extraFields: [String: String] = [:],
        attachments: [FeedbackAttachment] = []
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.contactEmail = contactEmail
        self.extraFields = extraFields
        self.attachments = attachments
    }
}
