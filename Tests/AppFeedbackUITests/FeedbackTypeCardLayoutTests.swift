import XCTest
import SwiftUI
@testable import AppFeedbackUI

#if os(iOS)
/// The type cards sit side by side in a fixed-width row, and their copy is themable —
/// an adopter's "Bug / Issue" is longer than the default "Bug", and a localized string
/// can be longer still. These pin the two properties that copy length used to break:
/// text wraps instead of truncating, and both cards end up the same size.
@MainActor
final class FeedbackTypeCardLayoutTests: XCTestCase {

    /// Half an iPhone row, minus the sheet's padding — the width at which the reported
    /// truncation appeared.
    private let cardWidth: CGFloat = 155

    private func height(label: String, tagline: String) -> CGFloat {
        let card = FeedbackTypeCard(
            icon: "ant.fill",
            accent: .red,
            label: label,
            tagline: tagline,
            isSelected: false,
            action: {}
        )
        let host = UIHostingController(rootView: card)
        return host.sizeThatFits(in: CGSize(width: cardWidth, height: .greatestFiniteMagnitude)).height
    }

    /// A tagline too long for one line has to wrap, which makes the card taller. If it
    /// were still truncating to a single line the two heights would match.
    func test_longTaglineWrapsRatherThanTruncating() {
        let short = height(label: "Bug", tagline: "Short")
        let long = height(label: "Bug", tagline: "Something isn't working right at all")
        XCTAssertGreaterThan(long, short, "long tagline should wrap onto more lines, not ellipsize")
    }

    func test_longLabelWrapsRatherThanTruncating() {
        let short = height(label: "Bug", tagline: "Short")
        let long = height(label: "Feature Request Suggestion", tagline: "Short")
        XCTAssertGreaterThan(long, short, "long label should wrap onto more lines, not ellipsize")
    }

    /// Both cards are handed the same height by the row, so a card must expand to fill a
    /// taller proposal rather than sitting at its natural height.
    func test_cardFillsTheHeightItIsGiven() {
        let card = FeedbackTypeCard(
            icon: "ant.fill", accent: .red, label: "Bug", tagline: "Short",
            isSelected: false, action: {}
        )
        let host = UIHostingController(rootView: card)
        let natural = host.sizeThatFits(in: CGSize(width: cardWidth, height: .greatestFiniteMagnitude)).height
        let proposed = natural + 40
        let filled = host.sizeThatFits(in: CGSize(width: cardWidth, height: proposed)).height
        XCTAssertEqual(filled, proposed, accuracy: 0.5, "card should fill the row height, so both cards match")
    }
}
#endif
