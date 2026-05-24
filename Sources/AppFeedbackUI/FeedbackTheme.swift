import SwiftUI

/// Visual + copy customization for ``FeedbackSheet``.
///
/// Construct one of these (or use ``default``) and pass it to the sheet:
///
/// ```swift
/// FeedbackSheet(
///     client: feedback,
///     theme: FeedbackTheme(
///         bugAccent: .red,
///         featureAccent: .blue,
///         copy: .default
///     )
/// )
/// ```
///
/// All copy strings are plain `String` rather than `LocalizedStringKey` so
/// integrators can pass already-localized text from their own bundle (see
/// <doc:Localization>). The SDK doesn't ship a strings table.
public struct FeedbackTheme: Sendable {

    /// Accent color used when the user selects "Bug" — drives the hero
    /// gradient, type-card highlight, and success ring.
    public var bugAccent: Color

    /// Accent color used when the user selects "Feature request".
    public var featureAccent: Color

    /// All visible text on the sheet. See ``Copy`` for the full field list.
    public var copy: Copy

    /// Builds a theme.
    public init(bugAccent: Color, featureAccent: Color, copy: Copy) {
        self.bugAccent = bugAccent
        self.featureAccent = featureAccent
        self.copy = copy
    }

    /// A balanced default: red bug accent, blue/purple feature accent,
    /// English copy. Suitable for getting started; override either or both
    /// to match your brand.
    public static let `default` = FeedbackTheme(
        bugAccent: Color(red: 0.95, green: 0.30, blue: 0.40),
        featureAccent: Color(red: 0.45, green: 0.45, blue: 1.0),
        copy: .default
    )

    /// Every visible string on the sheet.
    ///
    /// Fields are plain `String` so integrators can supply pre-localized
    /// text from their own bundle. See <doc:Localization> for an example
    /// wiring `String(localized:)` against a `.xcstrings` catalog.
    public struct Copy: Sendable {

        /// Large heading at the top of the form. Defaults to `"Send Feedback"`.
        public var headerTitle: String

        /// Subtitle shown under the heading while "Bug" is selected.
        public var bugSubtitle: String

        /// Subtitle shown under the heading while "Feature request" is selected.
        public var featureSubtitle: String

        /// Label for the bug card in the type selector.
        public var bugLabel: String

        /// One-line description under the bug card label.
        public var bugTagline: String

        /// Label for the feature-request card in the type selector.
        public var featureLabel: String

        /// One-line description under the feature card label.
        public var featureTagline: String

        /// Section label above the title text field.
        public var titleLabel: String

        /// Name used in the validation prompt when title is empty.
        public var titleFieldName: String

        /// Placeholder text inside the empty title field.
        public var titlePlaceholder: String

        /// Section label above the description text editor.
        public var descriptionLabel: String

        /// Name used in the validation prompt when description is empty.
        public var descriptionFieldName: String

        /// Placeholder text inside the empty description editor.
        public var descriptionPlaceholder: String

        /// Section label above the email field.
        public var emailLabel: String

        /// Pill-shaped "Optional" badge next to the email label.
        public var emailOptionalBadge: String

        /// Placeholder text inside the empty email field.
        public var emailPlaceholder: String

        /// Hint text under the email field explaining why we collect it.
        public var emailHint: String

        /// Privacy disclosure shown below the form. Tell users that device
        /// info will be auto-attached.
        public var privacyNotice: String

        /// Footer submit button label.
        public var submitButton: String

        /// Success-screen dismiss button label.
        public var doneButton: String

        /// Headline on the success screen after submission completes.
        public var successTitle: String

        /// Subhead text on the success screen.
        public var successMessage: String

        /// Section label above the attachments row.
        public var attachmentsLabel: String

        /// Alert title used when the transport throws.
        public var errorAlertTitle: String

        /// Template used for "Please fill in: {fields}". The literal token
        /// `{fields}` is replaced with a comma-joined list of missing
        /// field names — see <doc:Localization>.
        public var validationPromptTemplate: String

        /// Builds a `Copy` block with every field specified.
        public init(
            headerTitle: String,
            bugSubtitle: String,
            featureSubtitle: String,
            bugLabel: String,
            bugTagline: String,
            featureLabel: String,
            featureTagline: String,
            titleLabel: String,
            titleFieldName: String,
            titlePlaceholder: String,
            descriptionLabel: String,
            descriptionFieldName: String,
            descriptionPlaceholder: String,
            emailLabel: String,
            emailOptionalBadge: String,
            emailPlaceholder: String,
            emailHint: String,
            privacyNotice: String,
            attachmentsLabel: String = "Attachments",
            submitButton: String,
            doneButton: String,
            successTitle: String,
            successMessage: String,
            errorAlertTitle: String,
            validationPromptTemplate: String
        ) {
            self.headerTitle = headerTitle
            self.bugSubtitle = bugSubtitle
            self.featureSubtitle = featureSubtitle
            self.bugLabel = bugLabel
            self.bugTagline = bugTagline
            self.featureLabel = featureLabel
            self.featureTagline = featureTagline
            self.titleLabel = titleLabel
            self.titleFieldName = titleFieldName
            self.titlePlaceholder = titlePlaceholder
            self.descriptionLabel = descriptionLabel
            self.descriptionFieldName = descriptionFieldName
            self.descriptionPlaceholder = descriptionPlaceholder
            self.emailLabel = emailLabel
            self.emailOptionalBadge = emailOptionalBadge
            self.emailPlaceholder = emailPlaceholder
            self.emailHint = emailHint
            self.privacyNotice = privacyNotice
            self.attachmentsLabel = attachmentsLabel
            self.submitButton = submitButton
            self.doneButton = doneButton
            self.successTitle = successTitle
            self.successMessage = successMessage
            self.errorAlertTitle = errorAlertTitle
            self.validationPromptTemplate = validationPromptTemplate
        }

        /// English defaults suitable for prototyping.
        public static let `default` = Copy(
            headerTitle: "Send Feedback",
            bugSubtitle: "Report an issue you've encountered",
            featureSubtitle: "Suggest a new feature or improvement",
            bugLabel: "Bug",
            bugTagline: "Something isn't working",
            featureLabel: "Feature",
            featureTagline: "Idea or improvement",
            titleLabel: "Title",
            titleFieldName: "Title",
            titlePlaceholder: "Brief summary",
            descriptionLabel: "Description",
            descriptionFieldName: "Description",
            descriptionPlaceholder: "Describe what happened, what you expected, and how to reproduce.",
            emailLabel: "Email",
            emailOptionalBadge: "Optional",
            emailPlaceholder: "email@example.com",
            emailHint: "So we can reach out for more details",
            privacyNotice: "Device information will be automatically included",
            attachmentsLabel: "Attachments",
            submitButton: "Submit",
            doneButton: "Done",
            successTitle: "Thanks!",
            successMessage: "Your feedback was submitted. We'll take a look soon.",
            errorAlertTitle: "Submission failed",
            validationPromptTemplate: "Please fill in: {fields}"
        )
    }
}

extension FeedbackTheme.Copy {
    func validationPrompt(forMissing fields: [String]) -> String {
        // `ListFormatter` produces locale-correct output — "Title, Description"
        // in English, "Titel und Beschreibung" in German, etc. Since the rest
        // of `Copy` is explicitly localized, the joiner should match.
        let joined = ListFormatter.localizedString(byJoining: fields)
        return validationPromptTemplate.replacingOccurrences(of: "{fields}", with: joined)
    }
}
