import XCTest
@testable import AppFeedbackCore

final class AttachmentSizeFormatTests: XCTestCase {

    private let device = DeviceInfo(
        appName: "A", appVersion: "1", buildNumber: "1",
        model: "M", osName: "macOS", osVersion: "Version 15.1"
    )

    func test_attachment_line_uses_deterministic_size_string() {
        let uploaded = [
            UploadedAttachment(
                filename: "shot.png", mimeType: "image/png", sizeBytes: 1234,
                url: URL(string: "https://example.com/shot.png")!
            )
        ]
        let body = IssueBodyFormatter.format(
            report: FeedbackReport(type: .bug, title: "t", description: "d"),
            deviceInfo: device, uploaded: uploaded
        )
        XCTAssertTrue(
            body.contains("![shot.png](https://example.com/shot.png) — image/png, 1.2 KB"),
            "expected deterministic '1.2 KB'; got body:\n\(body)"
        )
    }
}
