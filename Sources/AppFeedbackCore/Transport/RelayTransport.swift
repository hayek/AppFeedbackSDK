import Foundation

/// A ``FeedbackTransport`` that posts reports to an **adopter-operated relay**
/// instead of to GitHub directly.
///
/// A relay holds the GitHub credential server-side, so the app binary never
/// ships a writable token. This is the recommended production path (see the
/// "Secrets" discussion in <doc:SecretsAndTokens>): the relay verifies an
/// optional CAPTCHA, enforces rate limits and payload caps, formats the issue
/// body, creates the issue with its server-held credential, and returns the
/// issue number.
///
/// `RelayTransport` is wire-compatible with the same relays the AppFeedback
/// Web and Android SDKs target — it speaks the canonical browser⇄relay HTTP
/// contract.
///
/// ```swift
/// let transport = RelayTransport(
///     endpoint: URL(string: "https://your-relay.example.com/api/feedback")!
/// )
/// let feedback = FeedbackClient(appName: "AcmeApp", transport: transport)
/// ```
///
/// The transport sends a `POST <endpoint>` request with a JSON body matching
/// the relay contract (`type`, `title`, `description`, optional `contactEmail`,
/// `extraFields`, `deviceInfo`, optional `captchaToken`). On success it decodes
/// the `{ "issueNumber": Int, "issueUrl": String }` response and returns the
/// issue number.
///
/// > Note: Attachments are **not** sent by this transport. The relay contract
/// > carries them, but the Apple SDK's attachment-upload path currently targets
/// > ``GitHubDirectTransport`` only; relay attachment support is tracked
/// > separately.
public struct RelayTransport: FeedbackTransport {

    /// Absolute URL of the adopter-operated relay, per the relay contract.
    ///
    /// The transport issues `POST <endpoint>` with `Content-Type:
    /// application/json`.
    public let endpoint: URL

    /// Optional bot-mitigation token (e.g. Cloudflare Turnstile / hCaptcha)
    /// forwarded to the relay as `captchaToken`. When `nil`, the field is
    /// omitted from the request body.
    public let captchaToken: String?

    /// The session used for the POST request. Override for tests via a
    /// `URLProtocol` stub.
    public let session: URLSession

    /// Builds a transport.
    ///
    /// - Parameters:
    ///   - endpoint: Absolute URL of your relay (per the relay contract).
    ///   - captchaToken: Optional bot-mitigation token to forward. Defaults to
    ///     `nil`, in which case the `captchaToken` field is omitted.
    ///   - session: Defaults to `.shared`. Pass an ephemeral session with a
    ///     `URLProtocol` stub in tests.
    public init(
        endpoint: URL,
        captchaToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.captchaToken = captchaToken
        self.session = session
    }

    /// Posts a report to the relay.
    ///
    /// - Parameters:
    ///   - report: The user submission. `contactEmail` is sent only when
    ///     non-`nil`.
    ///   - deviceInfo: Metadata block, sent as the structured `deviceInfo`
    ///     object.
    /// - Returns: The issue number the relay reports it created.
    /// - Throws: ``FeedbackSubmissionError`` on network, response-shape, or
    ///   HTTP errors. A non-2xx status maps to
    ///   ``FeedbackSubmissionError/httpStatus(_:body:)`` (e.g. `400` validation,
    ///   `403` CAPTCHA/auth, `502` GitHub upstream); the body, when present,
    ///   carries the relay's `{ "error": String }` payload.
    public func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int {
        let payload = RelayRequest(
            type: report.type,
            title: report.title,
            description: report.description,
            contactEmail: report.contactEmail,
            extraFields: report.extraFields,
            deviceInfo: DeviceInfoPayload(deviceInfo),
            captchaToken: captchaToken
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            return try JSONDecoder().decode(RelayResponse.self, from: data).issueNumber
        } catch {
            throw FeedbackSubmissionError.decoding(error as any Error & Sendable)
        }
    }

    // MARK: - Wire types

    /// Request body matching the relay contract. `contactEmail` and
    /// `captchaToken` are omitted when `nil` (the relay treats absent and
    /// `null` identically); `extraFields` defaults to an empty object.
    private struct RelayRequest: Encodable {
        let type: FeedbackType
        let title: String
        let description: String
        let contactEmail: String?
        let extraFields: [String: String]
        let deviceInfo: DeviceInfoPayload
        let captchaToken: String?
    }

    /// Structured device metadata, matching the contract's `deviceInfo` shape.
    private struct DeviceInfoPayload: Encodable {
        let appName: String
        let appVersion: String
        let buildNumber: String
        let model: String
        let osName: String
        let osVersion: String

        init(_ info: DeviceInfo) {
            self.appName = info.appName
            self.appVersion = info.appVersion
            self.buildNumber = info.buildNumber
            self.model = info.model
            self.osName = info.osName
            self.osVersion = info.osVersion
        }
    }

    private struct RelayResponse: Decodable {
        let issueNumber: Int
    }
}
