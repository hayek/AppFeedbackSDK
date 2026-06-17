import XCTest
@testable import AppFeedbackUI
import AppFeedbackCore

final class MakeReportTests: XCTestCase {

    func test_extraFields_are_forwarded_into_report() {
        let report = FeedbackSheet.makeReport(
            type: .bug, title: "t", description: "d", contactEmail: "",
            attachments: [], extraFields: ["Install ID": "abc-123", "Usage Diagnostics": "fetch=ok"]
        )
        XCTAssertEqual(report.extraFields["Install ID"], "abc-123")
        XCTAssertEqual(report.extraFields["Usage Diagnostics"], "fetch=ok")
    }

    func test_empty_email_becomes_nil() {
        let report = FeedbackSheet.makeReport(
            type: .featureRequest, title: "t", description: "d",
            contactEmail: "  ", attachments: [], extraFields: [:]
        )
        XCTAssertNil(report.contactEmail)
    }

    func test_nonempty_email_is_kept_trimmed() {
        let report = FeedbackSheet.makeReport(
            type: .bug, title: "t", description: "d",
            contactEmail: "  user@example.com  ", attachments: [], extraFields: [:]
        )
        XCTAssertEqual(report.contactEmail, "user@example.com")
    }
}
