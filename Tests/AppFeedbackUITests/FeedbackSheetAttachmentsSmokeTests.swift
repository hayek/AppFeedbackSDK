import XCTest
import SwiftUI
@testable import AppFeedbackCore
@testable import AppFeedbackUI

final class FeedbackSheetAttachmentsSmokeTests: XCTestCase {

    /// Sanity: the sheet compiles with a client and renders without crashing.
    @MainActor
    func test_sheet_initializes_with_default_theme() {
        struct NoOpTransport: FeedbackTransport {
            func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int { 1 }
        }
        let client = FeedbackClient(transport: NoOpTransport(), deviceInfo: DeviceInfo(
            appName: "T", appVersion: "1", buildNumber: "1",
            model: "Mac", osName: "macOS", osVersion: "Version 15.1"
        ))
        let sheet = FeedbackSheet(client: client)
        #if os(macOS)
        let host = NSHostingView(rootView: sheet)
        XCTAssertNotNil(host)
        #else
        _ = sheet.body
        #endif
    }
}
