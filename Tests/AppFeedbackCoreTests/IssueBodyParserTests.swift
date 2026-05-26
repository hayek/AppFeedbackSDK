import XCTest
@testable import AppFeedbackCore

/// Parses known body shapes that today's ClaudeUsage app produces. If these
/// break, the inbox will silently lose structured fields on real production
/// data, so we pin the parser to the exact format ClaudeUsage emits.
final class IssueBodyParserTests: XCTestCase {

    func test_parses_legacy_claudeusage_body_shape() {
        let raw = """
        The export button does nothing on macOS 15.

        ---
        **Device Information:**
        App: Usage for Claude
        App Version: 3.4.1 (980)
        Device: Mac15,11
        macOS Version: Version 15.1 (Build 24B83)

        **Contact Email:**
        beta@example.com

        ---
        👍 Votes: 0
        """

        let parsed = IssueBodyParser.parse(raw)

        XCTAssertEqual(parsed.description, "The export button does nothing on macOS 15.")
        XCTAssertEqual(parsed.appName, "Usage for Claude")
        XCTAssertEqual(parsed.appVersion, "3.4.1 (980)")
        XCTAssertEqual(parsed.device, "Mac15,11")
        XCTAssertEqual(parsed.osVersion, "Version 15.1 (Build 24B83)")
        XCTAssertEqual(parsed.email, "beta@example.com")
    }

    func test_parses_body_without_email() {
        let raw = """
        Just a feature idea.

        ---
        **Device Information:**
        App: AcmeApp
        App Version: 1.0 (1)
        Device: iPhone15,2
        iOS Version: Version 18.0 (Build 22A123)

        ---
        👍 Votes: 0
        """

        let parsed = IssueBodyParser.parse(raw)

        XCTAssertEqual(parsed.description, "Just a feature idea.")
        XCTAssertNil(parsed.email)
        XCTAssertEqual(parsed.appName, "AcmeApp")
    }

    func test_parses_inline_contact_email_on_same_line() {
        // Some clients write `**Contact Email:** foo@bar.com` on one line.
        let raw = """
        Description here.

        ---
        **Device Information:**
        App: AcmeApp
        App Version: 1.0 (1)
        Device: iPhone15,2
        iOS Version: 18.0
        **Contact Email:** foo@bar.com
        """

        let parsed = IssueBodyParser.parse(raw)

        XCTAssertEqual(parsed.email, "foo@bar.com")
    }

    func test_multiline_description_preserved() {
        let raw = """
        First paragraph.

        Second paragraph with more detail.

        ---
        **Device Information:**
        App: AcmeApp
        App Version: 1.0 (1)
        Device: iPhone15,2
        iOS Version: 18.0
        """

        let parsed = IssueBodyParser.parse(raw)

        XCTAssertEqual(parsed.description, "First paragraph.\n\nSecond paragraph with more detail.")
    }
}
