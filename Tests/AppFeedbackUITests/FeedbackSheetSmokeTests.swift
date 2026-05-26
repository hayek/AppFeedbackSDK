import XCTest
import SwiftUI
@testable import AppFeedbackUI
@testable import AppFeedbackCore

/// SwiftUI view rendering is hard to assert on without snapshots; these are
/// build-and-instantiate smoke tests that catch the most common regressions
/// (missing init params, broken type-checking, non-Sendable closures, etc).
final class FeedbackSheetSmokeTests: XCTestCase {

    func test_sheet_instantiates_with_default_theme() {
        let client = FeedbackClient(
            transport: NoOpTransport(),
            deviceInfo: DeviceInfo(
                appName: "AcmeApp", appVersion: "1.0", buildNumber: "1",
                model: "Mac15,11", osName: "macOS",
                osVersion: "Version 15.1 (Build 24B83)"
            )
        )
        let sheet = FeedbackSheet(client: client, theme: .default)
        _ = sheet.body
    }

    func test_validation_template_substitutes_fields_locale_aware() {
        // Uses `ListFormatter.localizedString(byJoining:)` so the joiner is
        // locale-correct. In English the output is "Title and Description";
        // other locales get appropriate conjunctions and separators.
        let copy = FeedbackTheme.Copy.default
        let message = copy.validationPrompt(forMissing: ["Title", "Description"])
        XCTAssertTrue(message.hasPrefix("Please fill in: "))
        XCTAssertTrue(message.contains("Title"))
        XCTAssertTrue(message.contains("Description"))
    }

    func test_theme_is_sendable_across_actor() async {
        let theme = FeedbackTheme.default
        await Task.detached { _ = theme }.value
    }
}

private struct NoOpTransport: FeedbackTransport {
    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int { 0 }
}
