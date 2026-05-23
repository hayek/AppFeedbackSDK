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
