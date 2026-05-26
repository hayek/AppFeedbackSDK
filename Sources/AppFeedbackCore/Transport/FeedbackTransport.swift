import Foundation

/// Where a ``FeedbackReport`` gets delivered.
///
/// Conform to `FeedbackTransport` to send reports anywhere — GitHub directly
/// (see ``GitHubDirectTransport``), a relay server you control (see
/// <doc:CustomTransports>), a mock in tests, or a chain that fans out to
/// multiple destinations.
///
/// Conformances must be `Sendable` because ``FeedbackClient`` stores one
/// across actor boundaries.
public protocol FeedbackTransport: Sendable {

    /// Delivers a report and returns the backend-assigned identifier.
    ///
    /// - Parameters:
    ///   - report: The user submission, including any optional contact email
    ///     and custom `extraFields`.
    ///   - deviceInfo: Per-submission metadata collected by ``FeedbackClient``.
    /// - Returns: Whatever identifier the backend uses to refer to this
    ///   submission. For ``GitHubDirectTransport`` it's the issue number.
    /// - Throws: ``FeedbackSubmissionError`` for known failure modes, or any
    ///   error your custom transport surfaces.
    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int
}
