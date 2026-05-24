import XCTest
@testable import AppFeedbackCore

/// The contract between the SDK and the AppFeedback inbox is the issue body
/// shape. These tests prove that what `IssueBodyFormatter` writes is exactly
/// what `IssueBodyParser` reads back.
final class RoundtripTests: XCTestCase {

    private let macDevice = DeviceInfo(
        appName: "Usage for Claude",
        appVersion: "1.2.3",
        buildNumber: "456",
        model: "MacBookPro18,1",
        osName: "macOS",
        osVersion: "Version 14.5 (Build 23F79)"
    )

    func test_bug_with_email_roundtrips() throws {
        let report = FeedbackReport(
            type: .bug,
            title: "Crash on launch",
            description: "Steps to reproduce…\nMore detail.",
            contactEmail: "user@example.com"
        )

        let body = IssueBodyFormatter.format(report: report, deviceInfo: macDevice)
        let parsed = IssueBodyParser.parse(body)

        XCTAssertEqual(parsed.description, "Steps to reproduce…\nMore detail.")
        XCTAssertEqual(parsed.appName, "Usage for Claude")
        XCTAssertEqual(parsed.appVersion, "1.2.3 (456)")
        XCTAssertEqual(parsed.device, "MacBookPro18,1")
        XCTAssertEqual(parsed.osVersion, "Version 14.5 (Build 23F79)")
        XCTAssertEqual(parsed.email, "user@example.com")
    }

    func test_feature_request_without_email_roundtrips() throws {
        let report = FeedbackReport(
            type: .featureRequest,
            title: "Add dark mode",
            description: "Plain ASCII description."
        )

        let body = IssueBodyFormatter.format(report: report, deviceInfo: macDevice)
        let parsed = IssueBodyParser.parse(body)

        XCTAssertEqual(parsed.description, "Plain ASCII description.")
        XCTAssertNil(parsed.email)
        XCTAssertEqual(parsed.appName, "Usage for Claude")
    }

    func test_ios_device_roundtrips_with_iOS_label() throws {
        let ios = DeviceInfo(
            appName: "AcmeApp",
            appVersion: "2.0",
            buildNumber: "200",
            model: "iPhone15,2",
            osName: "iOS",
            osVersion: "Version 18.2 (Build 22C150)"
        )
        let report = FeedbackReport(type: .bug, title: "t", description: "d")

        let parsed = IssueBodyParser.parse(IssueBodyFormatter.format(report: report, deviceInfo: ios))

        XCTAssertEqual(parsed.device, "iPhone15,2")
        XCTAssertEqual(parsed.osVersion, "Version 18.2 (Build 22C150)")
    }

    func test_visionOS_label_is_parsed() throws {
        let vision = DeviceInfo(
            appName: "AcmeApp",
            appVersion: "1.0",
            buildNumber: "1",
            model: "RealityDevice14,1",
            osName: "visionOS",
            osVersion: "Version 2.0 (Build 22N123)"
        )
        let report = FeedbackReport(type: .bug, title: "t", description: "d")

        let parsed = IssueBodyParser.parse(IssueBodyFormatter.format(report: report, deviceInfo: vision))

        XCTAssertEqual(parsed.osVersion, "Version 2.0 (Build 22N123)")
    }

    func test_labels_include_type_and_user_submitted() {
        XCTAssertEqual(IssueBodyFormatter.labels(for: .bug), ["bug", "user-submitted"])
        XCTAssertEqual(IssueBodyFormatter.labels(for: .featureRequest), ["feature-request", "user-submitted"])
    }

    func test_description_with_dashes_survives_roundtrip() throws {
        // The body uses `---` as a separator; user descriptions might also
        // contain dashes. The parser strips standalone `---` lines, so any
        // surviving dashes in the description should be embedded in real text.
        let report = FeedbackReport(
            type: .bug,
            title: "t",
            description: "Line one — with em-dash\nLine two has - a single dash"
        )

        let parsed = IssueBodyParser.parse(IssueBodyFormatter.format(report: report, deviceInfo: macDevice))

        XCTAssertEqual(parsed.description, "Line one — with em-dash\nLine two has - a single dash")
    }
}

extension RoundtripTests {
    func test_attachments_roundtrip_through_format_and_parse() {
        let device = DeviceInfo(
            appName: "App", appVersion: "1.0", buildNumber: "1",
            model: "Mac", osName: "macOS", osVersion: "Version 15.1"
        )
        let uploaded = [
            UploadedAttachment(
                filename: "shot.png", mimeType: "image/png", sizeBytes: 312 * 1024,
                url: URL(string: "https://example.com/shot.png")!
            ),
            UploadedAttachment(
                filename: "log.txt", mimeType: "text/plain", sizeBytes: 4096,
                url: URL(string: "https://example.com/log.txt")!
            ),
        ]
        let report = FeedbackReport(type: .bug, title: "T", description: "D")
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: uploaded)
        let parsed = IssueBodyParser.parse(body)
        XCTAssertEqual(parsed.attachments.count, 2)
        XCTAssertEqual(parsed.attachments[0].filename, "shot.png")
        XCTAssertEqual(parsed.attachments[0].mimeType, "image/png")
        XCTAssertEqual(parsed.attachments[0].url.absoluteString, "https://example.com/shot.png")
        XCTAssertEqual(parsed.attachments[1].filename, "log.txt")
        XCTAssertEqual(parsed.attachments[1].mimeType, "text/plain")
    }
}
