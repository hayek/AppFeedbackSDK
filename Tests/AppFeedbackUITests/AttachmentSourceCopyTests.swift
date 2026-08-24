import XCTest
@testable import AppFeedbackUI

/// The iOS attachment menu names its two sources, and every visible string in the sheet
/// has to be overridable for localization — see <doc:Localization>.
final class AttachmentSourceCopyTests: XCTestCase {

    func test_defaultCopy_namesBothAttachmentSources() {
        let copy = FeedbackTheme.default.copy
        XCTAssertEqual(copy.attachPhotoLibraryLabel, "Photo Library")
        XCTAssertEqual(copy.attachFilesLabel, "Files…")
    }

    func test_attachmentSourceLabels_areOverridable() {
        var copy = FeedbackTheme.default.copy
        copy.attachPhotoLibraryLabel = "Galerie"
        copy.attachFilesLabel = "Dateien…"
        XCTAssertEqual(copy.attachPhotoLibraryLabel, "Galerie")
        XCTAssertEqual(copy.attachFilesLabel, "Dateien…")
    }
}
