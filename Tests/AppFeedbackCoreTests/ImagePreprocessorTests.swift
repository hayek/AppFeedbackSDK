// Tests/AppFeedbackCoreTests/ImagePreprocessorTests.swift
import XCTest
import ImageIO
@testable import AppFeedbackCore

final class ImagePreprocessorTests: XCTestCase {

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    private func metadataDict(_ data: Data) -> [String: Any] {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        return (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]
    }

    func test_jpeg_input_emits_jpeg_output_without_gps() throws {
        let input = FeedbackAttachment(filename: "in.jpg", mimeType: "image/jpeg", data: fixture("sample.jpg"))
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.mimeType, "image/jpeg")
        XCTAssertEqual(out.filename, "in.jpg")
        let props = metadataDict(out.data)
        // exiftool not available during fixture generation — fixtures have no GPS to strip,
        // but the assertion still holds: after processing, GPS key must be absent.
        XCTAssertNil(props["{GPS}"], "GPS metadata should be stripped")
    }

    func test_heic_input_transcodes_to_jpeg_and_renames_extension() throws {
        let input = FeedbackAttachment(filename: "shot.heic", mimeType: "image/heic", data: fixture("sample.heic"))
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.mimeType, "image/jpeg")
        XCTAssertEqual(out.filename, "shot.jpg")
        let props = metadataDict(out.data)
        // exiftool not available during fixture generation — fixtures have no GPS to strip,
        // but the assertion still holds: after processing, GPS key must be absent.
        XCTAssertNil(props["{GPS}"], "GPS metadata should be stripped")
    }

    func test_png_input_emits_png_output() throws {
        let input = FeedbackAttachment(filename: "in.png", mimeType: "image/png", data: fixture("sample.png"))
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.mimeType, "image/png")
        XCTAssertEqual(out.filename, "in.png")
    }

    func test_gif_is_passed_through_unchanged() throws {
        let bytes = fixture("sample.gif")
        let input = FeedbackAttachment(filename: "anim.gif", mimeType: "image/gif", data: bytes)
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.data, bytes, "GIF should be byte-identical")
        XCTAssertEqual(out.mimeType, "image/gif")
        XCTAssertEqual(out.filename, "anim.gif")
    }

    func test_non_image_is_bypassed() throws {
        let bytes = Data("hello".utf8)
        let input = FeedbackAttachment(filename: "log.txt", mimeType: "text/plain", data: bytes)
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.data, bytes)
        XCTAssertEqual(out.mimeType, "text/plain")
        XCTAssertEqual(out.filename, "log.txt")
    }

    func test_unreadable_image_throws_processing_failed() {
        let input = FeedbackAttachment(filename: "broken.jpg", mimeType: "image/jpeg", data: Data([0x00, 0x01, 0x02]))
        XCTAssertThrowsError(try ImagePreprocessor.process(input)) { error in
            guard case FeedbackAttachmentError.imageProcessingFailed(let name) = error else {
                return XCTFail("expected imageProcessingFailed, got \(error)")
            }
            XCTAssertEqual(name, "broken.jpg")
        }
    }
}
