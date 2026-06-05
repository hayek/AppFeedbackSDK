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
