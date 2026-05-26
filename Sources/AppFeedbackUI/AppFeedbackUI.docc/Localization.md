# Localization

Pass pre-localized strings into ``FeedbackTheme/Copy`` so the SDK doesn't have to ship a strings table.

## Overview

``FeedbackTheme/Copy`` uses plain `String` fields rather than `LocalizedStringKey`. This is deliberate: integrators ship their own strings catalogs and pass already-localized text into the theme. The SDK doesn't bundle a strings file, doesn't pick a locale, and doesn't override your app's localization workflow.

## Using `String(localized:)`

In a localized app (`.xcstrings` catalog or `Localizable.strings`):

```swift
let copy = FeedbackTheme.Copy(
    headerTitle:             String(localized: "feedback_header"),
    bugSubtitle:             String(localized: "feedback_bug_subtitle"),
    featureSubtitle:         String(localized: "feedback_feature_subtitle"),
    bugLabel:                String(localized: "feedback_type_bug"),
    bugTagline:              String(localized: "feedback_type_bug_tagline"),
    featureLabel:            String(localized: "feedback_type_feature"),
    featureTagline:          String(localized: "feedback_type_feature_tagline"),
    titleLabel:              String(localized: "feedback_title_label"),
    titleFieldName:          String(localized: "feedback_title_label"),
    titlePlaceholder:        String(localized: "feedback_title_placeholder"),
    descriptionLabel:        String(localized: "feedback_description_label"),
    descriptionFieldName:    String(localized: "feedback_description_label"),
    descriptionPlaceholder:  String(localized: "feedback_description_placeholder"),
    emailLabel:              String(localized: "feedback_email_label"),
    emailOptionalBadge:      String(localized: "feedback_optional"),
    emailPlaceholder:        String(localized: "feedback_email_placeholder"),
    emailHint:               String(localized: "feedback_email_hint"),
    privacyNotice:           String(localized: "feedback_privacy_notice"),
    submitButton:            String(localized: "feedback_submit_button"),
    doneButton:              String(localized: "feedback_done_button"),
    successTitle:            String(localized: "feedback_success_title"),
    successMessage:          String(localized: "feedback_success_message"),
    errorAlertTitle:         String(localized: "feedback_error_title"),
    validationPromptTemplate: String(localized: "feedback_validation_template")
)
```

`String(localized:)` resolves at runtime against `Bundle.main`, so each call picks up the user's current locale and any in-flight language change.

## The validation prompt template

`validationPromptTemplate` is interpolated when the user submits with required fields blank. The literal token `{fields}` is replaced with a comma-separated list of missing field names:

```text
"Please fill in: {fields}"   →   "Please fill in: Title, Description"
```

For locales that need different word order, encode it in the template:

```text
"Bitte ausfüllen: {fields}"   →   "Bitte ausfüllen: Titel, Beschreibung"
```

The names that fill `{fields}` come from `titleFieldName` and `descriptionFieldName`. Keep those short and in the same locale.

## Right-to-left layout

SwiftUI handles RTL automatically — the entire sheet flips when the system layout direction is right-to-left. No extra theme work needed; just provide RTL-correct copy strings.

## Topics

- ``FeedbackTheme/Copy``
- ``FeedbackTheme``
