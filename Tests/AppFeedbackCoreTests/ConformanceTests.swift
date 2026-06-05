import XCTest
@testable import AppFeedbackCore

/// Runs the language-neutral golden fixtures from `appfeedback-spec` (vendored
/// under Fixtures/conformance) through the Swift formatter and parser. Every
/// platform port runs this same corpus; it is the blocking gate that keeps the
/// three implementations byte-identical.
final class ConformanceTests: XCTestCase {

    // MARK: Fixture models

    private struct ReportFixture: Decodable {
        let type: String
        // `title` becomes the GitHub issue title, NOT part of the body; it is
        // carried only so each case constructs a realistic report.
        let title: String
        let description: String
        let contactEmail: String?
        let extraFields: [String: String]?
    }
    private struct DeviceFixture: Decodable {
        let appName, appVersion, buildNumber, model, osName, osVersion: String
    }
    private struct UploadedFixture: Decodable {
        let filename, mimeType: String
        let sizeBytes: Int
        let url: String
    }
    private struct FormatCase: Decodable {
        let name: String
        let report: ReportFixture
        let deviceInfo: DeviceFixture
        let uploaded: [UploadedFixture]?
        let expectedBody: String
        let expectedLabels: [String]?
    }
    private struct AttachmentExpectation: Decodable {
        let filename, mimeType, url: String
        let sizeBytes: Int?
    }
    private struct ParsedExpectation: Decodable {
        let description: String
        let appName, appVersion, device, osVersion, email: String?
        let attachments: [AttachmentExpectation]?
    }
    private struct ParseCase: Decodable {
        let name: String
        let body: String
        let expected: ParsedExpectation
    }

    /// Top-level fixture envelope. The `version` field lets the corpus schema
    /// evolve without a breaking top-level shape change across the Swift,
    /// Kotlin, and TypeScript ports that all consume these same files.
    private struct Corpus<Case: Decodable>: Decodable {
        let version: Int
        let cases: [Case]
    }

    // MARK: Loading

    private func loadCases<T: Decodable>(_ resource: String) throws -> [T] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: resource, withExtension: "json", subdirectory: "Fixtures/conformance"),
            "missing fixture \(resource).json"
        )
        return try JSONDecoder().decode(Corpus<T>.self, from: Data(contentsOf: url)).cases
    }

    // MARK: Tests

    func test_format_golden_fixtures() throws {
        let cases: [FormatCase] = try loadCases("format-cases")
        XCTAssertFalse(cases.isEmpty, "no format fixtures loaded")
        for c in cases {
            let type = try XCTUnwrap(FeedbackType(rawValue: c.report.type), "unknown type in \(c.name)")
            let report = FeedbackReport(
                type: type, title: c.report.title, description: c.report.description,
                contactEmail: c.report.contactEmail, extraFields: c.report.extraFields ?? [:]
            )
            let device = DeviceInfo(
                appName: c.deviceInfo.appName, appVersion: c.deviceInfo.appVersion,
                buildNumber: c.deviceInfo.buildNumber, model: c.deviceInfo.model,
                osName: c.deviceInfo.osName, osVersion: c.deviceInfo.osVersion
            )
            let uploaded = try (c.uploaded ?? []).map {
                UploadedAttachment(
                    filename: $0.filename, mimeType: $0.mimeType, sizeBytes: $0.sizeBytes,
                    url: try XCTUnwrap(URL(string: $0.url), "bad url in \(c.name)")
                )
            }
            let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: uploaded)
            XCTAssertEqual(body, c.expectedBody, "format mismatch in '\(c.name)'")
            if let labels = c.expectedLabels {
                // Labels are part of the wire contract; each platform port
                // verifies them against its own labels(for:) implementation.
                XCTAssertEqual(IssueBodyFormatter.labels(for: type), labels, "labels mismatch in '\(c.name)'")
            }
        }
    }

    func test_parse_golden_fixtures() throws {
        let cases: [ParseCase] = try loadCases("parse-cases")
        XCTAssertFalse(cases.isEmpty, "no parse fixtures loaded")
        for c in cases {
            let parsed = IssueBodyParser.parse(c.body)
            XCTAssertEqual(parsed.description, c.expected.description, "description mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.appName, c.expected.appName, "appName mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.appVersion, c.expected.appVersion, "appVersion mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.device, c.expected.device, "device mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.osVersion, c.expected.osVersion, "osVersion mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.email, c.expected.email, "email mismatch in '\(c.name)'")
            let expected = c.expected.attachments ?? []
            XCTAssertEqual(parsed.attachments.count, expected.count, "attachment count mismatch in '\(c.name)'")
            for (i, ea) in expected.enumerated() where i < parsed.attachments.count {
                XCTAssertEqual(parsed.attachments[i].filename, ea.filename, "att filename in '\(c.name)'[\(i)]")
                XCTAssertEqual(parsed.attachments[i].mimeType, ea.mimeType, "att mime in '\(c.name)'[\(i)]")
                XCTAssertEqual(parsed.attachments[i].url.absoluteString, ea.url, "att url in '\(c.name)'[\(i)]")
                XCTAssertEqual(parsed.attachments[i].sizeBytes, ea.sizeBytes, "att size in '\(c.name)'[\(i)]")
            }
        }
    }
}
