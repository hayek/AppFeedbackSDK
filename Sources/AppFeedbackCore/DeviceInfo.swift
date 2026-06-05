import Foundation
#if os(macOS)
import Darwin
#endif

/// Per-submission metadata about the host app and device.
///
/// Every submission attaches a `DeviceInfo` block to the issue body. The
/// AppFeedback inbox parses it back out into typed columns (app name, version,
/// device model, OS version) so triage can filter by platform.
///
/// In most apps you'll use ``current(appName:)`` and never construct this
/// directly:
///
/// ```swift
/// let info = DeviceInfo.current(appName: "AcmeApp")
/// ```
///
/// For tests or to override the auto-detected OS name (for example to
/// distinguish iPadOS from iOS), construct one explicitly:
///
/// ```swift
/// let info = DeviceInfo(
///     appName: "AcmeApp",
///     appVersion: "1.2.3",
///     buildNumber: "456",
///     model: "iPad14,1",
///     osName: "iPadOS",
///     osVersion: "Version 18.2 (Build 22C150)"
/// )
/// ```
public struct DeviceInfo: Sendable, Equatable, Hashable {

    /// Display name of the host app. Default sources are
    /// `CFBundleDisplayName` then `CFBundleName`.
    public let appName: String

    /// Marketing version, e.g. `"1.2.3"`. Sourced from
    /// `CFBundleShortVersionString`.
    public let appVersion: String

    /// Build / CI version, e.g. `"456"`. Sourced from `CFBundleVersion`.
    public let buildNumber: String

    /// Hardware model identifier, e.g. `"MacBookPro18,1"` or `"iPhone15,2"`.
    ///
    /// macOS uses `sysctlbyname("hw.model")`; other Apple platforms use the
    /// `utsname.machine` identifier.
    public let model: String

    /// Human-readable platform name. Apple platforms use one of `"macOS"`,
    /// `"iOS"`, `"iPadOS"`, `"watchOS"`, `"tvOS"`, `"visionOS"`; other platforms
    /// use `"Android"`, `"Windows"`, `"Linux"`, `"Web"`, or `"ChromeOS"` (the
    /// generic `"OS"` is also accepted). These are the names the inbox parser
    /// recognises for the OS column.
    ///
    /// On iOS, ``current(appName:)`` returns `"iOS"` even on iPad — pass an
    /// explicit `osName` here if you need to distinguish iPadOS in the inbox.
    public let osName: String

    /// Full OS version string, typically
    /// `"Version 14.5 (Build 23F79)"`. Sourced from
    /// `ProcessInfo.processInfo.operatingSystemVersionString`.
    public let osVersion: String

    /// Builds a `DeviceInfo` with every field specified.
    ///
    /// Use this for tests, screenshots, or when you want to override one or
    /// more of the auto-detected values.
    public init(
        appName: String,
        appVersion: String,
        buildNumber: String,
        model: String,
        osName: String,
        osVersion: String
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
    }

    /// Auto-detects the host app + device metadata.
    ///
    /// - Parameter overrideName: Optional app-name override. When `nil`, the
    ///   bundle's `CFBundleDisplayName` (then `CFBundleName`) is used.
    /// - Returns: A `DeviceInfo` instance for the current process.
    public static func current(appName overrideName: String? = nil) -> DeviceInfo {
        let snapshot = Self.processSnapshot
        return DeviceInfo(
            appName: overrideName ?? snapshot.appName,
            appVersion: snapshot.appVersion,
            buildNumber: snapshot.buildNumber,
            model: snapshot.model,
            osName: snapshot.osName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    /// Renders this device info as the block that goes inside the issue body.
    ///
    /// The output is multi-line plain text in the exact shape
    /// ``IssueBodyParser`` understands. See <doc:BodyFormat> for the full spec.
    public func renderForIssueBody() -> String {
        """
        \(BodyMarker.appLabel) \(appName)
        \(BodyMarker.appVersionLabel) \(appVersion) (\(buildNumber))
        \(BodyMarker.deviceLabel) \(model)
        \(osName)\(BodyMarker.osVersionSuffix) \(osVersion)
        """
    }

    // MARK: - Snapshot

    /// Process-immutable values collected once at first access. Cached because
    /// `Bundle.main.infoDictionary` and `sysctlbyname` allocate per call, and
    /// these never change for the lifetime of the process.
    private struct ProcessSnapshot: Sendable {
        let appName: String
        let appVersion: String
        let buildNumber: String
        let model: String
        let osName: String
    }

    private static let processSnapshot: ProcessSnapshot = {
        ProcessSnapshot(
            appName: bundleAppName(),
            appVersion: bundleAppVersion(),
            buildNumber: bundleBuildNumber(),
            model: machineModel(),
            osName: compileTimeOSName
        )
    }()

    // MARK: - Collectors

    private static func bundleAppName() -> String {
        (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? "Unknown"
    }

    private static func bundleAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private static func bundleBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private static func machineModel() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        if let nulIndex = bytes.firstIndex(of: 0) { bytes.removeSubrange(nulIndex..<bytes.count) }
        return String(decoding: bytes, as: UTF8.self)
        #else
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: &info.machine) { raw -> String in
            let bytes = raw.bindMemory(to: UInt8.self)
            let nul = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<nul], as: UTF8.self)
        }
        return identifier.isEmpty ? "Unknown" : identifier
        #endif
    }

    /// Compile-time OS name. On iOS we deliberately return `"iOS"` for both
    /// iPhone and iPad — distinguishing iPadOS would require reading
    /// `UIDevice.current` from a MainActor context, which doesn't compose well
    /// with the rest of the SDK being nonisolated. Callers wanting iPadOS in
    /// the inbox can override via ``init(appName:appVersion:buildNumber:model:osName:osVersion:)``.
    private static let compileTimeOSName: String = {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "Unknown"
        #endif
    }()
}
