/// A required field the user left empty.
///
/// Reported instead of the field's on-screen label: that copy is themable and
/// localized, so a German adopter would otherwise report `"Titel"` and an
/// English one `"Title"`, fragmenting the same funnel step by locale and theme.
public enum FeedbackField: String, Sendable, Hashable, CaseIterable {
    case title
    case description
}

/// Where an attachment came from.
///
/// Distinguishes the four ways a file enters the sheet, which is what answers
/// "is the photo picker actually being used?".
public enum AttachmentSource: String, Sendable, Hashable, CaseIterable {
    /// The system file importer.
    case files
    /// The iOS photo picker.
    case photoLibrary = "photo_library"
    /// ⌘V on macOS.
    case paste
    /// Drag-and-drop onto the sheet on macOS.
    case drop
}

/// Why a submission did not lead to the App Store rating prompt.
///
/// Answers "why aren't my users being asked to rate?", which is otherwise
/// invisible — the praise check is on-device and silent by design.
public enum RatingPromptSuppressionReason: String, Sendable, Hashable, CaseIterable {

    /// `requestsAppStoreReview` was `false`.
    case disabled

    /// Apple Intelligence could not be reached: an OS below 26, a build with no
    /// Foundation Models SDK, ineligible hardware, the feature switched off, or
    /// the model still downloading.
    case appleIntelligenceUnavailable = "apple_intelligence_unavailable"

    /// The model read the feedback and judged it not to be unqualified praise.
    case notPraise = "not_praise"

    /// The model failed rather than answered — a guardrail trip, a refusal, an
    /// unsupported language, or a context overflow.
    case classifierFailed = "classifier_failed"

    /// No verdict arrived before the deadline.
    case classificationTimedOut = "classification_timed_out"

    /// The sheet was dismissed before the prompt could be presented.
    case dismissed
}
