import XCTest
@testable import AppFeedbackCore

final class RelayTransportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private let endpoint = URL(string: "https://relay.example.com/api/feedback")!

    private let device = DeviceInfo(
        appName: "AcmeApp",
        appVersion: "1.2.3",
        buildNumber: "456",
        model: "Mac15,11",
        osName: "macOS",
        osVersion: "Version 15.1 (Build 24B83)"
    )

    func test_posts_contract_body_and_returns_issue_number() async throws {
        URLProtocolStub.respond { request in
            XCTAssertEqual(request.url?.absoluteString, "https://relay.example.com/api/feedback")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let bodyData = request.bodyData ?? Data()
            let decoded = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]

            // type carries the raw label string, not a Swift case name.
            XCTAssertEqual(decoded["type"] as? String, "feature-request")
            XCTAssertEqual(decoded["title"] as? String, "Add dark mode")
            XCTAssertEqual(decoded["description"] as? String, "Please add a dark theme")
            XCTAssertEqual(decoded["contactEmail"] as? String, "user@example.com")

            let extra = decoded["extraFields"] as? [String: String]
            XCTAssertEqual(extra?["plan"], "pro")

            let info = decoded["deviceInfo"] as? [String: Any]
            XCTAssertEqual(info?["appName"] as? String, "AcmeApp")
            XCTAssertEqual(info?["appVersion"] as? String, "1.2.3")
            XCTAssertEqual(info?["buildNumber"] as? String, "456")
            XCTAssertEqual(info?["model"] as? String, "Mac15,11")
            XCTAssertEqual(info?["osName"] as? String, "macOS")
            XCTAssertEqual(info?["osVersion"] as? String, "Version 15.1 (Build 24B83)")

            // captchaToken absent when not configured.
            XCTAssertNil(decoded["captchaToken"])

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                #"{"issueNumber":1234,"issueUrl":"https://github.com/acme/feedback/issues/1234"}"#.data(using: .utf8)!
            )
        }

        let transport = RelayTransport(endpoint: endpoint, session: makeSession())

        let issueNumber = try await transport.submit(
            FeedbackReport(
                type: .featureRequest,
                title: "Add dark mode",
                description: "Please add a dark theme",
                contactEmail: "user@example.com",
                extraFields: ["plan": "pro"]
            ),
            deviceInfo: device
        )

        XCTAssertEqual(issueNumber, 1234)
    }

    func test_omits_contactEmail_when_nil_and_fetches_fresh_captchaToken_per_submit() async throws {
        // The provider mints a *different* token on each call. A correct
        // implementation invokes it per submission, so each request body must
        // carry that submission's freshly-returned token — never a stale one
        // captured at construction time.
        let providerCalls = TokenCounter()
        let captchaTokens = TokenRecorder()

        URLProtocolStub.respond { request in
            let bodyData = request.bodyData ?? Data()
            let decoded = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]

            // contactEmail is absent (not null) when the report has none.
            XCTAssertNil(decoded["contactEmail"])
            XCTAssertFalse(decoded.keys.contains("contactEmail"))
            XCTAssertEqual(decoded["type"] as? String, "bug")

            captchaTokens.record(decoded["captchaToken"] as? String)

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                #"{"issueNumber":7,"issueUrl":"https://x/issues/7"}"#.data(using: .utf8)!
            )
        }

        let transport = RelayTransport(
            endpoint: endpoint,
            captchaTokenProvider: { "turnstile-\(providerCalls.next())" },
            session: makeSession()
        )

        let report = FeedbackReport(type: .bug, title: "Crash", description: "Boom")

        let first = try await transport.submit(report, deviceInfo: device)
        let second = try await transport.submit(report, deviceInfo: device)

        XCTAssertEqual(first, 7)
        XCTAssertEqual(second, 7)

        // Provider invoked once per submit (not once at construction).
        XCTAssertEqual(providerCalls.count, 2)
        // Each request carried its own freshly-minted token, in order.
        XCTAssertEqual(captchaTokens.recorded, ["turnstile-1", "turnstile-2"])
    }

    func test_omits_captchaToken_when_no_provider() async throws {
        let captchaTokens = TokenRecorder()
        URLProtocolStub.respond { request in
            let bodyData = request.bodyData ?? Data()
            let decoded = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            // captchaToken absent (not null) when no provider is configured.
            XCTAssertNil(decoded["captchaToken"])
            XCTAssertFalse(decoded.keys.contains("captchaToken"))
            captchaTokens.record(decoded["captchaToken"] as? String)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                #"{"issueNumber":9,"issueUrl":"https://x/issues/9"}"#.data(using: .utf8)!
            )
        }

        let transport = RelayTransport(endpoint: endpoint, session: makeSession())
        let issueNumber = try await transport.submit(
            FeedbackReport(type: .bug, title: "Crash", description: "Boom"),
            deviceInfo: device
        )
        XCTAssertEqual(issueNumber, 9)
        XCTAssertEqual(captchaTokens.recorded, [nil])
    }

    func test_validation_400_throws_httpStatus_with_error_body() async {
        URLProtocolStub.respond { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                #"{"error":"invalid submission"}"#.data(using: .utf8)!
            )
        }

        let transport = RelayTransport(endpoint: endpoint, session: makeSession())

        do {
            _ = try await transport.submit(
                FeedbackReport(type: .bug, title: "t", description: "d"),
                deviceInfo: device
            )
            XCTFail("Expected throw")
        } catch let FeedbackSubmissionError.httpStatus(code, body) {
            XCTAssertEqual(code, 400)
            XCTAssertEqual(body, #"{"error":"invalid submission"}"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_forbidden_403_throws_httpStatus() async {
        URLProtocolStub.respond { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                #"{"error":"captcha verification failed"}"#.data(using: .utf8)!
            )
        }

        let transport = RelayTransport(endpoint: endpoint, session: makeSession())

        do {
            _ = try await transport.submit(
                FeedbackReport(type: .bug, title: "t", description: "d"),
                deviceInfo: device
            )
            XCTFail("Expected throw")
        } catch let FeedbackSubmissionError.httpStatus(code, _) {
            XCTAssertEqual(code, 403)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_upstream_502_throws_httpStatus() async {
        URLProtocolStub.respond { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!,
                #"{"error":"GitHub upstream error (503)"}"#.data(using: .utf8)!
            )
        }

        let transport = RelayTransport(endpoint: endpoint, session: makeSession())

        do {
            _ = try await transport.submit(
                FeedbackReport(type: .bug, title: "t", description: "d"),
                deviceInfo: device
            )
            XCTFail("Expected throw")
        } catch let FeedbackSubmissionError.httpStatus(code, _) {
            XCTAssertEqual(code, 502)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test helpers

/// Thread-safe call counter — the `@Sendable` captcha provider may run off the
/// test's task, so plain mutable state isn't safe to capture.
private final class TokenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Increments and returns the new count.
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

/// Thread-safe recorder of the `captchaToken` seen in each request body.
private final class TokenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []

    func record(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        values.append(token)
    }

    var recorded: [String?] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
