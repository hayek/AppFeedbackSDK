# Custom Transports

Replace ``GitHubDirectTransport`` with a relay server, a mock, or any other backend by conforming to ``FeedbackTransport``.

## Overview

``FeedbackClient`` knows nothing about GitHub. All it does is collect ``DeviceInfo`` and hand the ``FeedbackReport`` to its ``FeedbackTransport``. Anything that can produce an `Int` from that pair is a valid transport.

```swift
public protocol FeedbackTransport: Sendable {
    func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int
}
```

## A relay transport

The most common reason to replace the default transport is to avoid shipping a GitHub PAT inside the app binary (see <doc:SecretsAndTokens>). A small relay server holds the credential, exposes a thin HTTPS endpoint, and applies abuse controls. The client then looks like this:

```swift
public struct RelayTransport: FeedbackTransport {
    public let endpoint: URL
    public let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func submit(_ report: FeedbackReport, deviceInfo: DeviceInfo) async throws -> Int {
        struct Payload: Encodable {
            let type: String
            let title: String
            let description: String
            let email: String?
            let appName: String
            let appVersion: String
            let buildNumber: String
            let model: String
            let osName: String
            let osVersion: String
        }
        let payload = Payload(
            type: report.type.rawValue,
            title: report.title,
            description: report.description,
            email: report.contactEmail,
            appName: deviceInfo.appName,
            appVersion: deviceInfo.appVersion,
            buildNumber: deviceInfo.buildNumber,
            model: deviceInfo.model,
            osName: deviceInfo.osName,
            osVersion: deviceInfo.osVersion
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

Pass it to ``FeedbackClient/init(transport:deviceInfo:)`` with a fixed ``DeviceInfo`` for fully deterministic tests.

## Error contract

Transports should throw ``FeedbackSubmissionError`` for known conditions and let other errors propagate. The SDK's UI layer ``AppFeedbackUI/FeedbackSheet`` displays `error.localizedDescription` in an alert, so make sure your errors conform to `LocalizedError` if you want friendly messages.

## Topics

- ``FeedbackTransport``
- ``GitHubDirectTransport``
- ``FeedbackSubmissionError``
