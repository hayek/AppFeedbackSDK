// Tests/AppFeedbackCoreTests/AttachmentBodyFormatTests.swift
import XCTest
@testable import AppFeedbackCore

final class AttachmentBodyFormatTests: XCTestCase {

    private let device = DeviceInfo(
        appName: "AcmeApp", appVersion: "1.0", buildNumber: "1",
        model: "Mac", osName: "macOS", osVersion: "Version 15.1"
    )

    func test_empty_attachments_emits_no_markers() {
        let report = FeedbackReport(type: .bug, title: "T", description: "Desc")
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: [])
        XCTAssertFalse(body.contains(BodyMarker.attachmentsOpen))
        XCTAssertFalse(body.contains(BodyMarker.attachmentsClose))
    }

    func test_image_entry_uses_image_embed_markdown() {
        let report = FeedbackReport(type: .bug, title: "T", description: "Desc")
        let uploaded = [
            UploadedAttachment(
                filename: "screenshot.png",
                mimeType: "image/png",
                sizeBytes: 1234,
                url: URL(string: "https://raw.githubusercontent.com/o/r/feedback-attachments/attachments/uuid/screenshot.png")!
            )
        ]
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: uploaded)
        XCTAssertTrue(body.contains(BodyMarker.attachmentsOpen))
        XCTAssertTrue(body.contains("![screenshot.png](https://raw.githubusercontent.com/o/r/feedback-attachments/attachments/uuid/screenshot.png) — image/png"))
        XCTAssertTrue(body.contains(BodyMarker.attachmentsClose))
    }

    func test_file_entry_uses_link_markdown() {
        let report = FeedbackReport(type: .bug, title: "T", description: "Desc")
        let uploaded = [
            UploadedAttachment(
                filename: "crash.log",
                mimeType: "text/plain",
                sizeBytes: 4321,
                url: URL(string: "https://example.com/crash.log")!
            )
        ]
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: uploaded)
        XCTAssertTrue(body.contains("[crash.log](https://example.com/crash.log) — text/plain"))
        XCTAssertFalse(body.contains("![crash.log]"))
    }

    func test_attachments_block_appears_before_votes_footer() {
        let report = FeedbackReport(type: .bug, title: "T", description: "Desc")
        let uploaded = [
            UploadedAttachment(
                filename: "a.png", mimeType: "image/png", sizeBytes: 1,
                url: URL(string: "https://example.com/a.png")!
            )
        ]
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: uploaded)
        let openRange = body.range(of: BodyMarker.attachmentsOpen)!
        let votesRange = body.range(of: BodyMarker.votesFooter)!
        XCTAssertLessThan(openRange.lowerBound, votesRange.lowerBound,
                          "attachments block must precede votes footer")
    }
}

final class AttachmentBodyParseTests: XCTestCase {

    func test_absent_block_yields_empty_attachments() {
        let body = "Just a description.\n\n---\n👍 Votes: 0"
        let parsed = IssueBodyParser.parse(body)
        XCTAssertTrue(parsed.attachments.isEmpty)
    }

    func test_parses_image_and_file_entries() {
        let body = """
        Desc

        <!-- attachments-v1 -->
        ## Attachments

        ![shot.png](https://example.com/shot.png) — image/png, 312 KB

        [log.txt](https://example.com/log.txt) — text/plain, 4.1 KB

        <!-- /attachments-v1 -->

        ---
        👍 Votes: 0
        """
        let parsed = IssueBodyParser.parse(body)
        XCTAssertEqual(parsed.attachments.count, 2)
        XCTAssertEqual(parsed.attachments[0].filename, "shot.png")
        XCTAssertEqual(parsed.attachments[0].mimeType, "image/png")
        XCTAssertEqual(parsed.attachments[0].url.absoluteString, "https://example.com/shot.png")
        XCTAssertEqual(parsed.attachments[1].filename, "log.txt")
        XCTAssertEqual(parsed.attachments[1].mimeType, "text/plain")
    }

    func test_missing_suffix_falls_back_to_extension_inference() {
        let body = """
        <!-- attachments-v1 -->
        ## Attachments

        ![s.png](https://example.com/s.png)

        [crash.log](https://example.com/crash.log)

        <!-- /attachments-v1 -->
        """
        let parsed = IssueBodyParser.parse(body)
        XCTAssertEqual(parsed.attachments.count, 2)
        XCTAssertEqual(parsed.attachments[0].mimeType, "image/png")
        XCTAssertEqual(parsed.attachments[1].mimeType, "text/plain")
        XCTAssertNil(parsed.attachments[0].sizeBytes)
    }

    func test_malformed_line_is_skipped() {
        let body = """
        <!-- attachments-v1 -->
        ## Attachments

        not a link line
        ![good.png](https://example.com/g.png) — image/png, 1 KB

        <!-- /attachments-v1 -->
        """
        let parsed = IssueBodyParser.parse(body)
        XCTAssertEqual(parsed.attachments.count, 1)
        XCTAssertEqual(parsed.attachments[0].filename, "good.png")
    }

    func test_future_version_marker_is_ignored() {
        let body = """
        <!-- attachments-v2 -->
        opaque future content
        <!-- /attachments-v2 -->
        """
        let parsed = IssueBodyParser.parse(body)
        XCTAssertTrue(parsed.attachments.isEmpty)
    }

    func test_missing_close_marker_parses_through_to_end() {
        let body = """
        <!-- attachments-v1 -->
        ![a.png](https://example.com/a.png) — image/png, 1 KB
        """
        let parsed = IssueBodyParser.parse(body)
        XCTAssertEqual(parsed.attachments.count, 1)
    }
}
