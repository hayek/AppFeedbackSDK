import Foundation

/// Errors thrown by ``GitHubDirectTransport``.
///
/// Custom transports may throw these as well; the UI module
/// ``AppFeedbackUI/FeedbackSheet`` displays `localizedDescription` in an
/// alert, so conform to `LocalizedError` (this enum already does) if you
/// want user-friendly messages.
public enum FeedbackSubmissionError: Error, LocalizedError, Sendable {

    /// The server responded but the response object wasn't an
    /// `HTTPURLResponse`. Rare — typically indicates a misconfigured
    /// `URLSession`.
    case invalidResponse

    /// The server returned a non-2xx HTTP status code.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code returned by the server.
    ///   - body: The response body, when available. Useful for surfacing
    ///     GitHub validation errors (e.g. `{"message":"Validation Failed"}`).
    case httpStatus(Int, body: String?)

    /// The server returned a 2xx but the response body couldn't be decoded
    /// into the expected shape. Carries the underlying `DecodingError`.
    case decoding(any Error & Sendable)

    /// The request failed at the network layer (no connection, DNS, TLS).
    /// Carries the underlying `URLError`.
    case transport(any Error & Sendable)

    /// Synchronous validation failure. No network was touched and no state changed.
    case attachmentValidation(FeedbackAttachmentError)

    /// Per-file upload failure. `filename` is empty when the failure occurred before
    /// any specific file (e.g. branch-ensure). Files uploaded before this one in the
    /// same submission remain as orphan blobs on the attachments branch.
    case attachmentUpload(filename: String, underlying: any Error & Sendable)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from feedback server"
        case .httpStatus(let code, _):
            return "Feedback server returned HTTP \(code)"
        case .decoding:
            return "Could not decode feedback server response"
        case .transport(let underlying):
            return underlying.localizedDescription
        case .attachmentValidation:
            return "Attachment validation failed"
        case .attachmentUpload(let filename, _):
            return filename.isEmpty ? "Attachment upload initialization failed" : "Failed to upload attachment: \(filename)"
        }
    }
}
