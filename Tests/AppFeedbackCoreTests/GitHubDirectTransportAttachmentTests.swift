import XCTest
@testable import AppFeedbackCore

final class GitHubDirectTransportAttachmentTests: XCTestCase {

    override func setUp() { super.setUp(); URLProtocolStub.reset() }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    func test_branch_already_exists_short_circuits() async throws {
        URLProtocolStub.respond { req in
            XCTAssertEqual(req.url?.path, "/repos/octocat/feedback/branches/feedback-attachments")
            XCTAssertEqual(req.httpMethod, "GET")
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                #"{"name":"feedback-attachments"}"#.data(using: .utf8)!
            )
        }
        let uploader = AttachmentUploader(
            owner: "octocat", repo: "feedback", token: "t", session: makeSession()
        )
        try await uploader.ensureBranchExists()
    }

    func test_missing_branch_is_created_from_default_branch() async throws {
        URLProtocolStub.enqueue([
            // 1. branch-check 404
            { req in
                XCTAssertEqual(req.url?.path, "/repos/octocat/feedback/branches/feedback-attachments")
                return (
                    HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            },
            // 2. fetch repo → default_branch
            { req in
                XCTAssertEqual(req.url?.path, "/repos/octocat/feedback")
                return (
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    #"{"default_branch":"main"}"#.data(using: .utf8)!
                )
            },
            // 3. fetch ref SHA
            { req in
                XCTAssertEqual(req.url?.path, "/repos/octocat/feedback/git/refs/heads/main")
                return (
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    #"{"object":{"sha":"abc123"}}"#.data(using: .utf8)!
                )
            },
            // 4. create ref
            { req in
                XCTAssertEqual(req.url?.path, "/repos/octocat/feedback/git/refs")
                XCTAssertEqual(req.httpMethod, "POST")
                let body = try! JSONSerialization.jsonObject(with: req.bodyData ?? Data()) as! [String: Any]
                XCTAssertEqual(body["ref"] as? String, "refs/heads/feedback-attachments")
                XCTAssertEqual(body["sha"] as? String, "abc123")
                return (
                    HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            },
        ])
        let uploader = AttachmentUploader(
            owner: "octocat", repo: "feedback", token: "t", session: makeSession()
        )
        try await uploader.ensureBranchExists()
    }
}
