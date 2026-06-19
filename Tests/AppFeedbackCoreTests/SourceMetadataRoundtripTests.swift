import XCTest
@testable import AppFeedbackCore

/// The source-metadata block (`source-meta-v1`) is the contract that lets a
/// synthesized App Store / email issue carry its origin through GitHub and back.
/// These tests prove what `IssueBodyFormatter.sourceMetadataBlock` writes is
/// exactly what `IssueBodyParser` reads.
final class SourceMetadataRoundtripTests: XCTestCase {

    func test_app_store_metadata_roundtrips() {
        let block = IssueBodyFormatter.sourceMetadataBlock(
            source: "app-store",
            rating: 4,
            reviewerNickname: "Jane",
            territory: "USA",
            reviewId: "rv-123",
            reviewCreatedAt: "2026-06-18T10:00:00Z",
            fromAddress: nil,
            messageId: nil
        )
        let body = "Loved the new update!\n\n" + block
        let parsed = IssueBodyParser.parse(body)

        XCTAssertEqual(parsed.description, "Loved the new update!")
        XCTAssertEqual(parsed.source, "app-store")
        XCTAssertEqual(parsed.rating, 4)
        XCTAssertEqual(parsed.reviewerNickname, "Jane")
        XCTAssertEqual(parsed.territory, "USA")
        XCTAssertEqual(parsed.reviewId, "rv-123")
        XCTAssertEqual(parsed.reviewCreatedAt, "2026-06-18T10:00:00Z")
        XCTAssertNil(parsed.fromAddress)
        XCTAssertNil(parsed.messageId)
    }

    func test_email_metadata_roundtrips() {
        let block = IssueBodyFormatter.sourceMetadataBlock(
            source: "email",
            rating: nil,
            reviewerNickname: nil,
            territory: nil,
            reviewId: nil,
            reviewCreatedAt: nil,
            fromAddress: "user@example.com",
            messageId: "<abc@mail>"
        )
        let parsed = IssueBodyParser.parse("Hi there\n\n" + block)
        XCTAssertEqual(parsed.source, "email")
        XCTAssertEqual(parsed.fromAddress, "user@example.com")
        XCTAssertEqual(parsed.messageId, "<abc@mail>")
        XCTAssertNil(parsed.rating)
    }

    func test_absent_block_leaves_source_nil() {
        let parsed = IssueBodyParser.parse("Just a plain SDK body.\n\n---\n👍 Votes: 0")
        XCTAssertNil(parsed.source)
        XCTAssertNil(parsed.rating)
    }

    func test_block_survives_CRLF_normalization() {
        let block = IssueBodyFormatter.sourceMetadataBlock(
            source: "app-store", rating: 5, reviewerNickname: nil, territory: "GBR",
            reviewId: "r9", reviewCreatedAt: nil, fromAddress: nil, messageId: nil
        )
        let crlf = ("Body\n\n" + block).replacingOccurrences(of: "\n", with: "\r\n")
        let parsed = IssueBodyParser.parse(crlf)
        XCTAssertEqual(parsed.source, "app-store")
        XCTAssertEqual(parsed.rating, 5)
        XCTAssertEqual(parsed.territory, "GBR")
        XCTAssertEqual(parsed.reviewId, "r9")
    }
}
