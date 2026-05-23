import Foundation

/// A binary payload attached to a ``FeedbackReport``.
///
/// Build one per file the user picked, push into ``FeedbackReport/attachments``.
/// The SDK validates count + size + MIME type, image-preprocesses (EXIF strip,
/// HEIC→JPEG), then uploads to a `feedback-attachments` branch of the inbox repo
/// before creating the issue. See <doc:Attachments> for the wire contract.
public struct FeedbackAttachment: Sendable, Equatable {
    /// Display filename. Basename only — leading directories stripped. Sanitized at upload time.
    public let filename: String

    /// Canonical MIME type. Must be one of the SDK allowlist:
    /// `image/png`, `image/jpeg`, `image/heic`, `image/gif`,
    /// `text/plain`, `application/json`, `application/pdf`.
    public let mimeType: String

    /// Raw bytes. Images are re-encoded before upload to strip metadata.
    public let data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}
