import Foundation

/// Per-attachment record after the SDK has uploaded bytes to GitHub. Drives
/// the body renderer and is the parsed counterpart on the inbox side
/// (`ParsedAttachment`).
public struct UploadedAttachment: Sendable, Equatable {
    public let filename: String
    public let mimeType: String
    public let sizeBytes: Int
    public let url: URL

    public init(filename: String, mimeType: String, sizeBytes: Int, url: URL) {
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.url = url
    }
}

/// Renders a ``FeedbackReport`` + ``DeviceInfo`` into the exact issue body
/// shape that ``IssueBodyParser/parse(_:)`` understands.
///
/// This is one half of the wire contract with the AppFeedback inbox — the
/// other being ``IssueBodyParser``. Both halves ship in the same module so the
/// two ends can never drift. See <doc:BodyFormat> for the full spec.
///
/// ```swift
/// let body = IssueBodyFormatter.format(report: report, deviceInfo: info)
/// let labels = IssueBodyFormatter.labels(for: report.type)
/// // body and labels go into the GitHub create-issue payload.
/// ```
///
/// You normally don't call this directly — ``GitHubDirectTransport`` invokes
/// it for every submission. It's `public` so custom transports (relay
/// servers, mocks) can produce inbox-compatible output.
public enum IssueBodyFormatter {

    /// The marker label that identifies an issue as user-submitted (as
    /// opposed to created via the GitHub web UI). The AppFeedback inbox
    /// filters by this label so internal triage notes don't appear as
    /// "feedback".
    public static let userSubmittedLabel = "user-submitted"

    /// Builds the issue body string for a given report.
    ///
    /// - Parameters:
    ///   - report: The user submission, including the optional contact email
    ///     and any custom `extraFields`.
    ///   - deviceInfo: The metadata block, rendered inline via
    ///     ``DeviceInfo/renderForIssueBody()``.
    /// - Returns: A multi-line UTF-8 string ready to drop into the GitHub
    ///   create-issue payload's `body` field.
    public static func format(report: FeedbackReport, deviceInfo: DeviceInfo) -> String {
        format(report: report, deviceInfo: deviceInfo, uploaded: [])
    }

    public static func format(
        report: FeedbackReport,
        deviceInfo: DeviceInfo,
        uploaded: [UploadedAttachment]
    ) -> String {
        var body = report.description

        body += "\n\n\(BodyMarker.horizontalRule)\n**\(BodyMarker.deviceHeader)**\n\(deviceInfo.renderForIssueBody())"

        if let email = report.contactEmail, !email.isEmpty {
            body += "\n\n**\(BodyMarker.contactEmailLabel)**\n\(email)"
        }

        for key in report.extraFields.keys.sorted() {
            body += "\n\n**\(key):**\n\(report.extraFields[key]!)"
        }

        if !uploaded.isEmpty {
            body += "\n\n\(BodyMarker.attachmentsOpen)\n\(BodyMarker.attachmentsHeader)\n"
            for a in uploaded {
                let prefix = a.mimeType.hasPrefix("image/") ? "!" : ""
                let size = ByteCountFormatter.string(fromByteCount: Int64(a.sizeBytes), countStyle: .file)
                body += "\n\(prefix)[\(a.filename)](\(a.url.absoluteString)) — \(a.mimeType), \(size)\n"
            }
            body += "\n\(BodyMarker.attachmentsClose)"
        }

        body += "\n\n\(BodyMarker.horizontalRule)\n\(BodyMarker.votesFooter)"
        return body
    }

    /// Returns the label strings to apply to the created GitHub issue.
    ///
    /// - Parameter type: The submission's type.
    /// - Returns: `[type.rawValue, "user-submitted"]`. Both labels are part of
    ///   the contract — the inbox uses them to categorize and filter.
    public static func labels(for type: FeedbackType) -> [String] {
        [type.rawValue, userSubmittedLabel]
    }
}
