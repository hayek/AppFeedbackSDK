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
/// The common case uses ``init(appName:transport:analytics:)``, which collects
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
/// instance with ``init(transport:deviceInfo:analytics:)``:
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

    /// The optional analytics sink, also read by `AppFeedbackUI`'s sheet so the
    /// whole funnel lands in one place. `package` rather than `public`: the UI
    /// target needs it, adopters never do, and it stays out of the public API.
    package let analytics: (any FeedbackAnalytics)?

    /// Builds a client that collects fresh ``DeviceInfo`` on every submission.
    ///
    /// - Parameters:
    ///   - appName: Overrides the auto-detected `CFBundleDisplayName` /
    ///     `CFBundleName`. Pass `nil` to use the bundle value.
    ///   - transport: Where reports get delivered. Use
    ///     ``GitHubDirectTransport`` to POST directly to GitHub Issues, or
    ///     conform to ``FeedbackTransport`` for a relay or mock.
    ///   - analytics: Optional sink for ``FeedbackEvent``. Configure it here and
    ///     nowhere else: `FeedbackSheet` reads it from the client,
    ///     so one object receives the submission lifecycle *and* the UI funnel.
    ///     Defaults to `nil`, which is a genuine no-op.
    public init(
        appName: String? = nil,
        transport: any FeedbackTransport,
        analytics: (any FeedbackAnalytics)? = nil
    ) {
        self.transport = transport
        self.deviceInfoProvider = { DeviceInfo.current(appName: appName) }
        self.analytics = analytics
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
    ///   - analytics: Optional sink for ``FeedbackEvent``. See
    ///     ``init(appName:transport:analytics:)``.
    public init(
        transport: any FeedbackTransport,
        deviceInfo: DeviceInfo,
        analytics: (any FeedbackAnalytics)? = nil
    ) {
        self.transport = transport
        self.deviceInfoProvider = { deviceInfo }
        self.analytics = analytics
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
        // The client is the sole emitter of submission events; the sheet never
        // re-emits them, so a submission can't be counted twice.
        analytics?.record(.submissionStarted(
            report.type,
            attachmentCount: report.attachments.count,
            hasContactEmail: report.contactEmail != nil
        ))
        do {
            let issueNumber = try await transport.submit(report, deviceInfo: deviceInfoProvider())
            analytics?.record(.submissionSucceeded(report.type, issueNumber: issueNumber))
            return issueNumber
        } catch {
            analytics?.record(.submissionFailed(report.type, error: error))
            throw error
        }
    }
}
