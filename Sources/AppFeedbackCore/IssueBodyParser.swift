import Foundation

/// Canonical ASCII whitespace set the parser trims, per the wire-format spec:
/// `{ U+0009, U+000A, U+000B, U+000C, U+000D, U+0020 }` and nothing else.
/// Deliberately NOT `.whitespacesAndNewlines`, whose Unicode-defined membership
/// (NBSP, NEL, BOM, …) diverges from Kotlin/TS `trim` semantics. Non-ASCII
/// whitespace is preserved verbatim, identically across all three ports.
private let asciiWhitespace = CharacterSet(charactersIn: "\u{09}\u{0A}\u{0B}\u{0C}\u{0D}\u{20}")

/// A single attachment entry extracted from the `<!-- attachments-v1 -->` block
/// in a GitHub issue body.
public struct ParsedAttachment: Sendable, Equatable {
    public let filename: String
    public let mimeType: String
    public let url: URL
    /// Approximate file size, derived from the human-formatted suffix in the
    /// body (e.g. "312 KB" → 312_000). Round-trips lossy by design — the
    /// canonical byte count lives in the downloaded file's size on disk.
    public let sizeBytes: Int?

    public init(filename: String, mimeType: String, url: URL, sizeBytes: Int?) {
        self.filename = filename
        self.mimeType = mimeType
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

/// The structured fields extracted from an issue body by ``IssueBodyParser``.
///
/// All metadata fields are optional because the SDK accepts hand-written or
/// legacy bodies that may be missing pieces. ``description`` is always
/// non-`nil` (defaults to the empty string) so callers don't have to handle
/// that case.
public struct ParsedFeedbackBody: Sendable, Equatable {

    /// Free-form body content above the device-information block.
    /// Horizontal rules (`---`) and the device block itself are stripped.
    public var description: String = ""

    /// Value of the `App:` line inside the device-information block.
    public var appName: String?

    /// Value of the `App Version:` line.
    public var appVersion: String?

    /// Value of the `Device:` line.
    public var device: String?

    /// Value of the `<osName> Version:` line for any recognised OS
    /// (`macOS`, `iOS`, `iPadOS`, `watchOS`, `tvOS`, `visionOS`, `Android`,
    /// `Windows`, `Linux`, `Web`, `ChromeOS`, or the generic `OS`).
    public var osVersion: String?

    /// Reply-to address from the `**Contact Email:**` block.
    public var email: String?

    /// Attachments extracted from the `<!-- attachments-v1 -->` block.
    /// Empty when no block is present or the block contains no valid entries.
    public var attachments: [ParsedAttachment] = []

    /// Machine-readable source metadata from the `source-meta-v1` block.
    /// `source` is the originating feedback source ("sdk" | "app-store" | "email");
    /// nil when the block is absent (legacy SDK issues) — callers default to "sdk".
    public var source: String?
    /// App Store star rating (1…5) when `source == "app-store"`, else nil.
    public var rating: Int?
    public var reviewerNickname: String?
    public var territory: String?
    public var reviewId: String?
    public var reviewCreatedAt: String?
    public var fromAddress: String?
    public var messageId: String?

    /// Builds a parsed result with every field specified. Mostly useful for
    /// tests; production code calls ``IssueBodyParser/parse(_:)``.
    public init(
        description: String = "",
        appName: String? = nil,
        appVersion: String? = nil,
        device: String? = nil,
        osVersion: String? = nil,
        email: String? = nil,
        attachments: [ParsedAttachment] = [],
        source: String? = nil,
        rating: Int? = nil,
        reviewerNickname: String? = nil,
        territory: String? = nil,
        reviewId: String? = nil,
        reviewCreatedAt: String? = nil,
        fromAddress: String? = nil,
        messageId: String? = nil
    ) {
        self.description = description
        self.appName = appName
        self.appVersion = appVersion
        self.device = device
        self.osVersion = osVersion
        self.email = email
        self.attachments = attachments
        self.source = source
        self.rating = rating
        self.reviewerNickname = reviewerNickname
        self.territory = territory
        self.reviewId = reviewId
        self.reviewCreatedAt = reviewCreatedAt
        self.fromAddress = fromAddress
        self.messageId = messageId
    }
}

/// The inverse of ``IssueBodyFormatter``: pulls structured fields out of a
/// GitHub issue body produced by the AppFeedback SDK (or a hand-written body
/// following the same shape).
///
/// ```swift
/// let parsed = IssueBodyParser.parse(githubIssue.body ?? "")
/// parsed.appName       // "AcmeApp"
/// parsed.device        // "iPhone15,2"
/// parsed.osVersion     // "Version 18.2 (Build 22C150)"
/// parsed.email         // "user@example.com"
/// parsed.description   // body above the device block
/// ```
///
/// This type is the single source of truth for parsing — the AppFeedback inbox
/// app depends on it so the two ends of the wire contract can't drift.
public enum IssueBodyParser {

    /// Parses a raw GitHub issue body into structured fields.
    ///
    /// The parser is tolerant of variations seen in hand-written bodies — see
    /// <doc:BodyFormat>'s *Resilience* section for the full list. If a field
    /// can't be found, the corresponding property on the returned
    /// ``ParsedFeedbackBody`` is `nil`.
    ///
    /// - Parameter raw: The full UTF-8 issue body as returned by GitHub.
    /// - Returns: A ``ParsedFeedbackBody`` with whatever could be extracted.
    public static func parse(_ raw: String) -> ParsedFeedbackBody {
        var result = ParsedFeedbackBody()
        var descLines: [String] = []
        var inDevice = false
        var expectEmail = false

        // Normalize line endings so CRLF bodies (e.g. authored in the GitHub web
        // UI) parse identically to LF. `.whitespaces` does not strip `\r`.
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalized.components(separatedBy: "\n") {
            // Strip bold markers anywhere on the line so `**Contact Email:** foo`
            // and `**Device Information:**` both reduce to the same shape we
            // match below. `trimmed` is used only for marker detection — the
            // original `line` is what we append to the description, so removing
            // `**` here can't corrupt user-formatted body text.
            let trimmed = line.trimmingCharacters(in: asciiWhitespace)
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: asciiWhitespace)

            if trimmed == BodyMarker.deviceHeader {
                inDevice = true
                continue
            }

            guard inDevice else {
                descLines.append(line)
                continue
            }

            if expectEmail {
                if !trimmed.isEmpty && trimmed.contains("@") { result.email = trimmed }
                expectEmail = false
                continue
            }

            // `App Version:` must be checked before `App:` (the latter is a prefix of the former).
            if let value = trimmed.value(after: BodyMarker.appVersionLabel) {
                result.appVersion = value
            } else if let value = trimmed.value(after: BodyMarker.appLabel) {
                result.appName = value
            } else if let value = trimmed.value(after: BodyMarker.deviceLabel) {
                result.device = value
            } else if Self.osVersionMatcher.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ) != nil {
                result.osVersion = trimmed
                    .components(separatedBy: ":")
                    .dropFirst()
                    .joined(separator: ":")
                    .trimmingCharacters(in: asciiWhitespace)
            } else if trimmed == BodyMarker.contactEmailLabel {
                expectEmail = true
            } else if let value = trimmed.value(after: BodyMarker.contactEmailLabel) {
                if value.contains("@") { result.email = value } else { expectEmail = true }
            }
        }

        result.description = descLines
            .filter { $0.trimmingCharacters(in: asciiWhitespace) != BodyMarker.horizontalRule }
            .joined(separator: "\n")
            .trimmingCharacters(in: asciiWhitespace)

        result.attachments = parseAttachments(in: normalized)
        applySourceMetadata(in: normalized, to: &result)
        return result
    }

    // Compiled once at module load. NSRegularExpression is thread-safe for
    // matching — only initialization needs synchronization.
    private static let osVersionMatcher: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: BodyMarker.osVersionPattern, options: [.caseInsensitive])
    }()
}

private func parseAttachments(in raw: String) -> [ParsedAttachment] {
    guard let openRange = raw.range(of: BodyMarker.attachmentsOpen) else { return [] }
    let afterOpen = openRange.upperBound
    let end = raw.range(of: BodyMarker.attachmentsClose, range: afterOpen..<raw.endIndex)?.lowerBound ?? raw.endIndex
    let block = raw[afterOpen..<end]

    var results: [ParsedAttachment] = []
    for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: asciiWhitespace)
        guard let parsed = parseAttachmentLine(line) else { continue }
        results.append(parsed)
    }
    return results
}

private func parseAttachmentLine(_ line: String) -> ParsedAttachment? {
    // Image: ![name](url) optional " — mime, size"
    // File:  [name](url)  optional " — mime, size"
    let imagePrefix = "!["
    let filePrefix = "["
    var working = line
    if working.hasPrefix(imagePrefix) {
        working.removeFirst(imagePrefix.count)
    } else if working.hasPrefix(filePrefix) {
        working.removeFirst(filePrefix.count)
    } else {
        return nil
    }

    guard let nameEnd = working.range(of: "](") else { return nil }
    let filename = String(working[..<nameEnd.lowerBound])
    let afterName = working[nameEnd.upperBound...]
    guard let urlEnd = afterName.firstIndex(of: ")") else { return nil }
    // Attachment URLs are assumed to be valid absolute URLs (real GitHub
    // attachment URLs always are); a malformed url is skipped. MIME is inferred
    // from the raw url text below so it matches the Kotlin/TS ports.
    let urlString = String(afterName[..<urlEnd])
    guard let url = URL(string: urlString) else { return nil }
    let rest = afterName[afterName.index(after: urlEnd)...].trimmingCharacters(in: asciiWhitespace)

    var mime: String?
    var size: Int?
    if rest.hasPrefix("—") {
        let suffix = rest.dropFirst().trimmingCharacters(in: asciiWhitespace)
        let parts = suffix.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: asciiWhitespace) }
        if let first = parts.first, !first.isEmpty { mime = first }
        if parts.count > 1 { size = IssueBodyParser.parseHumanByteCount(parts[1]) }
    }

    let resolvedMime = mime ?? IssueBodyParser.inferMimeFromURL(urlString)

    return ParsedAttachment(filename: filename, mimeType: resolvedMime, url: url, sizeBytes: size)
}

private func applySourceMetadata(in raw: String, to result: inout ParsedFeedbackBody) {
    guard let openRange = raw.range(of: BodyMarker.sourceMetaOpen) else { return }
    let afterOpen = openRange.upperBound
    let end = raw.range(of: BodyMarker.sourceMetaClose, range: afterOpen..<raw.endIndex)?.lowerBound ?? raw.endIndex
    let block = raw[afterOpen..<end]

    for rawLine in block.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = rawLine.trimmingCharacters(in: asciiWhitespace)
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<colon]).trimmingCharacters(in: asciiWhitespace)
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: asciiWhitespace)
        guard !value.isEmpty else { continue }
        switch key {
        case BodyMarker.sourceKey:            result.source = value
        case BodyMarker.ratingKey:            result.rating = Int(value)
        case BodyMarker.reviewerNicknameKey:  result.reviewerNickname = value
        case BodyMarker.territoryKey:         result.territory = value
        case BodyMarker.reviewIdKey:          result.reviewId = value
        case BodyMarker.reviewCreatedAtKey:   result.reviewCreatedAt = value
        case BodyMarker.fromAddressKey:       result.fromAddress = value
        case BodyMarker.messageIdKey:         result.messageId = value
        default:                              break
        }
    }
}

extension IssueBodyParser {
    /// ASCII-decimal magnitude grammar, per the wire-format spec:
    /// `^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$`. Tokens that don't match — e.g.
    /// `0x10`, `0b1010`, `0o17`, `0xAp2`, `Infinity`, `NaN` — are rejected so the
    /// size is treated as absent. Swift's `Double` accepts hex / hex-float forms,
    /// so we MUST gate on this regex before parsing to match Kotlin/TS.
    private static let decimalMagnitude: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")
    }()

    static func parseHumanByteCount(_ s: String) -> Int? {
        // Split on the FIRST ASCII space: magnitude is the substring before it,
        // unit is everything after with the canonical ASCII whitespace trimmed
        // from both ends (so `4000  KB` collapses to magnitude `4000`, unit `KB`).
        // Deliberately NOT `split(maxSplits:)`, which leaves the extra leading
        // space on the unit field and silently demotes `4000  KB` to bytes.
        let numStr: String
        let unit: String
        if let sp = s.firstIndex(of: " ") {
            // Trim the magnitude too (per the spec: the decimal grammar is checked
            // *after* canonical trimming), so e.g. "4\t KB" matches like TS does.
            numStr = String(s[..<sp]).trimmingCharacters(in: asciiWhitespace)
            unit = s[s.index(after: sp)...].trimmingCharacters(in: asciiWhitespace).uppercased()
        } else {
            numStr = s.trimmingCharacters(in: asciiWhitespace)
            unit = "B"
        }
        if numStr.isEmpty { return nil }
        // Reject any non-decimal token before native parsing (Swift `Double`
        // would otherwise accept `0x10` / hex-float and diverge from Kotlin/TS).
        guard decimalMagnitude.firstMatch(
            in: numStr, range: NSRange(numStr.startIndex..., in: numStr)
        ) != nil else { return nil }
        guard let num = Double(numStr), num.isFinite else { return nil }
        let mult: Double
        switch unit {
        case "KB": mult = 1_000
        case "MB": mult = 1_000_000
        case "GB": mult = 1_000_000_000
        default:   mult = 1   // BYTES, B, or unknown unit -> bytes
        }
        let scaled = num * mult
        guard scaled.isFinite, scaled >= 0, scaled <= 100_000_000_000_000 else { return nil }
        return Int(scaled)
    }

    /// Best-effort MIME from a URL's file extension. Uses the fixed, canonical
    /// extension→MIME table from the wire-format spec — identical to the Kotlin
    /// and TypeScript ports. Deliberately NOT `UTType`, whose membership varies
    /// by OS / installed type declarations and would diverge cross-platform.
    ///
    /// The extension is extracted **manually** (NOT `URL.pathExtension`, which
    /// returns the empty string for a final segment like `.png` and would wrongly
    /// fall back to octet-stream): strip `?query`/`#fragment`, take the last path
    /// segment, then lower-case everything after that segment's FINAL `.`. A
    /// dotfile segment such as `.png` therefore infers `image/png`.
    static func inferMimeFromURL(_ url: String) -> String {
        let path = url.prefix { $0 != "?" && $0 != "#" }
        let lastSegment = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let ext: String
        if let dot = lastSegment.lastIndex(of: ".") {
            ext = lastSegment[lastSegment.index(after: dot)...].lowercased()
        } else {
            ext = ""
        }
        switch ext {
        case "png":                return "image/png"
        case "jpg", "jpeg":        return "image/jpeg"
        case "gif":                return "image/gif"
        case "heic":               return "image/heic"
        case "webp":               return "image/webp"
        case "pdf":                return "application/pdf"
        case "log", "txt", "text": return "text/plain"
        case "json":               return "application/json"
        case "xml":                return "application/xml"
        case "csv":                return "text/csv"
        default:                   return "application/octet-stream"
        }
    }
}

private extension String {
    /// Returns the trimmed substring after `marker` if `self` starts with it,
    /// otherwise `nil`. Replaces the older `dropPrefix` + `trimmingCharacters`
    /// chain at the call sites in `IssueBodyParser`.
    func value(after marker: String) -> String? {
        guard hasPrefix(marker) else { return nil }
        return String(dropFirst(marker.count)).trimmingCharacters(in: asciiWhitespace)
    }
}
