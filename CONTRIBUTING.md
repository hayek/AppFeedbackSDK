# Contributing to AppFeedback (Apple/Swift SDK)

Thanks for helping improve AppFeedback! This is the Apple/Swift SDK
(SwiftPM). Bug reports, docs fixes, and pull requests are all welcome.

## Prerequisites

- Xcode 26.5 (toolchain pinned via `DEVELOPER_DIR`) or a matching Swift 6 toolchain
- macOS; the package also targets iOS 17+, watchOS 10+, tvOS 17+, and visionOS 1+

## Build & test

```sh
swift test
```

If you have multiple Xcodes installed, pin the toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer xcrun swift test
```

Please make sure the full test suite passes before opening a PR.

## The golden rule: the wire format is pinned by the spec

The cross-platform wire format is defined by the golden fixtures in
[**appfeedback-spec**](https://github.com/hayek/appfeedback-spec). The Swift,
Android, and Web SDKs must all encode and decode byte-for-byte identical
payloads, and the conformance tests in this repo run against fixtures synced
from the spec.

**Any change to the wire format must update the spec fixtures first.** Never
edit a synced fixture just to make a test pass — that silently breaks the
other platforms. The correct flow is:

1. Propose the change in `appfeedback-spec` and update its fixtures.
2. Run the spec's `scripts/sync-to-swift.sh` to bring the fixtures here.
3. Update this SDK to satisfy the new fixtures.

If a conformance test fails, treat it as a real cross-platform contract
mismatch, not a fixture to be massaged.

## Conventions

- Match the existing code style; keep public API additions documented.
- Add a `CHANGELOG.md` entry under `[Unreleased]` for user-facing changes.

## Questions

See the docs at <https://hayek.github.io/appfeedback-docs/>. For security
issues, follow [SECURITY.md](SECURITY.md) — do not open a public issue.
