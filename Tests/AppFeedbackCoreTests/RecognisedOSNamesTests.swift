import XCTest
@testable import AppFeedbackCore

final class RecognisedOSNamesTests: XCTestCase {

    /// Formats a body with the given OS name/version, parses it back, and
    /// returns the parsed `osVersion` (nil if the line was not recognised).
    private func roundTripOSVersion(osName: String, osVersion: String) -> String? {
        let device = DeviceInfo(
            appName: "A", appVersion: "1", buildNumber: "1",
            model: "M", osName: osName, osVersion: osVersion
        )
        let body = IssueBodyFormatter.format(
            report: FeedbackReport(type: .bug, title: "t", description: "d"),
            deviceInfo: device
        )
        return IssueBodyParser.parse(body).osVersion
    }

    func test_android_os_version_is_parsed() {
        XCTAssertEqual(roundTripOSVersion(osName: "Android", osVersion: "14"), "14")
    }

    func test_windows_os_version_is_parsed() {
        XCTAssertEqual(
            roundTripOSVersion(osName: "Windows", osVersion: "11 (22631.4317)"),
            "11 (22631.4317)"
        )
    }

    func test_web_os_version_is_parsed() {
        XCTAssertEqual(
            roundTripOSVersion(osName: "Web", osVersion: "Chrome 120 on macOS"),
            "Chrome 120 on macOS"
        )
    }

    func test_linux_and_chromeos_os_versions_are_parsed() {
        XCTAssertEqual(roundTripOSVersion(osName: "Linux", osVersion: "Ubuntu 24.04"), "Ubuntu 24.04")
        XCTAssertEqual(roundTripOSVersion(osName: "ChromeOS", osVersion: "120"), "120")
    }

    func test_existing_apple_os_names_still_parse() {
        XCTAssertEqual(roundTripOSVersion(osName: "iOS", osVersion: "Version 18.2"), "Version 18.2")
        XCTAssertEqual(roundTripOSVersion(osName: "macOS", osVersion: "Version 15.1"), "Version 15.1")
    }

    func test_unrecognised_os_name_is_not_parsed() {
        XCTAssertNil(roundTripOSVersion(osName: "BeOS", osVersion: "5.0"))
    }
}
