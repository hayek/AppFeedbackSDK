import XCTest
@testable import AppFeedbackCore

final class FeedbackAttachmentValidatorTests: XCTestCase {

    private func att(name: String = "f.png", mime: String = "image/png", bytes: Int = 1024) -> FeedbackAttachment {
        FeedbackAttachment(filename: name, mimeType: mime, data: Data(count: bytes))
    }

    func test_empty_attachments_pass() throws {
        XCTAssertNoThrow(try FeedbackAttachmentValidator.validate([]))
    }

    func test_three_at_limit_pass() throws {
        let xs = [att(), att(), att()]
        XCTAssertNoThrow(try FeedbackAttachmentValidator.validate(xs))
    }

    func test_four_exceeds_count_limit() {
        let xs = [att(), att(), att(), att()]
        XCTAssertThrowsError(try FeedbackAttachmentValidator.validate(xs)) { error in
            guard case FeedbackAttachmentError.tooManyAttachments(let limit, let got) = error else {
                return XCTFail("expected tooManyAttachments, got \(error)")
            }
            XCTAssertEqual(limit, 3)
            XCTAssertEqual(got, 4)
        }
    }

    func test_per_file_size_limit() {
        let big = att(name: "big.png", bytes: 5 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try FeedbackAttachmentValidator.validate([big])) { error in
            guard case FeedbackAttachmentError.fileTooLarge(let name, let bytes, let limit) = error else {
                return XCTFail("expected fileTooLarge, got \(error)")
            }
            XCTAssertEqual(name, "big.png")
            XCTAssertEqual(bytes, 5 * 1024 * 1024 + 1)
            XCTAssertEqual(limit, 5 * 1024 * 1024)
        }
    }

    func test_total_size_limit() {
        let xs = [
            att(name: "a.png", bytes: 5 * 1024 * 1024),
            att(name: "b.png", bytes: 5 * 1024 * 1024),
            att(name: "c.png", bytes: 1),
        ]
        XCTAssertThrowsError(try FeedbackAttachmentValidator.validate(xs)) { error in
            guard case FeedbackAttachmentError.totalSizeTooLarge(let bytes, let limit) = error else {
                return XCTFail("expected totalSizeTooLarge, got \(error)")
            }
            XCTAssertEqual(bytes, 10 * 1024 * 1024 + 1)
            XCTAssertEqual(limit, 10 * 1024 * 1024)
        }
    }

    func test_unsupported_mime_type() {
        let bad = att(mime: "application/zip")
        XCTAssertThrowsError(try FeedbackAttachmentValidator.validate([bad])) { error in
            guard case FeedbackAttachmentError.unsupportedMimeType(let name, let mime) = error else {
                return XCTFail("expected unsupportedMimeType, got \(error)")
            }
            XCTAssertEqual(name, "f.png")
            XCTAssertEqual(mime, "application/zip")
        }
    }

    func test_all_allowed_mime_types_pass() throws {
        let mimes = [
            "image/png", "image/jpeg", "image/heic", "image/gif",
            "text/plain", "application/json", "application/pdf",
        ]
        for m in mimes {
            XCTAssertNoThrow(
                try FeedbackAttachmentValidator.validate([att(mime: m)]),
                "expected \(m) to be allowed"
            )
        }
    }
}
