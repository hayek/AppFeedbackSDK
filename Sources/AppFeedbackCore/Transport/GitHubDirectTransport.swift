import Foundation

/// A ``FeedbackTransport`` that posts reports directly to the GitHub Issues
/// REST API.
///
/// The token is held in memory by the caller — this transport does **not**
/// obfuscate or persist it. Shipping a Personal Access Token inside an app
/// binary is a known security trade-off (anyone can extract it); for
/// production-volume apps prefer a server-side relay implementing
/// ``FeedbackTransport``. See <doc:SecretsAndTokens> for the full discussion.
///
/// ```swift
/// let transport = GitHubDirectTransport(
///     owner: "acme-co",
///     repo: "feedback",
///     token: SecretLoader.gitHubToken
/// )
/// let feedback = FeedbackClient(appName: "AcmeApp", transport: transport)
/// ```
///
/// The transport sends a `POST /repos/{owner}/{repo}/issues` request whose
/// body is rendered by ``IssueBodyFormatter``. On success it decodes the
/// `{"number": Int}` response and returns the GitHub issue number.
public struct GitHubDirectTransport: FeedbackTransport {

    /// GitHub username or organization that owns the inbox repository.
    public let owner: String

    /// Repository name. Must already exist; the transport does not create it.
    public let repo: String

    /// Personal Access Token with scope sufficient to open issues
    /// (`public_repo` for a public repo, `repo` for a private one).
    public let token: String

    /// The session used for the POST request. Override for tests via a
    /// `URLProtocol` stub.
    public let session: URLSession

    /// Builds a transport.
    ///
    /// - Parameters:
    ///   - owner: GitHub org or user that owns the repo.
    ///   - repo: Repo name.
    ///   - token: PAT with `issues:write` scope.
    ///   - session: Defaults to `.shared`. Pass an ephemeral session with a
    ///     `URLProtocol` stub in tests.
    public init(
        owner: String,
        repo: String,
        token: String,
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repo = repo
        self.token = token
        self.session = session
    }

    /// Posts a report to GitHub Issues.
    ///
    /// - Parameters:
    ///   - report: The user submission.
    ///   - deviceInfo: Metadata block, rendered into the body.
    /// - Returns: The created issue's number.
    /// - Throws: ``FeedbackSubmissionError`` on network, response-shape, or
    ///   HTTP errors. See the case docs for each.
    public func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int {
        var uploaded: [UploadedAttachment] = []

        if !report.attachments.isEmpty {
            do {
                try FeedbackAttachmentValidator.validate(report.attachments)
            } catch let error as FeedbackAttachmentError {
                throw FeedbackSubmissionError.attachmentValidation(error)
            }

            let processed: [FeedbackAttachment]
            do {
                processed = try report.attachments.map(ImagePreprocessor.process)
            } catch let error as FeedbackAttachmentError {
                throw FeedbackSubmissionError.attachmentValidation(error)
            }

            // Re-validate sizes post-processing.
            do {
                try FeedbackAttachmentValidator.validate(processed)
            } catch let error as FeedbackAttachmentError {
                throw FeedbackSubmissionError.attachmentValidation(error)
            }

            let uploader = AttachmentUploader(owner: owner, repo: repo, token: token, session: session)
            do {
                try await uploader.ensureBranchExists()
            } catch {
                throw FeedbackSubmissionError.attachmentUpload(filename: "", underlying: error as any Error & Sendable)
            }

            let submissionID = UUID().uuidString.lowercased()
            let sanitizedNames = AttachmentUploader.deduplicate(processed.map { AttachmentUploader.sanitize($0.filename) })

            for (i, att) in processed.enumerated() {
                do {
                    let url = try await uploader.upload(
                        data: att.data,
                        sanitizedFilename: sanitizedNames[i],
                        submissionID: submissionID
                    )
                    uploaded.append(UploadedAttachment(
                        filename: sanitizedNames[i],
                        mimeType: att.mimeType,
                        sizeBytes: att.data.count,
                        url: url
                    ))
                } catch {
                    throw FeedbackSubmissionError.attachmentUpload(
                        filename: sanitizedNames[i],
                        underlying: error as any Error & Sendable
                    )
                }
            }
        }

        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        guard let url = URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)/issues") else {
            throw FeedbackSubmissionError.invalidResponse
        }

        let payload = CreateIssueRequest(
            title: report.title,
            body: IssueBodyFormatter.format(report: report, deviceInfo: deviceInfo, uploaded: uploaded),
            labels: IssueBodyFormatter.labels(for: report.type)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedbackSubmissionError.transport(error as any Error & Sendable)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FeedbackSubmissionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedbackSubmissionError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            return try JSONDecoder().decode(IssueResponse.self, from: data).number
        } catch {
            throw FeedbackSubmissionError.decoding(error as any Error & Sendable)
        }
    }

    // MARK: - Wire types

    private struct CreateIssueRequest: Encodable {
        let title: String
        let body: String
        let labels: [String]
    }

    private struct IssueResponse: Decodable {
        let number: Int
    }
}
