import Foundation

/// Whether a feedback submission is a bug report or a feature request.
///
/// The raw value of each case is **also** the GitHub label string used by the
/// AppFeedback inbox to categorize the issue. Changing these values would
/// silently break inbox filtering, so they're part of the wire contract.
///
/// ```swift
/// FeedbackType.bug.rawValue            // "bug"
/// FeedbackType.featureRequest.rawValue // "feature-request"
/// ```
///
/// See ``IssueBodyFormatter/labels(for:)`` for the full label set applied to
/// each submission.
public enum FeedbackType: String, Sendable, CaseIterable, Codable, Hashable {

    /// Something is broken or not working as expected.
    case bug

    /// A request for new behavior or an enhancement to existing behavior.
    case featureRequest = "feature-request"
}
