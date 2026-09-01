import XCTest
import Foundation
@testable import AppFeedbackUI

/// ``PraisePromptBuilder`` deliberately imports no framework, so these run on
/// every platform and every Xcode — including toolchains with no Foundation
/// Models SDK at all.
final class PraisePromptBuilderTests: XCTestCase {

    func test_input_carries_both_title_and_description() {
        let input = PraisePromptBuilder.input(title: "Great app", description: "I love it")
        XCTAssertTrue(input.contains("Great app"))
        XCTAssertTrue(input.contains("I love it"))
    }

    func test_short_input_is_passed_through_untruncated() {
        let input = PraisePromptBuilder.input(title: "t", description: "d")
        XCTAssertTrue(input.hasSuffix("d"))
        XCTAssertLessThan(input.count, PraisePromptBuilder.inputCharacterLimit)
    }

    func test_over_limit_input_is_capped() {
        // `descriptionLimit` on the sheet is advisory — it colors the counter red
        // but never blocks submission — so the text reaching the model is
        // genuinely unbounded and has to be capped here.
        let long = String(repeating: "a", count: PraisePromptBuilder.inputCharacterLimit * 2)
        let input = PraisePromptBuilder.input(title: "t", description: long)
        XCTAssertEqual(input.count, PraisePromptBuilder.inputCharacterLimit)
    }

    func test_truncation_lands_on_a_grapheme_boundary() {
        // A family emoji is one Character built from seven scalars. Capping by
        // byte or scalar offset would slice it into mojibake; capping by
        // Character cannot.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let long = String(repeating: family, count: PraisePromptBuilder.inputCharacterLimit)
        let input = PraisePromptBuilder.input(title: "t", description: long)
        XCTAssertEqual(input.count, PraisePromptBuilder.inputCharacterLimit)
        XCTAssertEqual(String(input.suffix(1)), family)
    }

    /// Feedback front-loads the compliment and appends the qualifier, so a
    /// head-only cap would delete the clause that disqualifies the text and
    /// hand the model a crash report reading as pure praise.
    func test_truncation_keeps_the_tail_where_the_qualifier_lives() {
        let padding = String(repeating: "I really love this app. ", count: 200)
        let input = PraisePromptBuilder.input(
            title: "Love it",
            description: padding + "But it crashes every time I export."
        )
        XCTAssertGreaterThan(padding.count, PraisePromptBuilder.inputCharacterLimit)
        XCTAssertTrue(input.contains("But it crashes every time I export."))
        XCTAssertTrue(input.contains("Love it"))
        XCTAssertTrue(input.contains(PraisePromptBuilder.elision))
    }

    /// The instructions have to account for the gap the cap leaves behind,
    /// otherwise the model reads the elision as a non sequitur.
    func test_instructions_explain_the_elision_marker() {
        XCTAssertTrue(PraisePromptBuilder.instructions.contains(PraisePromptBuilder.elision.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
