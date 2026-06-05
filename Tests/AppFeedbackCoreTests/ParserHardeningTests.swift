import XCTest
@testable import AppFeedbackCore

final class ParserHardeningTests: XCTestCase {
    func test_control_char_on_device_header_still_parses() {
        // A stray vertical tab on the header line must not hide the marker.
        let body = "Bug.\n\n---\n**Device Information:**\u{0B}\nApp: Acme\nApp Version: 1.0 (1)\nDevice: Mac\nmacOS Version: 15.1\n\n---\n👍 Votes: 0"
        let parsed = IssueBodyParser.parse(body)
        XCTAssertEqual(parsed.appName, "Acme")
        XCTAssertEqual(parsed.osVersion, "15.1")
    }
    func test_non_finite_and_oversize_byte_counts_are_nil() {
        XCTAssertNil(IssueBodyParser.parseHumanByteCount("Infinity KB"))
        XCTAssertNil(IssueBodyParser.parseHumanByteCount("NaN B"))
        XCTAssertNil(IssueBodyParser.parseHumanByteCount("10000000000 GB"))
        XCTAssertEqual(IssueBodyParser.parseHumanByteCount("3 GB"), 3_000_000_000)
    }
}
