import Foundation

/// The entry point for submitting feedback.
///
/// Build one `FeedbackClient` at app start, hold a reference, and call
/// ``submit(_:)`` from anywhere. The client itself is a value type — it stores
/// a transport and a closure for collecting ``DeviceInfo``, and is safe to
/// pass across actor boundaries.
///
/// ## Two ways to construct
///
/// The common case uses ``init(appName:transport:)``, which collects
/// ``DeviceInfo`` lazily on every submission:
///
/// ```swift
/// let feedback = FeedbackClient(
///     appName: "AcmeApp",
///     transport: GitHubDirectTransport(owner: "acme", repo: "feedback", token: token)
/// )
/// ```
///
/// For tests or fully deterministic submissions, freeze a ``DeviceInfo``
/// instance with ``init(transport:deviceInfo:)``:
///
/// ```swift
/// let feedback = FeedbackClient(
///     transport: NoOpTransport(),
///     deviceInfo: DeviceInfo(...)
/// )
/// ```
///
/// ## Why lazy device info
///
/// A long-lived client built at app start might submit feedback hours or
/// days later, possibly across an app update. Collecting ``DeviceInfo``
/// per submission means the version and OS reported always reflect the
/// process state at submission time, not at client construction time.
public struct FeedbackClient: Sendable {
    private let transport: any FeedbackTransport
    private let deviceInfoProvider: @Sendable () -> DeviceInfo

    /// Builds a client that collects fresh ``DeviceInfo`` on every submission.
    ///
    /// - Parameters:
    ///   - appName: Overrides the auto-detected `CFBundleDisplayName` /
    ///     `CFBundleName`. Pass `nil` to use the bundle value.
    ///   - transport: Where reports get delivered. Use
    ///     ``GitHubDirectTransport`` to POST directly to GitHub Issues, or
    ///     conform to ``FeedbackTransport`` for a relay or mock.
    public init(
        appName: String? = nil,
        transport: any FeedbackTransport
    ) {
        self.transport = transport
        self.deviceInfoProvider = { DeviceInfo.current(appName: appName) }
    }

    /// Builds a client that uses a frozen ``DeviceInfo`` for every submission.
    ///
    /// Useful for tests, screenshots, or apps that want to override one or
    /// more device fields. The same `deviceInfo` is sent every time
    /// ``submit(_:)`` is called.
    ///
    /// - Parameters:
    ///   - transport: Where reports get delivered.
    ///   - deviceInfo: The metadata block attached to every submission.
    public init(
        transport: any FeedbackTransport,
        deviceInfo: DeviceInfo
    ) {
        self.transport = transport
        self.deviceInfoProvider = { deviceInfo }
    }

    /// Submits a report and returns the backend-assigned identifier.
    ///
    /// For ``GitHubDirectTransport`` the return value is the created GitHub
    /// issue number. Other transports may return whatever identifier their
    /// backend uses.
    ///
    /// - Parameter report: The user-supplied content. The transport renders
    ///   it into the wire format and attaches device info.
    /// - Returns: A backend-defined identifier (`Int`).
    /// - Throws: ``FeedbackSubmissionError`` for known failures from
    ///   ``GitHubDirectTransport``, or whatever the active transport throws.
    @discardableResult
    public func submit(_ report: FeedbackReport) async throws -> Int {
        try await transport.submit(report, deviceInfo: deviceInfoProvider())
    }
}
