import Foundation

/// The string literals that make up the wire contract between
/// ``IssueBodyFormatter`` and ``IssueBodyParser``.
///
/// Both halves of the contract read from this file, so renaming a marker
/// here updates both sides atomically — preventing the silent drift the
/// SDK was created to fix.
enum BodyMarker {
    static let deviceHeader = "Device Information:"
    static let appLabel = "App:"
    static let appVersionLabel = "App Version:"
    static let deviceLabel = "Device:"
    static let osVersionSuffix = " Version:"
    static let contactEmailLabel = "Contact Email:"
    static let horizontalRule = "---"
    static let votesFooter = "👍 Votes: 0"
    static let attachmentsOpen = "<!-- attachments-v1 -->"
    static let attachmentsClose = "<!-- /attachments-v1 -->"
    static let attachmentsHeader = "## Attachments"

    /// HTML-comment fences wrapping the machine-readable source metadata block.
    /// The fence lines themselves are HTML comments, but the `key: value` content
    /// lines inside render visibly in the issue body (like the device-info block).
    /// The block survives the GitHub round-trip and is parsed back by ``IssueBodyParser``.
    static let sourceMetaOpen = "<!-- source-meta-v1 -->"
    static let sourceMetaClose = "<!-- /source-meta-v1 -->"

    /// Keys written inside the `source-meta-v1` block, one `key: value` per line.
    /// `source` is always present; the rest are populated per source type.
    static let sourceKey = "source"
    static let ratingKey = "rating"
    static let reviewerNicknameKey = "reviewerNickname"
    static let territoryKey = "territory"
    static let reviewIdKey = "reviewId"
    static let reviewCreatedAtKey = "reviewCreatedAt"
    static let fromAddressKey = "fromAddress"
    static let messageIdKey = "messageId"

    /// OS names recognised in the `<osName> Version:` line, written by
    /// ``DeviceInfo/renderForIssueBody()`` and read by ``IssueBodyParser/parse(_:)``.
    static let recognisedOSNames = [
        "OS", "macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS",
        "Android", "Windows", "Linux", "Web", "ChromeOS",
    ]

    /// Regex that matches a line starting with any `recognisedOSNames` entry
    /// followed by ` Version:`. Used by the parser to extract the OS version.
    static let osVersionPattern = "^(\(recognisedOSNames.joined(separator: "|"))) Version:"
}
