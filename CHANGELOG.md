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
