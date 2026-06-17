# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `RelayTransport` — posts feedback to an adopter-operated relay (relay-contract
  wire-compatible with the Web/Android SDKs), with optional `captchaToken`
  forwarding.

### Changed

### Fixed

- Synced the OS-name parse fixtures and `recognisedOSNames` to the canonical
  spec, adding the non-Apple names `Android`, `Windows`, `Linux`, `Web`, and
  `ChromeOS`.

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
