# P0 — Contract Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze the AppFeedback wire contract into a deterministic, locale-invariant, byte-exact form and capture it as a shared spec + golden-fixture conformance suite, so the upcoming Android and Web ports can match it exactly.

**Architecture:** Harden the existing Swift `AppFeedbackCore` (deterministic byte-count formatting, explicit code-point ordering for extra fields, extended OS-name recognition), add a golden-fixture conformance test that exercises the formatter and parser against language-neutral JSON cases, then create a standalone `appfeedback-spec` repo holding the canonical wire-format spec, the relay HTTP contract, and the canonical fixtures.

**Tech Stack:** Swift 6 / SwiftPM (`swift test`), XCTest, JSON fixtures bundled via `resources: [.copy("Fixtures")]`, a sibling git repo for the spec.

**Reference spec:** `docs/superpowers/specs/2026-06-05-android-web-docs-expansion-design.md` (§4 is this phase).

---

## Conventions used in every test/build step

- SDK repo root: `/Users/amir/Developer/AppFeedbackSDK`
- Test command (full suite):
  ```bash
  cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
  ```
  If `/Applications/Xcode-26.5.0.app` does not exist on the machine, drop the `DEVELOPER_DIR=...` prefix or point it at the installed Xcode (`xcode-select -p` shows the current one). XCTest is only available through a full Xcode toolchain, not Command Line Tools.
- Single-suite command: append `--filter <SuiteName>` to the test command.

## File structure (what this phase creates / modifies)

**Swift SDK (`/Users/amir/Developer/AppFeedbackSDK`):**
- Create `Sources/AppFeedbackCore/DeterministicByteCount.swift` — locale-invariant byte→string.
- Modify `Sources/AppFeedbackCore/IssueBodyFormatter.swift` — use `DeterministicByteCount`; sort `extraFields` by explicit code-point comparator.
- Modify `Sources/AppFeedbackCore/BodyMarkers.swift` — extend `recognisedOSNames`.
- Create `Tests/AppFeedbackCoreTests/DeterministicByteCountTests.swift`
- Create `Tests/AppFeedbackCoreTests/AttachmentSizeFormatTests.swift`
- Create `Tests/AppFeedbackCoreTests/ExtraFieldsOrderingTests.swift`
- Create `Tests/AppFeedbackCoreTests/RecognisedOSNamesTests.swift`
- Create `Tests/AppFeedbackCoreTests/ConformanceTests.swift`
- Create `Tests/AppFeedbackCoreTests/Fixtures/conformance/format-cases.json`
- Create `Tests/AppFeedbackCoreTests/Fixtures/conformance/parse-cases.json`

**New spec repo (`/Users/amir/Developer/appfeedback-spec`):**
- `README.md`, `wire-format.md`, `relay-contract.md`, `fixtures/format-cases.json`, `fixtures/parse-cases.json`, `scripts/sync-to-swift.sh`

No `Package.swift` change is needed: source files under `Sources/AppFeedbackCore/` and test files under `Tests/AppFeedbackCoreTests/` are auto-discovered, and the test target already declares `resources: [.copy("Fixtures")]`, which recursively bundles `Fixtures/conformance/`.

---

### Task 0: Setup — branch and baseline

**Files:** none (git + verification only)

- [ ] **Step 1: Create the feature branch off `main`**

```bash
cd /Users/amir/Developer/AppFeedbackSDK && git checkout main && git checkout -b feat/p0-contract-foundation
```

- [ ] **Step 2: Confirm the baseline test suite is green before any change**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
```
Expected: build succeeds and all existing tests pass (`Test Suite '...' passed`). If it fails to build for toolchain reasons, resolve `DEVELOPER_DIR` per the Conventions section before proceeding.

---

### Task 1: Deterministic byte-count formatter

**Files:**
- Create: `Sources/AppFeedbackCore/DeterministicByteCount.swift`
- Test: `Tests/AppFeedbackCoreTests/DeterministicByteCountTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AppFeedbackCoreTests/DeterministicByteCountTests.swift`:

```swift
import XCTest
@testable import AppFeedbackCore

final class DeterministicByteCountTests: XCTestCase {

    func test_bytes_below_one_thousand_render_as_integer_bytes() {
        XCTAssertEqual(DeterministicByteCount.string(0), "0 B")
        XCTAssertEqual(DeterministicByteCount.string(512), "512 B")
        XCTAssertEqual(DeterministicByteCount.string(999), "999 B")
    }

    func test_negative_clamps_to_zero() {
        XCTAssertEqual(DeterministicByteCount.string(-5), "0 B")
    }

    func test_kilobytes_round_half_up_to_one_decimal() {
        XCTAssertEqual(DeterministicByteCount.string(1000), "1 KB")
        XCTAssertEqual(DeterministicByteCount.string(1234), "1.2 KB")
        XCTAssertEqual(DeterministicByteCount.string(1500), "1.5 KB")
        XCTAssertEqual(DeterministicByteCount.string(4096), "4.1 KB")
        XCTAssertEqual(DeterministicByteCount.string(319_488), "319.5 KB")
    }

    func test_megabytes_and_gigabytes() {
        XCTAssertEqual(DeterministicByteCount.string(1_000_000), "1 MB")
        XCTAssertEqual(DeterministicByteCount.string(1_500_000), "1.5 MB")
        XCTAssertEqual(DeterministicByteCount.string(2_500_000), "2.5 MB")
        XCTAssertEqual(DeterministicByteCount.string(1_000_000_000), "1 GB")
    }

    func test_trailing_zero_decimal_is_dropped() {
        XCTAssertEqual(DeterministicByteCount.string(2_000_000), "2 MB")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter DeterministicByteCountTests 2>&1 | tail -20
```
Expected: compile error — `cannot find 'DeterministicByteCount' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/AppFeedbackCore/DeterministicByteCount.swift`:

```swift
/// Locale-invariant, deterministic human-readable byte-count formatter.
///
/// Replaces `ByteCountFormatter`, whose output varies by locale and OS version
/// (`kB` vs `KB`, non-breaking spaces, decimal grouping) and therefore cannot
/// be reproduced byte-for-byte by the Android (Kotlin) and Web (TypeScript)
/// ports. The attachment size string is part of the wire contract (see the
/// `appfeedback-spec` wire-format document), so it must be pinned to a single
/// algorithm every platform can replicate exactly.
///
/// Decimal (1000-based) units, matching `IssueBodyParser.parseHumanByteCount`:
/// - `< 1000` bytes → integer bytes, e.g. `"512 B"`.
/// - `KB`/`MB`/`GB` → at most one decimal place, half-up rounded, a trailing
///   `.0` dropped, a single ASCII space before the unit, e.g. `"1.2 KB"`,
///   `"2 MB"`.
///
/// Negative inputs clamp to `0`. Attachment sizes are validated to a small cap
/// upstream, so the integer arithmetic below cannot overflow in practice.
enum DeterministicByteCount {
    static func string(_ bytes: Int) -> String {
        let b = max(0, bytes)
        let units: [(name: String, factor: Int)] = [
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000),
        ]
        for unit in units where b >= unit.factor {
            // Tenths of `unit`, rounded half-up using integer arithmetic so the
            // result never depends on floating-point or locale behaviour.
            let tenths = (b * 10 + unit.factor / 2) / unit.factor
            let whole = tenths / 10
            let frac = tenths % 10
            return frac == 0 ? "\(whole) \(unit.name)" : "\(whole).\(frac) \(unit.name)"
        }
        return "\(b) B"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter DeterministicByteCountTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/amir/Developer/AppFeedbackSDK && git add Sources/AppFeedbackCore/DeterministicByteCount.swift Tests/AppFeedbackCoreTests/DeterministicByteCountTests.swift && git commit -m "feat(core): deterministic locale-invariant byte-count formatter"
```

---

### Task 2: Use the deterministic formatter in the body

**Files:**
- Modify: `Sources/AppFeedbackCore/IssueBodyFormatter.swift` (the attachment loop, currently line ~78)
- Test: `Tests/AppFeedbackCoreTests/AttachmentSizeFormatTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AppFeedbackCoreTests/AttachmentSizeFormatTests.swift`:

```swift
import XCTest
@testable import AppFeedbackCore

final class AttachmentSizeFormatTests: XCTestCase {

    private let device = DeviceInfo(
        appName: "A", appVersion: "1", buildNumber: "1",
        model: "M", osName: "macOS", osVersion: "Version 15.1"
    )

    func test_attachment_line_uses_deterministic_size_string() {
        let uploaded = [
            UploadedAttachment(
                filename: "shot.png", mimeType: "image/png", sizeBytes: 1234,
                url: URL(string: "https://example.com/shot.png")!
            )
        ]
        let body = IssueBodyFormatter.format(
            report: FeedbackReport(type: .bug, title: "t", description: "d"),
            deviceInfo: device, uploaded: uploaded
        )
        XCTAssertTrue(
            body.contains("![shot.png](https://example.com/shot.png) — image/png, 1.2 KB"),
            "expected deterministic '1.2 KB'; got body:\n\(body)"
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter AttachmentSizeFormatTests 2>&1 | tail -20
```
Expected: FAIL — `ByteCountFormatter` renders 1234 bytes as `"1 KB"` (not `"1.2 KB"`), so the substring is absent.

- [ ] **Step 3: Replace `ByteCountFormatter` in the formatter**

In `Sources/AppFeedbackCore/IssueBodyFormatter.swift`, inside the `for a in uploaded` loop, replace this line:

```swift
                let size = ByteCountFormatter.string(fromByteCount: Int64(a.sizeBytes), countStyle: .file)
```

with:

```swift
                let size = DeterministicByteCount.string(a.sizeBytes)
```

(Same module — no import needed. `Foundation` is still imported for other uses in the file; leave it.)

- [ ] **Step 4: Run the focused test, then the full suite**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter AttachmentSizeFormatTests 2>&1 | tail -20
```
Expected: PASS.

Then run the whole suite to confirm the existing `AttachmentBodyFormatTests` / `RoundtripTests` still pass (they assert `— image/png` but not the size string, so they are unaffected):
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
cd /Users/amir/Developer/AppFeedbackSDK && git add Sources/AppFeedbackCore/IssueBodyFormatter.swift Tests/AppFeedbackCoreTests/AttachmentSizeFormatTests.swift && git commit -m "feat(core): emit deterministic attachment sizes in issue body"
```

---

### Task 3: Pin `extraFields` ordering to code-point order

**Files:**
- Modify: `Sources/AppFeedbackCore/IssueBodyFormatter.swift` (the `extraFields` loop, currently line ~70; add a static comparator)
- Test: `Tests/AppFeedbackCoreTests/ExtraFieldsOrderingTests.swift`

> **Note:** This is a *spec-pinning* change. Swift's implicit `String.sorted()` already produces code-point order for the ASCII/Latin-1 inputs below, so the characterization test will pass before and after. We still make the comparator explicit so the ordering is a defined contract the Kotlin/TS ports replicate (their default string sorts diverge from code-point order for some inputs), rather than an accident of Swift's `String` comparison internals.

- [ ] **Step 1: Write the characterization test**

Create `Tests/AppFeedbackCoreTests/ExtraFieldsOrderingTests.swift`:

```swift
import XCTest
@testable import AppFeedbackCore

final class ExtraFieldsOrderingTests: XCTestCase {

    private let device = DeviceInfo(
        appName: "A", appVersion: "1", buildNumber: "1",
        model: "M", osName: "macOS", osVersion: "Version 15.1"
    )

    func test_extra_fields_sorted_by_codepoint_uppercase_before_lowercase() {
        let report = FeedbackReport(
            type: .bug, title: "t", description: "Desc",
            extraFields: ["Zeta": "z", "alpha": "a", "Beta": "b"]
        )
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device)
        // Code-point order: 'B'(0x42) < 'Z'(0x5A) < 'a'(0x61)
        let beta = body.range(of: "**Beta:**")!
        let zeta = body.range(of: "**Zeta:**")!
        let alpha = body.range(of: "**alpha:**")!
        XCTAssertLessThan(beta.lowerBound, zeta.lowerBound)
        XCTAssertLessThan(zeta.lowerBound, alpha.lowerBound)
    }

    func test_non_ascii_key_orders_after_ascii_by_codepoint() {
        let report = FeedbackReport(
            type: .bug, title: "t", description: "Desc",
            extraFields: ["é": "x", "a": "y"]
        )
        let body = IssueBodyFormatter.format(report: report, deviceInfo: device)
        // 'a'(0x61) < 'é'(0xE9)
        let a = body.range(of: "**a:**")!
        let e = body.range(of: "**é:**")!
        XCTAssertLessThan(a.lowerBound, e.lowerBound)
    }
}
```

- [ ] **Step 2: Run the test (documents current behavior — expected PASS)**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter ExtraFieldsOrderingTests 2>&1 | tail -20
```
Expected: PASS (Swift's implicit sort already matches for these inputs).

- [ ] **Step 3: Make the comparator explicit**

In `Sources/AppFeedbackCore/IssueBodyFormatter.swift`, replace this line:

```swift
        for key in report.extraFields.keys.sorted() {
```

with:

```swift
        for key in report.extraFields.keys.sorted(by: Self.codePointOrder) {
```

Then add this static helper inside the `IssueBodyFormatter` enum (e.g. directly above the `labels(for:)` function):

```swift
    /// Deterministic ordering for `extraFields` keys: ascending by Unicode
    /// scalar value (code point). Pinned in the wire spec so the Kotlin/TS
    /// ports replicate it exactly — each language's default string sort is
    /// *not* guaranteed to equal code-point order for non-ASCII keys.
    static func codePointOrder(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
    }
```

- [ ] **Step 4: Run the focused test, then the full suite**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter ExtraFieldsOrderingTests 2>&1 | tail -20
```
Expected: PASS.

Then full suite:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
cd /Users/amir/Developer/AppFeedbackSDK && git add Sources/AppFeedbackCore/IssueBodyFormatter.swift Tests/AppFeedbackCoreTests/ExtraFieldsOrderingTests.swift && git commit -m "feat(core): pin extraFields ordering to explicit code-point comparator"
```

---

### Task 4: Extend recognised OS names

**Files:**
- Modify: `Sources/AppFeedbackCore/BodyMarkers.swift` (the `recognisedOSNames` array, currently line ~24)
- Test: `Tests/AppFeedbackCoreTests/RecognisedOSNamesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AppFeedbackCoreTests/RecognisedOSNamesTests.swift`:

```swift
import XCTest
@testable import AppFeedbackCore

final class RecognisedOSNamesTests: XCTestCase {

    /// Formats a body with the given OS name/version, parses it back, and
    /// returns the parsed `osVersion` (nil if the line was not recognised).
    private func roundTripOSVersion(osName: String, osVersion: String) -> String? {
        let device = DeviceInfo(
            appName: "A", appVersion: "1", buildNumber: "1",
            model: "M", osName: osName, osVersion: osVersion
        )
        let body = IssueBodyFormatter.format(
            report: FeedbackReport(type: .bug, title: "t", description: "d"),
            deviceInfo: device
        )
        return IssueBodyParser.parse(body).osVersion
    }

    func test_android_os_version_is_parsed() {
        XCTAssertEqual(roundTripOSVersion(osName: "Android", osVersion: "14"), "14")
    }

    func test_windows_os_version_is_parsed() {
        XCTAssertEqual(
            roundTripOSVersion(osName: "Windows", osVersion: "11 (22631.4317)"),
            "11 (22631.4317)"
        )
    }

    func test_web_os_version_is_parsed() {
        XCTAssertEqual(
            roundTripOSVersion(osName: "Web", osVersion: "Chrome 120 on macOS"),
            "Chrome 120 on macOS"
        )
    }

    func test_linux_and_chromeos_os_versions_are_parsed() {
        XCTAssertEqual(roundTripOSVersion(osName: "Linux", osVersion: "Ubuntu 24.04"), "Ubuntu 24.04")
        XCTAssertEqual(roundTripOSVersion(osName: "ChromeOS", osVersion: "120"), "120")
    }

    func test_existing_apple_os_names_still_parse() {
        XCTAssertEqual(roundTripOSVersion(osName: "iOS", osVersion: "Version 18.2"), "Version 18.2")
        XCTAssertEqual(roundTripOSVersion(osName: "macOS", osVersion: "Version 15.1"), "Version 15.1")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter RecognisedOSNamesTests 2>&1 | tail -25
```
Expected: the Android/Windows/Web/Linux/ChromeOS tests FAIL (parsed `osVersion` is `nil` because those names are not yet recognised); the Apple test passes.

- [ ] **Step 3: Extend the recognised list**

In `Sources/AppFeedbackCore/BodyMarkers.swift`, replace:

```swift
    static let recognisedOSNames = ["OS", "macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS"]
```

with:

```swift
    static let recognisedOSNames = [
        "OS", "macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS",
        "Android", "Windows", "Linux", "Web", "ChromeOS",
    ]
```

(The `osVersionPattern` regex is derived from this array, so it updates automatically. No regex edit needed.)

- [ ] **Step 4: Run the focused test, then the full suite**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter RecognisedOSNamesTests 2>&1 | tail -20
```
Expected: PASS.

Then full suite:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
cd /Users/amir/Developer/AppFeedbackSDK && git add Sources/AppFeedbackCore/BodyMarkers.swift Tests/AppFeedbackCoreTests/RecognisedOSNamesTests.swift && git commit -m "feat(core): recognise Android/Windows/Linux/Web/ChromeOS OS names"
```

> **Cross-repo note:** The inbox app (`/Users/amir/Developer/AppFeedback`) parses via `AppFeedbackCore.IssueBodyParser` over a local SwiftPM dependency, so it picks up these names automatically the next time it builds. No inbox code change is required in P0. (Optional verification, not part of this branch: build the inbox app and confirm an Android-OS body shows a populated OS column.)

---

### Task 5: Golden fixtures + conformance test

**Files:**
- Create: `Tests/AppFeedbackCoreTests/Fixtures/conformance/format-cases.json`
- Create: `Tests/AppFeedbackCoreTests/Fixtures/conformance/parse-cases.json`
- Create: `Tests/AppFeedbackCoreTests/ConformanceTests.swift`

- [ ] **Step 1: Create the format fixtures**

Create `Tests/AppFeedbackCoreTests/Fixtures/conformance/format-cases.json` (UTF-8; note the literal `—` em-dash and `👍` emoji):

```json
[
  {
    "name": "bug-minimal-ios",
    "report": { "type": "bug", "title": "Crash on launch", "description": "It crashed on startup.", "contactEmail": null, "extraFields": {} },
    "deviceInfo": { "appName": "Acme", "appVersion": "1.2.3", "buildNumber": "456", "model": "iPhone15,2", "osName": "iOS", "osVersion": "Version 18.2 (Build 22C150)" },
    "uploaded": [],
    "expectedBody": "It crashed on startup.\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 1.2.3 (456)\nDevice: iPhone15,2\niOS Version: Version 18.2 (Build 22C150)\n\n---\n👍 Votes: 0",
    "expectedLabels": ["bug", "user-submitted"]
  },
  {
    "name": "feature-with-email-android",
    "report": { "type": "feature-request", "title": "Dark mode", "description": "Please add dark mode.", "contactEmail": "user@example.com", "extraFields": {} },
    "deviceInfo": { "appName": "Acme", "appVersion": "2.0", "buildNumber": "200", "model": "Pixel 8", "osName": "Android", "osVersion": "14" },
    "uploaded": [],
    "expectedBody": "Please add dark mode.\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 2.0 (200)\nDevice: Pixel 8\nAndroid Version: 14\n\n**Contact Email:**\nuser@example.com\n\n---\n👍 Votes: 0",
    "expectedLabels": ["feature-request", "user-submitted"]
  },
  {
    "name": "extra-fields-codepoint-order",
    "report": { "type": "bug", "title": "t", "description": "Desc", "contactEmail": null, "extraFields": { "Zeta": "z", "alpha": "a", "Beta": "b" } },
    "deviceInfo": { "appName": "Acme", "appVersion": "1.0", "buildNumber": "1", "model": "Mac", "osName": "macOS", "osVersion": "Version 15.1" },
    "uploaded": [],
    "expectedBody": "Desc\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 1.0 (1)\nDevice: Mac\nmacOS Version: Version 15.1\n\n**Beta:**\nb\n\n**Zeta:**\nz\n\n**alpha:**\na\n\n---\n👍 Votes: 0"
  },
  {
    "name": "image-attachment-deterministic-size",
    "report": { "type": "bug", "title": "t", "description": "See screenshot", "contactEmail": null, "extraFields": {} },
    "deviceInfo": { "appName": "Acme", "appVersion": "1.0", "buildNumber": "1", "model": "Mac", "osName": "macOS", "osVersion": "Version 15.1" },
    "uploaded": [ { "filename": "screenshot.png", "mimeType": "image/png", "sizeBytes": 1234, "url": "https://raw.githubusercontent.com/o/r/feedback-attachments/attachments/uuid/screenshot.png" } ],
    "expectedBody": "See screenshot\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 1.0 (1)\nDevice: Mac\nmacOS Version: Version 15.1\n\n<!-- attachments-v1 -->\n## Attachments\n\n![screenshot.png](https://raw.githubusercontent.com/o/r/feedback-attachments/attachments/uuid/screenshot.png) — image/png, 1.2 KB\n\n<!-- /attachments-v1 -->\n\n---\n👍 Votes: 0"
  },
  {
    "name": "web-osname",
    "report": { "type": "bug", "title": "t", "description": "d", "contactEmail": null, "extraFields": {} },
    "deviceInfo": { "appName": "Acme", "appVersion": "3.0", "buildNumber": "300", "model": "Desktop", "osName": "Web", "osVersion": "Chrome 120 on Windows" },
    "uploaded": [],
    "expectedBody": "d\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 3.0 (300)\nDevice: Desktop\nWeb Version: Chrome 120 on Windows\n\n---\n👍 Votes: 0"
  }
]
```

- [ ] **Step 2: Create the parse fixtures**

Create `Tests/AppFeedbackCoreTests/Fixtures/conformance/parse-cases.json`:

```json
[
  {
    "name": "legacy-macos-with-email",
    "body": "The export button does nothing on macOS 15.\n\n---\n**Device Information:**\nApp: Usage for Claude\nApp Version: 3.4.1 (980)\nDevice: Mac15,11\nmacOS Version: Version 15.1 (Build 24B83)\n\n**Contact Email:**\nbeta@example.com\n\n---\n👍 Votes: 0",
    "expected": { "description": "The export button does nothing on macOS 15.", "appName": "Usage for Claude", "appVersion": "3.4.1 (980)", "device": "Mac15,11", "osVersion": "Version 15.1 (Build 24B83)", "email": "beta@example.com", "attachments": [] }
  },
  {
    "name": "android-no-email",
    "body": "Tapping save does nothing.\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 2.0 (200)\nDevice: Pixel 8\nAndroid Version: 14\n\n---\n👍 Votes: 0",
    "expected": { "description": "Tapping save does nothing.", "appName": "Acme", "appVersion": "2.0 (200)", "device": "Pixel 8", "osVersion": "14", "email": null, "attachments": [] }
  },
  {
    "name": "web-inline-email",
    "body": "Layout breaks at 320px.\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 3.0 (300)\nDevice: Desktop\nWeb Version: Chrome 120 on Windows\n**Contact Email:** dev@example.com",
    "expected": { "description": "Layout breaks at 320px.", "appName": "Acme", "appVersion": "3.0 (300)", "device": "Desktop", "osVersion": "Chrome 120 on Windows", "email": "dev@example.com", "attachments": [] }
  },
  {
    "name": "macos-with-attachments",
    "body": "Has a rendering bug.\n\n---\n**Device Information:**\nApp: Acme\nApp Version: 1.0 (1)\nDevice: Mac\nmacOS Version: Version 15.1\n\n<!-- attachments-v1 -->\n## Attachments\n\n![shot.png](https://example.com/shot.png) — image/png, 312 KB\n\n[log.txt](https://example.com/log.txt) — text/plain, 4.1 KB\n\n<!-- /attachments-v1 -->\n\n---\n👍 Votes: 0",
    "expected": { "description": "Has a rendering bug.", "appName": "Acme", "appVersion": "1.0 (1)", "device": "Mac", "osVersion": "Version 15.1", "email": null, "attachments": [ { "filename": "shot.png", "mimeType": "image/png", "url": "https://example.com/shot.png", "sizeBytes": 312000 }, { "filename": "log.txt", "mimeType": "text/plain", "url": "https://example.com/log.txt", "sizeBytes": 4100 } ] }
  }
]
```

- [ ] **Step 3: Write the conformance test (expected to pass immediately)**

Create `Tests/AppFeedbackCoreTests/ConformanceTests.swift`:

```swift
import XCTest
@testable import AppFeedbackCore

/// Runs the language-neutral golden fixtures from `appfeedback-spec` (vendored
/// under Fixtures/conformance) through the Swift formatter and parser. Every
/// platform port runs this same corpus; it is the blocking gate that keeps the
/// three implementations byte-identical.
final class ConformanceTests: XCTestCase {

    // MARK: Fixture models

    private struct ReportFixture: Decodable {
        let type: String
        let title: String
        let description: String
        let contactEmail: String?
        let extraFields: [String: String]?
    }
    private struct DeviceFixture: Decodable {
        let appName, appVersion, buildNumber, model, osName, osVersion: String
    }
    private struct UploadedFixture: Decodable {
        let filename, mimeType: String
        let sizeBytes: Int
        let url: String
    }
    private struct FormatCase: Decodable {
        let name: String
        let report: ReportFixture
        let deviceInfo: DeviceFixture
        let uploaded: [UploadedFixture]?
        let expectedBody: String
        let expectedLabels: [String]?
    }
    private struct AttachmentExpectation: Decodable {
        let filename, mimeType, url: String
        let sizeBytes: Int?
    }
    private struct ParsedExpectation: Decodable {
        let description: String
        let appName, appVersion, device, osVersion, email: String?
        let attachments: [AttachmentExpectation]?
    }
    private struct ParseCase: Decodable {
        let name: String
        let body: String
        let expected: ParsedExpectation
    }

    // MARK: Loading

    private func loadCases<T: Decodable>(_ resource: String) throws -> [T] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: resource, withExtension: "json", subdirectory: "Fixtures/conformance"),
            "missing fixture \(resource).json"
        )
        return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
    }

    // MARK: Tests

    func test_format_golden_fixtures() throws {
        let cases: [FormatCase] = try loadCases("format-cases")
        XCTAssertFalse(cases.isEmpty, "no format fixtures loaded")
        for c in cases {
            let type = try XCTUnwrap(FeedbackType(rawValue: c.report.type), "unknown type in \(c.name)")
            let report = FeedbackReport(
                type: type, title: c.report.title, description: c.report.description,
                contactEmail: c.report.contactEmail, extraFields: c.report.extraFields ?? [:]
            )
            let device = DeviceInfo(
                appName: c.deviceInfo.appName, appVersion: c.deviceInfo.appVersion,
                buildNumber: c.deviceInfo.buildNumber, model: c.deviceInfo.model,
                osName: c.deviceInfo.osName, osVersion: c.deviceInfo.osVersion
            )
            let uploaded = try (c.uploaded ?? []).map {
                UploadedAttachment(
                    filename: $0.filename, mimeType: $0.mimeType, sizeBytes: $0.sizeBytes,
                    url: try XCTUnwrap(URL(string: $0.url), "bad url in \(c.name)")
                )
            }
            let body = IssueBodyFormatter.format(report: report, deviceInfo: device, uploaded: uploaded)
            XCTAssertEqual(body, c.expectedBody, "format mismatch in '\(c.name)'")
            if let labels = c.expectedLabels {
                XCTAssertEqual(IssueBodyFormatter.labels(for: type), labels, "labels mismatch in '\(c.name)'")
            }
        }
    }

    func test_parse_golden_fixtures() throws {
        let cases: [ParseCase] = try loadCases("parse-cases")
        XCTAssertFalse(cases.isEmpty, "no parse fixtures loaded")
        for c in cases {
            let parsed = IssueBodyParser.parse(c.body)
            XCTAssertEqual(parsed.description, c.expected.description, "description mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.appName, c.expected.appName, "appName mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.appVersion, c.expected.appVersion, "appVersion mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.device, c.expected.device, "device mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.osVersion, c.expected.osVersion, "osVersion mismatch in '\(c.name)'")
            XCTAssertEqual(parsed.email, c.expected.email, "email mismatch in '\(c.name)'")
            let expected = c.expected.attachments ?? []
            XCTAssertEqual(parsed.attachments.count, expected.count, "attachment count mismatch in '\(c.name)'")
            for (i, ea) in expected.enumerated() where i < parsed.attachments.count {
                XCTAssertEqual(parsed.attachments[i].filename, ea.filename, "att filename in '\(c.name)'[\(i)]")
                XCTAssertEqual(parsed.attachments[i].mimeType, ea.mimeType, "att mime in '\(c.name)'[\(i)]")
                XCTAssertEqual(parsed.attachments[i].url.absoluteString, ea.url, "att url in '\(c.name)'[\(i)]")
                XCTAssertEqual(parsed.attachments[i].sizeBytes, ea.sizeBytes, "att size in '\(c.name)'[\(i)]")
            }
        }
    }
}
```

- [ ] **Step 4: Run the conformance test, then the full suite**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test --filter ConformanceTests 2>&1 | tail -25
```
Expected: PASS (both `test_format_golden_fixtures` and `test_parse_golden_fixtures`). If a format case mismatches, the assertion message names the failing case and prints the exact expected vs. produced body — fix the fixture's `expectedBody` to match the real formatter output (the formatter is the source of truth), not the other way around.

Then full suite:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
cd /Users/amir/Developer/AppFeedbackSDK && git add Tests/AppFeedbackCoreTests/Fixtures/conformance Tests/AppFeedbackCoreTests/ConformanceTests.swift && git commit -m "test(core): golden-fixture conformance suite for the wire format"
```

---

### Task 6: Create the `appfeedback-spec` repo

**Files (all new, in `/Users/amir/Developer/appfeedback-spec`):**
- `README.md`, `wire-format.md`, `relay-contract.md`
- `fixtures/format-cases.json`, `fixtures/parse-cases.json`
- `scripts/sync-to-swift.sh`

- [ ] **Step 1: Scaffold the repo directories**

```bash
mkdir -p /Users/amir/Developer/appfeedback-spec/fixtures /Users/amir/Developer/appfeedback-spec/scripts
```

- [ ] **Step 2: Copy the canonical fixtures from the SDK into the spec repo**

```bash
cp /Users/amir/Developer/AppFeedbackSDK/Tests/AppFeedbackCoreTests/Fixtures/conformance/format-cases.json /Users/amir/Developer/appfeedback-spec/fixtures/format-cases.json
cp /Users/amir/Developer/AppFeedbackSDK/Tests/AppFeedbackCoreTests/Fixtures/conformance/parse-cases.json /Users/amir/Developer/appfeedback-spec/fixtures/parse-cases.json
```

- [ ] **Step 3: Write `README.md`**

Create `/Users/amir/Developer/appfeedback-spec/README.md`:

```markdown
# appfeedback-spec

The cross-platform contract for the AppFeedback SDK family (Apple · Android · Web).

Every SDK is a write-only client that creates a GitHub issue in a byte-exact
body format which the AppFeedback inbox parses back. This repo is the single
source of truth for that format so the platform implementations cannot drift.

## Contents

- [`wire-format.md`](./wire-format.md) — the GitHub issue body + labels contract.
- [`relay-contract.md`](./relay-contract.md) — the browser ⇄ relay HTTP contract for the Web SDK.
- [`fixtures/`](./fixtures) — language-neutral golden fixtures:
  - `format-cases.json` — `report` + `deviceInfo` + `uploaded` → exact expected body bytes.
  - `parse-cases.json` — issue body → expected parsed fields.

## How it is used

Each platform SDK vendors these fixtures into its test target and runs them as a
**blocking CI gate**. Any change to the wire format MUST add or update a fixture
here first. The Swift SDK at `../AppFeedbackSDK` is the reference implementation.

Run `scripts/sync-to-swift.sh` after editing `fixtures/` to copy them into the
Swift SDK's test resources.

## Versioning

The spec is versioned independently of the SDKs. Breaking changes to the wire
format bump the spec's MAJOR version and require a coordinated SDK + inbox update.
```

- [ ] **Step 4: Write `wire-format.md`**

Create `/Users/amir/Developer/appfeedback-spec/wire-format.md`:

```markdown
# AppFeedback wire format

The contract between any AppFeedback SDK (writer) and the AppFeedback inbox
(reader). A submission becomes one GitHub issue: a **title**, a **body**, and a
set of **labels**.

## Labels

`[<type>, "user-submitted"]` where `<type>` is one of:

- `bug`
- `feature-request`

## Title

The submission's one-line summary, used verbatim as the GitHub issue title.

## Body

Sections are joined by a blank line (`\n\n`). Lines within the device block are
joined by single newlines (`\n`). Order is fixed:

```
<description>

---
**Device Information:**
App: <appName>
App Version: <appVersion> (<buildNumber>)
Device: <model>
<osName> Version: <osVersion>

**Contact Email:**          ← only when a non-empty contact email is supplied
<email>

**<key>:**                  ← one block per extra field, keys ordered (see below)
<value>

<!-- attachments-v1 -->     ← only when there is at least one uploaded attachment
## Attachments

<prefix>[<filename>](<url>) — <mimeType>, <size>   ← one line per attachment

<!-- /attachments-v1 -->

---
👍 Votes: 0
```

### Field rules

- **description** — free-form text, emitted verbatim at the top.
- **Device block** — always present, in the order shown.
- **osName** — must be one of the recognised names so the inbox can populate the
  OS column: `OS`, `macOS`, `iOS`, `iPadOS`, `watchOS`, `tvOS`, `visionOS`,
  `Android`, `Windows`, `Linux`, `Web`, `ChromeOS`. Non-Apple platforms use
  `Android` / `Web` / `Windows` / `Linux` / `ChromeOS`; use the generic `OS`
  only when the platform is unknown.
- **Contact Email** — emitted only when the email is non-empty.
- **Extra fields** — one `**<key>:**\n<value>` block per entry, **ordered
  ascending by Unicode scalar value (code point)** of the key. This is a hard
  rule: do not rely on a language's default string sort, which can diverge from
  code-point order for non-ASCII keys.
- **Attachments** — only when present, wrapped in the exact HTML-comment markers
  `<!-- attachments-v1 -->` … `<!-- /attachments-v1 -->`, preceded by the
  `## Attachments` header. Each line is:
  - `<prefix>` = `!` when `mimeType` starts with `image/`, otherwise empty
    (Markdown image embed vs. link).
  - separator between url and metadata is a space-padded em-dash `" — "`
    (U+2014). This exact code point is required; the parser keys on it.
  - `<size>` is the **deterministic byte count** (see below).
- **Votes footer** — the literal `👍 Votes: 0` (U+1F44D + ` Votes: 0`), byte for
  byte. Source files must be UTF-8.

### Deterministic byte-count format

Decimal (1000-based) units, to match the parser's tolerant reader:

- `bytes < 1000` → `"<bytes> B"` (integer).
- otherwise pick the largest of `KB` (1e3), `MB` (1e6), `GB` (1e9) with
  `bytes >= factor`; the value is `bytes / factor` rounded **half-up to one
  decimal place**; a trailing `.0` is dropped; a single ASCII space precedes the
  unit.
- Negative inputs clamp to `0`.

Examples: `512 → "512 B"`, `1234 → "1.2 KB"`, `4096 → "4.1 KB"`,
`2_000_000 → "2 MB"`, `1_500_000 → "1.5 MB"`.

## Parser resilience (reader side)

The inbox parser is deliberately tolerant of hand-written / legacy bodies:
- `**bold**` markers around labels are ignored.
- A `**Contact Email:** foo@bar.com` inline form is accepted, as is the
  label-on-its-own-line-then-value form.
- Standalone `---` lines are stripped from the description.
- Attachment `<size>` is parsed approximately (`B`/`KB`/`MB`/`GB`, 1000-based);
  a missing size or MIME falls back to extension inference.
- Unknown future marker versions (e.g. `attachments-v2`) are ignored.

## Conformance

`fixtures/format-cases.json` and `fixtures/parse-cases.json` are the executable
form of this document. Implementations MUST pass both. A change here requires a
matching fixture change.
```

- [ ] **Step 5: Write `relay-contract.md`**

Create `/Users/amir/Developer/appfeedback-spec/relay-contract.md`:

```markdown
# AppFeedback relay contract (Web)

A browser cannot safely hold a writable GitHub token, so the Web SDK never calls
GitHub directly in production. It POSTs a feedback submission to an
**adopter-operated relay** that holds the GitHub credential server-side, creates
the issue, and returns its number. This document is the contract between the Web
SDK and any relay implementation (Cloudflare/Vercel/Netlify, Firebase, Appwrite,
or a custom backend).

## Endpoint

The adopter configures a single absolute URL. The SDK issues:

`POST <relayEndpoint>`  ·  `Content-Type: application/json`

## Request body

```json
{
  "type": "bug | feature-request",
  "title": "string (issue title)",
  "description": "string",
  "contactEmail": "string | null",
  "extraFields": { "key": "value" },
  "deviceInfo": {
    "appName": "string",
    "appVersion": "string",
    "buildNumber": "string",
    "model": "string",
    "osName": "Web | Windows | Linux | ChromeOS | ...",
    "osVersion": "string"
  },
  "attachments": [
    { "filename": "string", "mimeType": "string", "dataBase64": "string" }
  ],
  "captchaToken": "string | null"
}
```

`attachments` and `extraFields` may be omitted/empty. `captchaToken` carries a
bot-mitigation token (e.g. Cloudflare Turnstile / hCaptcha) when the relay
requires one.

## Response

`200 OK`:

```json
{ "issueNumber": 123, "issueUrl": "https://github.com/owner/repo/issues/123" }
```

Error responses use the matching HTTP status and a JSON `{ "error": "string" }`
body:

| Status | Meaning |
|--------|---------|
| `400` | malformed/invalid submission |
| `401` / `403` | missing/failed CAPTCHA or auth |
| `413` | payload too large |
| `429` | rate-limited |
| `502` | GitHub upstream error |

## Relay responsibilities

The relay — not the browser — performs privileged work and owns final body
assembly per `wire-format.md`:

1. Verify the CAPTCHA token (if configured).
2. Enforce per-IP and global rate limits, payload caps, and basic dedupe.
3. Optionally upload each attachment to the repo's `feedback-attachments` branch
   (GitHub contents API; use the Git blobs API or an external store for large
   files) and collect the resulting URLs.
4. Format the issue body and labels from the structured fields + uploaded URLs.
5. Create the issue with a server-held credential (GitHub App installation token
   recommended; a fine-grained PAT scoped to Issues+Contents on one repo is the
   simplest setup). The credential lives only in the relay's environment.
6. Return `{ issueNumber, issueUrl }`.
```

- [ ] **Step 6: Write the sync script**

Create `/Users/amir/Developer/appfeedback-spec/scripts/sync-to-swift.sh`:

```bash
#!/usr/bin/env bash
# Copy the canonical conformance fixtures into the Swift SDK's test resources.
# Run after editing anything in ../fixtures. Override the SDK location with
# APPFEEDBACK_SWIFT_DIR if it is not the sibling ../AppFeedbackSDK.
set -euo pipefail
SPEC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_DIR="${APPFEEDBACK_SWIFT_DIR:-$SPEC_DIR/../AppFeedbackSDK}"
DEST="$SWIFT_DIR/Tests/AppFeedbackCoreTests/Fixtures/conformance"
mkdir -p "$DEST"
cp "$SPEC_DIR/fixtures/format-cases.json" "$DEST/format-cases.json"
cp "$SPEC_DIR/fixtures/parse-cases.json" "$DEST/parse-cases.json"
echo "Synced fixtures → $DEST"
```

Make it executable:
```bash
chmod +x /Users/amir/Developer/appfeedback-spec/scripts/sync-to-swift.sh
```

- [ ] **Step 7: Verify the sync script round-trips (no diff)**

Run:
```bash
/Users/amir/Developer/appfeedback-spec/scripts/sync-to-swift.sh && cd /Users/amir/Developer/AppFeedbackSDK && git status --short Tests/AppFeedbackCoreTests/Fixtures/conformance
```
Expected: the script prints "Synced fixtures → …" and `git status` shows **no changes** (the spec copies are identical to the committed SDK fixtures).

- [ ] **Step 8: Initialise the repo and commit**

```bash
cd /Users/amir/Developer/appfeedback-spec && git init -q && git add -A && git commit -q -m "feat: AppFeedback wire-format spec, relay contract, golden fixtures" && git log --oneline -1
```
Expected: one commit listed.

---

### Task 7: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full SDK suite once more**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift test 2>&1 | tail -40
```
Expected: all suites pass, including `DeterministicByteCountTests`, `AttachmentSizeFormatTests`, `ExtraFieldsOrderingTests`, `RecognisedOSNamesTests`, `ConformanceTests`, and all pre-existing suites.

- [ ] **Step 2: Confirm the SDK branch history**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && git log --oneline main..feat/p0-contract-foundation
```
Expected: five feature commits (Tasks 1–5).

- [ ] **Step 3: Confirm `ByteCountFormatter` is fully removed from the source**

Run:
```bash
cd /Users/amir/Developer/AppFeedbackSDK && grep -rn "ByteCountFormatter" Sources || echo "none in Sources (expected)"
```
Expected: `none in Sources (expected)`.

- [ ] **Step 4: Confirm the spec repo exists and is committed**

Run:
```bash
cd /Users/amir/Developer/appfeedback-spec && git status --short && ls fixtures
```
Expected: clean working tree; `format-cases.json` and `parse-cases.json` listed.

---

## Self-Review (completed by plan author)

**Spec coverage (design §4):** ✅ deterministic byte formatter (Tasks 1–2, `wire-format.md`); ✅ em-dash pinned (documented in `wire-format.md`, exercised by the image-attachment fixture); ✅ extraFields code-point ordering (Task 3, fixture `extra-fields-codepoint-order`); ✅ votes footer UTF-8 (exercised by every format fixture); ✅ `recognisedOSNames` extension (Task 4); ✅ relay HTTP contract (`relay-contract.md`); ✅ golden fixtures + conformance harness as CI gate (Task 5); ✅ `appfeedback-spec` repo (Task 6).

**Out of P0 scope (correctly deferred):** attachment sanitize/dedup byte-exact porting (lands with the Android/Web ports under fixtures); submodule wiring (P0 uses copy + sync script per design §11 default-to-simple for bootstrapping); non-ASCII collation adversarial corpus beyond the seed `é` case (expand during port phases).

**Placeholder scan:** no TBD/TODO; every code/JSON/doc step contains complete content.

**Type/name consistency:** `DeterministicByteCount.string(_:)`, `IssueBodyFormatter.codePointOrder(_:_:)`, and `BodyMarker.recognisedOSNames` are referenced consistently across tasks; fixture JSON keys match the `Decodable` models in `ConformanceTests.swift`; `FeedbackType` raw values (`bug`, `feature-request`) match `Sources/AppFeedbackCore/FeedbackType.swift`.
