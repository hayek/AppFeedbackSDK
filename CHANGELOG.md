# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [0.8.0] - 2026-09-02

### Added

- Optional analytics. Conform to `FeedbackAnalytics` and pass it to
  `FeedbackClient(analytics:)` to observe the whole funnel: sheet presented, type
  changed, attachment added or rejected, validation blocked, submission
  started/succeeded/failed, cancelled, and whether the App Store rating prompt
  was requested or suppressed (with the reason). `FeedbackEvent` exposes
  `name`/`parameters` shaped for Firebase and Mixpanel, so forwarding is one
  line, and those strings are pinned by tests. Configure the sink once on the
  client — there is deliberately no sheet-level parameter, because a sink set
  only there would silently never see submission events. Each event has exactly
  one emitter, so nothing is double-counted. No event carries user content:
  failures project a stable `error_kind` rather than `localizedDescription`,
  which would otherwise leak an attachment filename or a relay host name. Passing
  no sink is a genuine no-op.

## [0.7.0] - 2026-09-01

### Added

- `FeedbackSheet` follows a successful submission with the native App Store
  rating prompt when the feedback is unqualified praise, via the new
  `requestsAppStoreReview` parameter (default `true`). The praise check is
  on-device Apple Intelligence (Foundation Models, iOS/macOS/visionOS 26+) using
  guided generation over a three-case verdict, so an unparsable answer is
  unrepresentable rather than merely unlikely; the bar is pure praise, and
  anything mixing in a bug, complaint, question, or request is excluded. Every
  other outcome — no Apple Intelligence, an unavailable or still-downloading
  model, a guardrail trip, a refusal, an unsupported language, a timeout —
  silently skips the prompt, reproducing the previous behavior exactly. The
  report is submitted before any of this runs and is never affected by it. No
  app ID or other configuration is required. Inert on watchOS and tvOS, which
  have no rating prompt.

## [0.6.1] - 2026-08-24

### Fixed

- The two feedback-type cards no longer end up different sizes with truncated
  taglines. Their copy is themable, so the tiles can't assume the defaults'
  length — an adopter's "Bug / Issue" is wider than "Bug", and a localized
  string wider still. Label and tagline had `lineLimit(1)` and each card sized
  to its own content, so longer copy ellipsized and the card whose label wrapped
  grew taller than its neighbour. Both texts now wrap, and the row sizes to its
  tallest card with each card filling that height and an equal share of the
  width.

## [0.6.0] - 2026-08-24

### Added

- `FeedbackSheet` can attach photos from the camera roll on iOS. The Add button
  now opens a source menu — Photo Library or Files — because the file importer
  can't reach the photo library, which is where a screenshot lives. Picks are
  named from their content type (`Photo.png`, `Photo-2.heic`): `PhotosPickerItem`
  carries no filename, and reading the real one would require the full
  photo-library authorization prompt that `PHPickerViewController` avoids. The
  picker requests `.current` encoding so the MIME matches the bytes, leaving
  HEIC→JPEG and EXIF/GPS stripping to `ImagePreprocessor` on the submit path.
  Other platforms keep the single-source Add button.
- `FeedbackTheme.Copy.attachPhotoLibraryLabel` / `attachFilesLabel` — localizable
  names for the two iOS menu items. Both have defaults, so existing `Copy`
  initializers keep compiling.
- `FeedbackAttachmentValidator.maxCount` / `maxFileBytes` / `maxTotalBytes` are
  now `public`, so a UI can cap its own picker at what the validator accepts
  instead of duplicating the numbers.
- `source-meta-v1` marker vocabulary, emitted by `IssueBodyFormatter` and parsed
  back into `ParsedFeedbackBody`, with a formatter↔parser round-trip test.

### Fixed

- `IssueBodyParser` neutralizes spoofed `source-meta-v1` fences in untrusted
  text, so a reporter can't forge source metadata by pasting a fence into their
  own description.

## [0.5.3] - 2026-06-17

> Recorded retroactively: 0.5.3 was tagged without a changelog entry, and the
> items below sat under "Unreleased" until the 0.6.0 release.

### Added

- `RelayTransport` — posts feedback to an adopter-operated relay (relay-contract
  wire-compatible with the Web/Android SDKs), with optional `captchaToken`
  forwarding.

### Fixed

- Synced the OS-name parse fixtures and `recognisedOSNames` to the canonical
  spec, adding the non-Apple names `Android`, `Windows`, `Linux`, `Web`, and
  `ChromeOS`.

## [0.5.2] - 2026-06-17

### Fixed

- macOS drag-and-drop attachments now work. Dragged file URLs carry a transient
  sandbox drag exception rather than a bookmark-based security scope, so
  `startAccessingSecurityScopedResource()` returns `false` for them; the sheet
  previously guarded on that and silently dropped every dragged file (the
  file-importer path was unaffected). It now reads the file regardless and only
  balances `stopAccessingSecurityScopedResource()` when access actually started.

## [0.5.1] - 2026-06-17

### Fixed

- `FeedbackSheet` now trims leading/trailing whitespace from the title,
  description, and contact email before validating and submitting. A
  whitespace-only title/description no longer passes validation, and a
  whitespace-only email no longer emits an empty `Contact Email` block in the
  issue body.

## [0.5.0] - 2026-06-17

### Added

- `FeedbackTheme.bugGradient` / `featureGradient` — optional explicit gradient
  stops for the hero tile, ambient background glow, and success ring. When
  `nil` (the default) a gradient is derived from `bugAccent` / `featureAccent`
  exactly as before, so existing themes are visually unchanged. Supply two (or
  more) stops for a richer multi-hue gradient.
- `FeedbackSheet` `onSubmitReport` — optional callback fired alongside
  `onSubmit` after a successful submission, passing the full `FeedbackReport`
  (including its `FeedbackType`) and the backend identifier. Lets adopters log
  which feedback type was submitted, which `onSubmit(Int)` alone can't surface.

Both additions are source- and behavior-compatible: new parameters default to
their previous behavior, so adopters on the existing API need no changes.
