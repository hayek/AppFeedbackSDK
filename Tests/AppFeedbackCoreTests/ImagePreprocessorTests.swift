// Tests/AppFeedbackCoreTests/ImagePreprocessorTests.swift
import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
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

    /// Creates a minimal 1×1 CGImage (red pixel).
    private func makeRedPixelImage() -> CGImage {
        var pixel: UInt32 = 0xFF0000FF  // RGBA red, full alpha
        let data = Data(bytes: &pixel, count: 4)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: 1, height: 1,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Builds a `CGImageMetadata` container with a GPS block (37.7749°N, 122.4194°W).
    private func makeGPSMetadata() -> CGMutableImageMetadata {
        let meta = CGImageMetadataCreateMutable()

        func set(_ path: CFString, _ value: CFTypeRef) {
            CGImageMetadataSetValueWithPath(meta, nil, path, value)
        }

        // Use the XMP-exif GPS paths that ImageIO understands.
        set("exif:GPSLatitudeRef" as CFString,  "N" as CFString)
        set("exif:GPSLatitude" as CFString,     "37,46.494000N" as CFString)
        set("exif:GPSLongitudeRef" as CFString, "W" as CFString)
        set("exif:GPSLongitude" as CFString,    "122,25.164000W" as CFString)

        return meta
    }

    /// Returns JPEG bytes for a 1×1 red pixel with embedded GPS metadata.
    private func makeJPEGWithGPS() -> Data {
        let output = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1, nil
        )!
        let imageOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]
        CGImageDestinationAddImageAndMetadata(
            dest, makeRedPixelImage(), makeGPSMetadata(), imageOptions as CFDictionary
        )
        CGImageDestinationFinalize(dest)
        return output as Data
    }

    /// Returns HEIC bytes for a 1×1 red pixel with embedded GPS metadata.
    private func makeHEICWithGPS() -> Data {
        let output = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.heic.identifier as CFString,
            1, nil
        )!
        let imageOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]
        CGImageDestinationAddImageAndMetadata(
            dest, makeRedPixelImage(), makeGPSMetadata(), imageOptions as CFDictionary
        )
        CGImageDestinationFinalize(dest)
        return output as Data
    }

    func test_jpeg_input_emits_jpeg_output_without_gps() throws {
        let input = FeedbackAttachment(filename: "in.jpg", mimeType: "image/jpeg", data: makeJPEGWithGPS())
        // Sanity-check the fixture has GPS so the strip is actually exercised.
        let beforeProps = metadataDict(input.data)
        XCTAssertNotNil(beforeProps["{GPS}"], "test fixture must have GPS for the strip-test to be meaningful")
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.mimeType, "image/jpeg")
        XCTAssertEqual(out.filename, "in.jpg")
        let afterProps = metadataDict(out.data)
        XCTAssertNil(afterProps["{GPS}"], "GPS metadata should be stripped")
    }

    func test_heic_input_transcodes_to_jpeg_and_renames_extension() throws {
        let input = FeedbackAttachment(filename: "shot.heic", mimeType: "image/heic", data: makeHEICWithGPS())
        let beforeProps = metadataDict(input.data)
        XCTAssertNotNil(beforeProps["{GPS}"], "test fixture must have GPS for the strip-test to be meaningful")
        let out = try ImagePreprocessor.process(input)
        XCTAssertEqual(out.mimeType, "image/jpeg")
        XCTAssertEqual(out.filename, "shot.jpg")
        let afterProps = metadataDict(out.data)
        XCTAssertNil(afterProps["{GPS}"], "GPS metadata should be stripped")
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
