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

extension GitHubDirectTransportAttachmentTests {

    func test_upload_puts_to_contents_api_with_base64_body_and_returns_download_url() async throws {
        URLProtocolStub.respond { req in
            XCTAssertEqual(req.url?.path, "/repos/octocat/feedback/contents/attachments/sub-1/shot.png")
            XCTAssertEqual(req.url?.query, nil)
            XCTAssertEqual(req.httpMethod, "PUT")
            let body = try! JSONSerialization.jsonObject(with: req.bodyData ?? Data()) as! [String: Any]
            XCTAssertEqual(body["branch"] as? String, "feedback-attachments")
            XCTAssertNotNil(body["message"] as? String)
            let content = body["content"] as! String
            XCTAssertEqual(Data(base64Encoded: content), Data("imagebytes".utf8))
            return (
                HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                #"""
                {"content":{"download_url":"https://raw.githubusercontent.com/octocat/feedback/feedback-attachments/attachments/sub-1/shot.png"}}
                """#.data(using: .utf8)!
            )
        }
        let uploader = AttachmentUploader(
            owner: "octocat", repo: "feedback", token: "t", session: makeSession()
        )
        let url = try await uploader.upload(
            data: Data("imagebytes".utf8),
            sanitizedFilename: "shot.png",
            submissionID: "sub-1"
        )
        XCTAssertEqual(url.absoluteString,
                       "https://raw.githubusercontent.com/octocat/feedback/feedback-attachments/attachments/sub-1/shot.png")
    }

    func test_upload_dedups_same_submission_filename_with_n_suffix() {
        let inputs = [
            FeedbackAttachment(filename: "shot.png", mimeType: "image/png", data: Data([1])),
            FeedbackAttachment(filename: "shot.png", mimeType: "image/png", data: Data([2])),
            FeedbackAttachment(filename: "shot.png", mimeType: "image/png", data: Data([3])),
        ]
        let deduped = AttachmentUploader.deduplicate(inputs.map(\.filename))
        XCTAssertEqual(deduped, ["shot.png", "shot (2).png", "shot (3).png"])
    }

    func test_filename_sanitization_strips_path_and_bad_chars() {
        XCTAssertEqual(AttachmentUploader.sanitize("../etc/passwd"), "passwd")
        XCTAssertEqual(AttachmentUploader.sanitize("a/b/c.png"), "c.png")
        XCTAssertEqual(AttachmentUploader.sanitize(""), "file.bin")
        XCTAssertEqual(AttachmentUploader.sanitize("   "), "file.bin")
    }
}
