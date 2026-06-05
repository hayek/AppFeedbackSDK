import XCTest
@testable import AppFeedbackCore

final class ExtraFieldsOrderingTests: XCTestCase {

    private let device = DeviceInfo(
        appName: "A", appVersion: "1", buildNumber: "1",
        model: "M", osName: "macOS", osVersion: "Version 15.1"
    )

    func test_extra_fields_sorted_by_codepoint_uppercase_before_lowercase() {
        let report = FeedbackReport(
            type: .bug, title: "t", description: "Desc",
            extraFields: ["Zeta": "z", "alpha": "a", "Beta": "b"]
        )
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device)
        // Code-point order: 'B'(0x42) < 'Z'(0x5A) < 'a'(0x61)
        let beta = body.range(of: "**Beta:**")!
        let zeta = body.range(of: "**Zeta:**")!
        let alpha = body.range(of: "**alpha:**")!
        XCTAssertLessThan(beta.lowerBound, zeta.lowerBound)
        XCTAssertLessThan(zeta.lowerBound, alpha.lowerBound)
    }

    func test_prefix_key_orders_before_longer_key() {
        let report = FeedbackReport(
            type: .bug, title: "t", description: "Desc",
            extraFields: ["ab": "2", "a": "1"]
        )
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device)
        // "a" is a prefix of "ab", so code-point lexicographic order puts "a" first.
        let a = body.range(of: "**a:**")!
        let ab = body.range(of: "**ab:**")!
        XCTAssertLessThan(a.lowerBound, ab.lowerBound)
    }

    func test_non_ascii_key_orders_after_ascii_by_codepoint() {
        let report = FeedbackReport(
            type: .bug, title: "t", description: "Desc",
            extraFields: ["é": "x", "a": "y"]
        )
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device)
        // 'a'(0x61) < 'é'(0xE9)
        let a = body.range(of: "**a:**")!
        let e = body.range(of: "**é:**")!
        XCTAssertLessThan(a.lowerBound, e.lowerBound)
    }
}
