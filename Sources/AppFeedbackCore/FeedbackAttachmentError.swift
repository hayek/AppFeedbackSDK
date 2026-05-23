import Foundation

/// Synchronous, pre-network validation failures from ``FeedbackAttachmentValidator``
/// and the SDK's image preprocessor. Surfaced via
/// ``FeedbackSubmissionError/attachmentValidation``.
public enum FeedbackAttachmentError: Error, Sendable, Equatable {
    case tooManyAttachments(limit: Int, got: Int)
    case fileTooLarge(filename: String, sizeBytes: Int, limit: Int)
    case totalSizeTooLarge(totalBytes: Int, limit: Int)
    case unsupportedMimeType(filename: String, mimeType: String)
    case imageProcessingFailed(filename: String)
}
