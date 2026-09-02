# Custom Transports

Replace ``GitHubDirectTransport`` with a relay server, a mock, or any other backend by conforming to ``FeedbackTransport``.

## Overview

``FeedbackClient`` knows nothing about GitHub. All it does is collect ``DeviceInfo`` and hand the ``FeedbackReport`` to its ``FeedbackTransport``. Anything that can produce an `Int` from that pair is a valid transport.

```swift
public protocol FeedbackTransport: Sendable {
    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int
}
```

## Use the built-in relay transport

The most common reason to replace the default transport is to avoid shipping a GitHub PAT inside the app binary (see <doc:SecretsAndTokens>). A relay server holds the credential, exposes a thin HTTPS endpoint, and applies abuse controls. **You don't have to write this transport** — the SDK ships ``RelayTransport``, which speaks the canonical relay contract (the same one the AppFeedback Web and Android SDKs target):

```swift
let transport = RelayTransport(
    endpoint: URL(string: "https://your-relay.example.com/api/feedback")!,
    captchaTokenProvider: { await captcha.freshToken() }  // optional, fetched per submit
)
let feedback = FeedbackClient(appName: "AcmeApp", transport: transport)
```

``RelayTransport`` POSTs a JSON body with `type`, `title`, `description`, optional `contactEmail`, `extraFields`, a nested `deviceInfo` object, and optional `captchaToken`, then decodes the relay's `{ "issueNumber", "issueUrl" }` response. No GitHub credential ever ships in the app binary.

The optional `captchaTokenProvider` is an `async` closure invoked **once per submission**, so each request carries a fresh Turnstile/hCaptcha token — these are single-use and expire in minutes, and the transport outlives any one submission. Return `nil` (or omit the provider) to leave `captchaToken` out of the body.

## Writing your own relay transport

If your backend speaks a different protocol, conform to ``FeedbackTransport`` directly. The example below mirrors the same wire shape ``RelayTransport`` uses — a nested `deviceInfo` object, `contactEmail` (not `email`), and `extraFields` plus an optional `captchaToken`:

```swift
public struct MyRelayTransport: FeedbackTransport {
    public let endpoint: URL
    public let captchaToken: String?
    public let session: URLSession

    public init(endpoint: URL, captchaToken: String? = nil, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.captchaToken = captchaToken
        self.session = session
    }

    public func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int {
        struct DeviceInfoPayload: Encodable {
            let appName: String
            let appVersion: String
            let buildNumber: String
            let model: String
            let osName: String
            let osVersion: String
        }
        struct Payload: Encodable {
            let type: FeedbackType
            let title: String
            let description: String
            let contactEmail: String?
            let extraFields: [String: String]
            let deviceInfo: DeviceInfoPayload
            let captchaToken: String?
        }
        let payload = Payload(
            type: report.type,
            title: report.title,
            description: report.description,
            contactEmail: report.contactEmail,
            extraFields: report.extraFields,
            deviceInfo: DeviceInfoPayload(
                appName: deviceInfo.appName,
                appVersion: deviceInfo.appVersion,
                buildNumber: deviceInfo.buildNumber,
                model: deviceInfo.model,
                osName: deviceInfo.osName,
                osVersion: deviceInfo.osVersion
            ),
            captchaToken: captchaToken
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackSubmissionError.invalidResponse
        }

        struct Response: Decodable { let issueNumber: Int }
        return try JSONDecoder().decode(Response.self, from: data).issueNumber
    }
}
```

Your relay can then call GitHub itself using ``IssueBodyFormatter`` for the body, or store the report in a database, or fan it out to multiple destinations — the client is unchanged.

## A test transport

For unit tests, build a transport that records calls and returns a canned result:

```swift
final class RecordingTransport: FeedbackTransport, @unchecked Sendable {
    private(set) var submitted: [(FeedbackReport, DeviceInfo)] = []
    var nextResult: Result<Int, any Error> = .success(0)

    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int {
        submitted.append((report, deviceInfo))
        return try nextResult.get()
    }
}
```

Pass it to ``FeedbackClient/init(transport:deviceInfo:analytics:)`` with a fixed ``DeviceInfo`` for fully deterministic tests.

## Error contract

Transports should throw ``FeedbackSubmissionError`` for known conditions and let other errors propagate. The SDK's UI layer ``AppFeedbackUI/FeedbackSheet`` displays `error.localizedDescription` in an alert, so make sure your errors conform to `LocalizedError` if you want friendly messages.

## Topics

- ``FeedbackTransport``
- ``GitHubDirectTransport``
- ``RelayTransport``
- ``FeedbackSubmissionError``
