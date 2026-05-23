import XCTest
@testable import AppFeedbackCore

final class GitHubDirectTransportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private let device = DeviceInfo(
        appName: "AcmeApp",
        appVersion: "1.0",
        buildNumber: "1",
        model: "Mac15,11",
        osName: "macOS",
        osVersion: "Version 15.1 (Build 24B83)"
    )

    func test_posts_to_issues_endpoint_with_expected_payload_and_returns_issue_number() async throws {
        URLProtocolStub.respond { request in
            XCTAssertEqual(request.url?.absoluteString,
                           "https://api.github.com/repos/octocat/feedback/issues")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let bodyData = request.bodyData ?? Data()
            let decoded = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            XCTAssertEqual(decoded["title"] as? String, "Crash on launch")
            XCTAssertEqual(decoded["labels"] as? [String], ["bug", "user-submitted"])
            let body = decoded["body"] as! String
            XCTAssertTrue(body.contains("Steps to reproduce"))
            XCTAssertTrue(body.contains("App: AcmeApp"))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                #"{"number":42}"#.data(using: .utf8)!
            )
        }

        let transport = GitHubDirectTransport(
            owner: "octocat",
            repo: "feedback",
            token: "test-token",
            session: makeSession()
        )

        let issueNumber = try await transport.submit(
            FeedbackReport(type: .bug, title: "Crash on launch", description: "Steps to reproduce"),
            deviceInfo: device
        )

        XCTAssertEqual(issueNumber, 42)
    }

    func test_non_2xx_throws_httpStatus_error_with_body() async {
        URLProtocolStub.respond { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!,
                #"{"message":"validation failed"}"#.data(using: .utf8)!
            )
        }

        let transport = GitHubDirectTransport(
            owner: "octocat",
            repo: "feedback",
            token: "t",
            session: makeSession()
        )

        do {
            _ = try await transport.submit(
                FeedbackReport(type: .bug, title: "t", description: "d"),
                deviceInfo: device
            )
            XCTFail("Expected throw")
        } catch let FeedbackSubmissionError.httpStatus(code, body) {
            XCTAssertEqual(code, 422)
            XCTAssertEqual(body, #"{"message":"validation failed"}"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
