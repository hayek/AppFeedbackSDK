// Sources/AppFeedbackUI/PhotoAttachmentNaming.swift
import Foundation
import UniformTypeIdentifiers

/// Names photo-library picks.
///
/// `PhotosPickerItem` carries no filename: the picker runs out of process, so all that
/// comes back are bytes and a content type. Reading the real name would mean resolving
/// the `PHAsset`, which needs full photo-library authorization — the very prompt
/// `PHPickerViewController` exists to avoid. So the name is synthesised from the type.
enum PhotoAttachmentNaming {
    static let baseName = "Photo"

    /// - Parameter taken: names already spoken for — earlier picks in the same batch and
    ///   anything already on the attachment strip — so a second pick can't shadow the first.
    static func descriptor(for type: UTType?, avoiding taken: Set<String>) -> (filename: String, mimeType: String) {
        let ext = type?.preferredFilenameExtension ?? "dat"
        // No guessing: an unmappable type gets an honestly-unsupported MIME so the
        // validator names it, rather than mislabelling the bytes as something they aren't.
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        var filename = "\(baseName).\(ext)"
        var suffix = 2
        while taken.contains(filename) {
            filename = "\(baseName)-\(suffix).\(ext)"
            suffix += 1
        }
        return (filename, mime)
    }
}
