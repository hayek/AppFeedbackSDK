import Foundation

enum FeedbackAttachmentValidator {

    static let maxCount = 3
    static let maxFileBytes = 5 * 1024 * 1024
    static let maxTotalBytes = 10 * 1024 * 1024
    static let allowedMimeTypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/heic",
        "image/gif",
        "text/plain",
        "application/json",
        "application/pdf",
    ]

    static func validate(_ attachments: [FeedbackAttachment]) throws {
        if attachments.count > maxCount {
            throw FeedbackAttachmentError.tooManyAttachments(limit: maxCount, got: attachments.count)
        }
        var total = 0
        for a in attachments {
            if !allowedMimeTypes.contains(a.mimeType) {
                throw FeedbackAttachmentError.unsupportedMimeType(filename: a.filename, mimeType: a.mimeType)
            }
            if a.data.count > maxFileBytes {
                throw FeedbackAttachmentError.fileTooLarge(filename: a.filename, sizeBytes: a.data.count, limit: maxFileBytes)
            }
            total += a.data.count
        }
        if total > maxTotalBytes {
            throw FeedbackAttachmentError.totalSizeTooLarge(totalBytes: total, limit: maxTotalBytes)
        }
    }
}
