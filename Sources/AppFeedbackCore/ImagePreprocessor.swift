// Sources/AppFeedbackCore/ImagePreprocessor.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Strips metadata (EXIF/GPS) and transcodes HEIC→JPEG before upload.
///
/// Cross-platform — no `#if`s; ImageIO is on every Apple platform.
public enum ImagePreprocessor {

    public static func process(_ attachment: FeedbackAttachment) throws -> FeedbackAttachment {
        switch attachment.mimeType {
        case "image/heic":
            return try transcode(attachment, to: UTType.jpeg, mime: "image/jpeg", swappingExtensionTo: "jpg")
        case "image/jpeg":
            return try transcode(attachment, to: UTType.jpeg, mime: "image/jpeg", swappingExtensionTo: nil)
        case "image/png":
            return try transcode(attachment, to: UTType.png, mime: "image/png", swappingExtensionTo: nil)
        case "image/gif":
            return attachment   // pass-through preserves animation
        default:
            return attachment   // non-images bypass
        }
    }

    private static func transcode(
        _ attachment: FeedbackAttachment,
        to type: UTType,
        mime: String,
        swappingExtensionTo newExtension: String?
    ) throws -> FeedbackAttachment {
        guard let source = CGImageSourceCreateWithData(attachment.data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw FeedbackAttachmentError.imageProcessingFailed(filename: attachment.filename)
        }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw FeedbackAttachmentError.imageProcessingFailed(filename: attachment.filename)
        }
        // Explicit GPS/XMP exclusion keys ensure ImageIO strips source metadata before writing.
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true,
        ]
        CGImageDestinationAddImageFromSource(dest, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FeedbackAttachmentError.imageProcessingFailed(filename: attachment.filename)
        }
        let newFilename: String
        if let newExtension {
            let stem = (attachment.filename as NSString).deletingPathExtension
            newFilename = "\(stem).\(newExtension)"
        } else {
            newFilename = attachment.filename
        }
        return FeedbackAttachment(filename: newFilename, mimeType: mime, data: output as Data)
    }
}
