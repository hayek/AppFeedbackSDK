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

        for key in report.extraFields.keys.sorted(by: Self.codePointOrder) {
            body += "\n\n**\(key):**\n\(report.extraFields[key]!)"
        }

        if !uploaded.isEmpty {
            body += "\n\n\(BodyMarker.attachmentsOpen)\n\(BodyMarker.attachmentsHeader)\n"
            for a in uploaded {
                let prefix = a.mimeType.hasPrefix("image/") ? "!" : ""
                let size = DeterministicByteCount.string(a.sizeBytes)
                body += "\n\(prefix)[\(a.filename)](\(a.url.absoluteString)) — \(a.mimeType), \(size)\n"
            }
            body += "\n\(BodyMarker.attachmentsClose)"
        }

        body += "\n\n\(BodyMarker.horizontalRule)\n\(BodyMarker.votesFooter)"
        return body
    }

    /// Deterministic ordering for `extraFields` keys: ascending by Unicode
    /// scalar value (code point). Pinned in the wire spec so the Kotlin/TS
    /// ports replicate it exactly — each language's default string sort is
    /// *not* guaranteed to equal code-point order for non-ASCII keys.
    static func codePointOrder(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
    }

    /// Returns the label strings to apply to the created GitHub issue.
    ///
    /// - Parameter type: The submission's type.
    /// - Returns: `[type.rawValue, "user-submitted"]`. Both labels are part of
    ///   the contract — the inbox uses them to categorize and filter.
    public static func labels(for type: FeedbackType) -> [String] {
        [type.rawValue, userSubmittedLabel]
    }

    /// Renders the machine-readable `source-meta-v1` block that carries a
    /// synthesized issue's origin through GitHub and back into ``IssueBodyParser``.
    /// Emits one `key: value` line per non-nil field (always at least `source`).
    /// The block is HTML-comment-fenced so it's invisible in rendered Markdown.
    ///
    /// - Parameter source: the feedback source raw value ("sdk" | "app-store" | "email").
    public static func sourceMetadataBlock(
        source: String,
        rating: Int? = nil,
        reviewerNickname: String? = nil,
        territory: String? = nil,
        reviewId: String? = nil,
        reviewCreatedAt: String? = nil,
        fromAddress: String? = nil,
        messageId: String? = nil
    ) -> String {
        var lines = ["\(BodyMarker.sourceKey): \(source)"]
        if let rating { lines.append("\(BodyMarker.ratingKey): \(rating)") }
        if let reviewerNickname { lines.append("\(BodyMarker.reviewerNicknameKey): \(reviewerNickname)") }
        if let territory { lines.append("\(BodyMarker.territoryKey): \(territory)") }
        if let reviewId { lines.append("\(BodyMarker.reviewIdKey): \(reviewId)") }
        if let reviewCreatedAt { lines.append("\(BodyMarker.reviewCreatedAtKey): \(reviewCreatedAt)") }
        if let fromAddress { lines.append("\(BodyMarker.fromAddressKey): \(fromAddress)") }
        if let messageId { lines.append("\(BodyMarker.messageIdKey): \(messageId)") }
        return "\(BodyMarker.sourceMetaOpen)\n" + lines.joined(separator: "\n") + "\n\(BodyMarker.sourceMetaClose)"
    }

    /// Neutralizes any `source-meta-v1` fences embedded in *untrusted* free text
    /// so they can't be parsed back as authoritative source metadata.
    ///
    /// `IssueBodyParser.applySourceMetadata` reads the FIRST `source-meta-v1`
    /// block in a body. When an inbox composes an issue from attacker-controlled
    /// input (e.g. an inbound email body) and appends its own trusted block
    /// afterwards, a fake block pasted into the free text would win and let the
    /// reporter spoof the source/rating (e.g. mis-badge an email as a 5-star
    /// App Store review). Callers MUST pass any untrusted free text through this
    /// before composing it ahead of a trusted `sourceMetadataBlock`.
    ///
    /// The neutralization is a minimal, reversible-looking edit: it zero-width
    /// "defangs" the HTML-comment open/close fences by inserting a marker the
    /// parser won't recognise, so the text remains human-readable but no longer
    /// forms a parseable block. Both the open and close fences are defanged, and
    /// any case variation of the literal fence is matched.
    public static func neutralizeSourceMetaFences(in untrustedText: String) -> String {
        var text = untrustedText
        for fence in [BodyMarker.sourceMetaOpen, BodyMarker.sourceMetaClose] {
            // Break the literal `<!-- ... -->` so `range(of:)` in the parser can
            // no longer find it, while keeping the text legible to a human.
            let defanged = fence.replacingOccurrences(of: "<!--", with: "<!-\u{200B}-")
            text = text.replacingOccurrences(
                of: fence, with: defanged, options: [.caseInsensitive])
        }
        return text
    }
}
