# AppFeedback SDK — Android, Web & Documentation Expansion

- **Date:** 2026-06-05
- **Status:** Approved design — pending spec review, then per-phase implementation plans
- **Scope:** Expand the existing Swift/Apple `AppFeedbackSDK` into a three-platform SDK family (Apple · Android · Web) with a shared wire-format contract and a high-quality documentation website.

---

## 1. Context

`AppFeedbackSDK` (at `/Users/amir/Developer/AppFeedbackSDK`) is a SwiftPM package that lets an app submit a bug/feature report which becomes a **GitHub issue in a byte-exact body format**. A separate "inbox" app (`/Users/amir/Developer/AppFeedback`) reads those issues back via `AppFeedbackCore.IssueBodyParser` and presents them for triage. The issue **body + labels** are the wire contract between the two ends.

Current packages:
- **`AppFeedbackCore`** — headless: `FeedbackReport`, `FeedbackType`, `DeviceInfo`, `IssueBodyFormatter`/`IssueBodyParser`, `GitHubDirectTransport`, attachment pipeline (`FeedbackAttachmentValidator`, `ImagePreprocessor`, `AttachmentUploader`), `FeedbackTransport` protocol.
- **`AppFeedbackUI`** — themeable SwiftUI `FeedbackSheet`.

**Goal:** ship idiomatic Android (Kotlin) and Web (TypeScript) SDKs with full UI parity, published as public OSS, plus a documentation site — without ever drifting from the wire contract the inbox depends on.

The inbox app consumes the SDK package: `AppFeedback/Services/IssueBodyParser.swift` is a thin shim over `AppFeedbackCore.IssueBodyParser.parse(_:)`. **Any change to the shared `BodyMarkers` / parser in the SDK flows into the inbox automatically.**

## 2. Decisions (with rationale)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Full UI parity** on Android & Web (Compose sheet + web widget), not headless-only | User requirement; matches the iOS `FeedbackSheet` drop-in experience. |
| 2 | **Web UI** = framework-agnostic widget **+** thin React wrapper | Widest reach (any site/framework) plus an idiomatic React component; mirrors how Sentry/Intercom-style widgets ship. |
| 3 | **Public OSS, published** (Maven Central + npm) | Third parties install it; implies signing, write-only/relay security, polished docs, strict semver. |
| 4 | **Idiomatic native ports** bound by a **shared wire-spec + golden-fixture conformance suite** — **not** Kotlin Multiplatform | The core is tiny (`IssueBodyFormatter` ~90 lines, parser ~170). KMP's web-consumer tax (non-idiomatic `.d.ts`, enums not `@JsExport`-able, Kotlin stdlib bundle weight, Gradle forced on the web build) outweighs its one benefit — sameness — which the protobuf model (one spec + cross-language test vectors) delivers more cheaply and verifiably. |
| 5 | **Web transport = adopter-hosted relay**; direct-token is a dev-only escape hatch | A browser cannot hold a writable token safely — everything shipped to the browser is world-readable, and GitHub's push-to-public-repo auto-revoke does **not** catch tokens embedded in site JS. Every peer SDK ships a public write-only key and keeps the secret server-side. **Adopters run their own relay and hold their own token** (Firebase / Appwrite / generic / custom). |
| 6 | **Extend `recognisedOSNames`** with `Android, Windows, Linux, Web, ChromeOS` | Otherwise Android/Web feedback lands in the inbox with a blank OS column. Single-file change in the SDK; the inbox picks it up via the shared parser. |

## 3. Architecture overview

```
AppFeedback SDK family — polyrepo, independent per-platform semver
│
├── appfeedback-spec        ← THE CONTRACT (source of truth, vendored into each SDK)
│     • wire-format spec (issue body + labels)
│     • relay HTTP contract (browser ⇄ relay)
│     • golden fixtures: input → exact expected bytes (+ parse round-trips, adversarial)
│
├── AppFeedbackSDK (Swift)  ← EXISTS; becomes the reference implementation
│     • determinism hardening + OS-name extension + conformance test
│
├── appfeedback-android (Kotlin)
│     • appfeedback-android          (headless core)
│     • appfeedback-android-compose  (UI)            → Maven Central
│
├── appfeedback-web (TypeScript, pnpm workspace)
│     • @appfeedback/core    (framework-agnostic)
│     • @appfeedback/widget  (vanilla / Web Component)
│     • @appfeedback/react   (thin wrapper)
│     • @appfeedback/relay   (portable handler) + adapters → npm
│
└── appfeedback-docs (Astro Starlight)
      • guides + multi-language code tabs + platform picker
      • /reference/{swift,kotlin,typescript}/ (DocC / Dokka / TypeDoc)
```

Each SDK is a **write-only client**: it FORMATS and SUBMITS. Only the inbox PARSES. Ports therefore need a byte-exact **formatter**; they implement the **parser** only to support the conformance round-trip tests.

## 4. The contract layer (P0 — foundation, build first)

### 4.1 The wire format (current, to be promoted to the canonical spec)

Produced by `IssueBodyFormatter.format(report:deviceInfo:uploaded:)`:

```
<description>

---
**Device Information:**
App: <appName>
App Version: <appVersion> (<buildNumber>)
Device: <model>
<osName> Version: <osVersion>

**Contact Email:**          ← only when contactEmail is non-empty
<email>

**<key>:**                  ← one block per extraFields entry, keys sorted (see 4.2)
<value>

<!-- attachments-v1 -->     ← only when there are uploaded attachments
## Attachments

<prefix>[<filename>](<url>) — <mime>, <size>   ← <prefix> = "!" for image/* else ""; one per attachment

<!-- /attachments-v1 -->

---
👍 Votes: 0
```

- **Labels** = `[<FeedbackType.rawValue>, "user-submitted"]` where `rawValue ∈ { "bug", "feature-request" }`.
- Block separators are `\n\n`; the device block lines are single-`\n` separated.

### 4.2 Byte-exactness pins (hazards confirmed in source)

These MUST be specified exactly or three hand-written implementations will silently diverge:

1. **Attachment size formatting** — Swift currently uses `ByteCountFormatter.string(fromByteCount:countStyle:.file)` (`IssueBodyFormatter.swift:78`), which is **locale- and OS-version-dependent** (can emit `kB`/`KB`, non-breaking spaces, decimal grouping, different unit thresholds). **Resolution:** replace it in the Swift SDK with a **deterministic, locale-invariant** formatter (fixed unit set, fixed `.` decimal, fixed rounding, ASCII space), and pin that algorithm in the spec. *(Note: the parser's `parseHumanByteCount` is deliberately lossy/tolerant, so this protects visual consistency and the size-extraction path, not a strict numeric round-trip.)*
2. **Attachment separator** — literal em-dash `" — "` (U+2014, ASCII spaces around it); the parser keys on `rest.hasPrefix("—")` (`IssueBodyParser.swift:214`). Pin the exact code point; an en-dash/hyphen silently fails to parse.
3. **`extraFields` ordering** — `keys.sorted()` (`IssueBodyFormatter.swift:70`) uses Swift's Unicode-scalar ordering. Pin **codepoint order** (and document it) so Kotlin `sortedWith(compareBy { it })` / JS `.sort()` match for non-ASCII keys.
4. **Votes footer** — literal `👍 Votes: 0`; must be byte-identical UTF-8 (no variation-selector stripping). Source files UTF-8.
5. **OS-name line** — `<osName> Version: <osVersion>`; parser recognizes the line only if `osName ∈ recognisedOSNames`. Extend that set (decision 6).
6. **Attachment filename handling** — `AttachmentUploader.sanitize` + `deduplicate` produce the filename that appears in the body, so both must be ported **byte-exactly** (covered by fixtures).

### 4.3 `recognisedOSNames` extension

`BodyMarker.recognisedOSNames` (`BodyMarkers.swift:24`) and its derived regex `osVersionPattern` gain: `Android`, `Windows`, `Linux`, `Web`, `ChromeOS`. Because the inbox parses via `AppFeedbackCore.IssueBodyParser`, this is the only edit needed for Android/Web feedback to get a proper OS column. Add fixtures covering each new OS name.

### 4.4 The relay HTTP contract

The browser SDK speaks only to the adopter's relay. The contract (pinned in the spec, language-neutral):

- **Request** `POST <relayEndpoint>` (JSON): `{ type, title, description, contactEmail?, extraFields?, deviceInfo{appName,appVersion,buildNumber,model,osName,osVersion}, attachments?: [{ filename, mimeType, dataBase64 }], captchaToken? }`.
- **Response** `200`: `{ issueNumber: number, issueUrl: string }`. Error codes: `400` (validation), `401/403` (auth/captcha), `413` (payload too large), `429` (rate-limited), `502` (GitHub upstream).
- The relay — not the browser — performs attachment upload and issue creation (it holds the credential and the contents-API write scope), so the relay owns final body assembly using the same formatter.

### 4.5 Golden fixtures

A language-neutral corpus seeded from `Tests/AppFeedbackCoreTests` (`RoundtripTests.swift`, `Fixtures/`):
- `format/` — `{ report, deviceInfo, uploaded } → exact expected body string` (UTF-8 bytes).
- `parse/` — `body → expected ParsedFeedbackBody` (incl. hand-written/legacy/tolerant cases).
- Adversarial: unicode `extraFields` keys, em-dash edge cases, every recognized OS name, empty/long fields, multiple attachments with dedup collisions, image vs non-image prefixes.
- Each SDK's test target consumes these as a **blocking CI gate**. Adding a format change REQUIRES adding a fixture.

## 5. P1 — Android (`appfeedback-android`)

- **Modules:** `appfeedback-android` (headless core, zero Compose dep) + `appfeedback-android-compose` (UI). Mirrors the `AppFeedbackCore` / `AppFeedbackUI` split.
- **Core:** data models; `IssueBodyFormatter`/`IssueBodyParser` ported against fixtures; `DeviceInfo` from `Build.MODEL` / `Build.MANUFACTURER` / `Build.VERSION.RELEASE` + the app's `versionName`/`versionCode`, `osName = "Android"`; `suspend fun submit(...)` transport interface; **`RelayTransport`** (default) + **`GitHubDirectTransport`** (escape hatch — acceptable on native since the token stays in the app); attachment validate/preprocess/upload. HTTP via **Ktor client** (clean coroutines, future-proof) — OkHttp acceptable alternative.
- **UI:** themeable Compose `FeedbackSheet` mirroring the SwiftUI sheet (type selector, validation, success animation, attachment picker).
- **Publish:** Maven Central via the **Sonatype Central Portal** (OSSRH is shut down) using `com.vanniktech.maven.publish`; `groupId = io.github.<owner>` (GitHub-verified), `artifactId = appfeedback-android` (+ `appfeedback-android-compose`), Android `namespace = com.appfeedback.sdk`, **minSdk 24**; in-memory GPG signing + Portal user token in CI; signed sources + javadoc jars + complete POM.

## 6. P2 — Web (`appfeedback-web`) + relay

- **`@appfeedback/core`** (framework-agnostic): models; formatter/parser ported against fixtures; `DeviceInfo` from `navigator.userAgent` / `userAgentData` (best-effort — document that browser device fields are coarse); **`RelayTransport`** (default) + **`DirectGitHubTransport`** behind an explicit `dangerouslyUseClientToken` flag (dev/internal only).
- **`@appfeedback/widget`**: framework-agnostic embeddable (Web Component / single import), themeable, parity with the native sheets.
- **`@appfeedback/react`**: thin wrapper; `react`/`react-dom` in `peerDependencies` (`>=18 <20`); preserve `'use client'` for RSC.
- **`@appfeedback/relay`**: portable handler — verify CAPTCHA (Turnstile/hCaptcha) → rate-limit/dedupe/payload-cap → upload attachments to the `feedback-attachments` branch → format body (reuses `@appfeedback/core`) → create issue → return `{issueNumber, issueUrl}`. Credential held in the **adopter's** env: GitHub **App installation token** (recommended; 1-hour, repo+permission scoped) or fine-grained **PAT** (quickstart).
  - **Adapters:** generic `Request→Response` (Cloudflare Workers / Vercel / Netlify / Deno / Bun), **Firebase Cloud Function**, **Appwrite Function**. Non-JS stacks implement the §4.4 contract directly.
- **Build/publish:** tsup dual ESM/CJS (`--format cjs,esm --dts`), `exports` map with `types` first + `.d.ts`/`.d.cts`, `sideEffects:false`, gated by `@arethetypeswrong/cli` + `publint`; published to npm. JS packages live in one **pnpm-workspace** monorepo.

## 7. P3 — Documentation (`appfeedback-docs`)

- **Astro Starlight** hub — best out-of-box visual quality, zero-JS-by-default, **Pagefind** local search, **Expressive Code** Swift/Kotlin/TS code tabs. (Docusaurus is the fallback only if dropdown multi-version docs become a hard day-one requirement.)
- **IA:** quickstart-first with a **platform picker**; guides for install-per-platform, theming, localization, **relay setup** (Firebase/Appwrite/generic + the contract), the security model, the body-format spec, and migration; sample apps per platform.
- **API reference**, generated in one CI job to stable sub-paths: DocC → `/reference/swift/` (`swift-docc-plugin --transform-for-static-hosting --hosting-base-path /reference/swift`, served as its own SPA), Dokka HTML → `/reference/kotlin/` (restyled to brand), TypeDoc → `/reference/typescript/` (optionally also `starlight-typedoc` to pull TS API pages into the theme/search). Existing DocC catalogs (`AppFeedbackCore.docc`, `AppFeedbackUI.docc`) feed both reference and conceptual content.
- **Host:** GitHub Pages or Cloudflare Pages; branch-based versioning (a docs branch/tag per release) rather than the immature `starlight-versions` plugin. The shell can stand up during P0 and fill in as platforms land.

## 8. Cross-cutting concerns

- **Repos & versioning:** polyrepo; **independent per-platform semver** (don't block a web patch on an Android release); a compatibility matrix in each README. Lockstep only *within* a repo's modules. No single all-language monorepo (Turborepo is JS-only; Nx/Bazel overkill for a small team; each ecosystem wants its own CI cadence).
- **Source of truth:** `appfeedback-spec` is git-submodule'd (or vendored + synced) into each SDK's test target. The **conformance gate is mandatory** in all CIs — it is the only thing preventing silent drift between three hand-written implementations.
- **Security posture:** the default, documented path is always the relay (web) / Keychain-or-relay (native). `dangerouslyUseClientToken` is named to discourage misuse and documented as dev/internal-only.

## 9. Phased roadmap

Each phase gets its own implementation plan (writing-plans) when reached.

| Phase | Deliverable | Depends on |
|-------|-------------|------------|
| **P0** | `appfeedback-spec` (wire spec + relay contract + golden fixtures) **and** Swift hardening (deterministic byte formatter, em-dash/collation/footer pins, `recognisedOSNames` extension, Swift conformance test). Optionally stand up the docs shell. | — |
| **P1** | `appfeedback-android` core + `appfeedback-android-compose` UI + Maven Central publish + conformance gate in CI. | P0 |
| **P2** | `@appfeedback/{core,widget,react,relay}` + relay adapters (generic/Firebase/Appwrite) + npm publish + conformance gate in CI. | P0 |
| **P3** | `appfeedback-docs` Starlight site + DocC/Dokka/TypeDoc references + CI deploy. | P1, P2 (references); shell can start at P0 |

P1 before P2: Android is closer to the existing model (native, optional direct transport, no relay infrastructure), so it validates the port-against-fixtures approach before P2 adds the novel relay surface. UI ships within each platform's phase to keep parity.

## 10. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Byte-exactness drift (size formatter, em-dash, collation, emoji) | Spec pins (§4.2) + Swift determinism fixes + golden fixtures + CI gate. |
| Relay abuse / GitHub quota exhaustion (one credential shares 5,000 req/hr + 500 issues/hr) | Reference relay ships CAPTCHA (Turnstile/hCaptcha), per-IP rate limiting, dedupe, payload caps. |
| Source-of-truth drift between 3 implementations | `appfeedback-spec` as single source; conformance gate **blocking** in every CI; format change requires a new fixture. |
| Weak/coarse web device-info (`navigator.userAgent` frozen, `userAgentData` Chromium-only) | Document expectations; map best-effort to App/Device/OS lines in the spec. |
| Attachment differences (HEIC, ~1 MB base64 PUT limit, sanitize/dedup) | Relay owns uploads (blobs API / external store for large); `sanitize`/`deduplicate` ported under fixtures. |
| "KMP is fine now" re-litigation (JetBrains fixed suspend-export in 2.3.0, Long→BigInt in 2.2.20) | Decision stands for *this tiny core*; revisit KMP only for a future large, logic-heavy, mostly-internal shared core. |

## 11. Open / deferred decisions

- **Relay default backend to lead docs with:** generic Cloudflare/Vercel handler vs Firebase vs Appwrite — ship all three; pick the docs' lead example at P2.
- **Relay credential default in quickstart:** GitHub App (recommended prod) vs fine-grained PAT (simplest) — document both.
- **Web client identity abstraction:** a Sentry/Canny-style public "project key" mapped server-side vs adopters hardcoding `owner/repo` in their relay config. Default to the simpler relay-config approach for v1; revisit if a hosted offering emerges.
- **Spec/fixtures distribution:** git submodule (single source, checkout friction) vs vendored copy + sync script. Default to submodule.
- **Additional web framework adapters** (Vue, Svelte): defer past v1 (core + widget + React first).

## 12. References

Key primary sources behind the decisions (full set in the research run `wf_1297f28a-293`):
- GitHub CORS / token revocation / rate limits / GitHub App installation tokens / contents API.
- Kotlin supported-platforms, `@JsExport` limitations, Ktor client targets; protobuf conformance model.
- Astro Starlight (Expressive Code, Pagefind), `swift-docc-plugin` static hosting, Dokka HTML, TypeDoc plugins.
- Peer SDK patterns: Sentry DSN/tunnel, Canny HMAC identify, Bugsnag/Instabug repo layouts.
- Sonatype Central Portal + vanniktech plugin; tsup dual ESM/CJS + `attw`/`publint`; Stripe/Sentry independent-semver precedent.
