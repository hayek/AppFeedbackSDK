# Security Policy

## Supported versions

AppFeedback is pre-1.0 and evolving quickly. Security fixes land on the
latest `main`; there are no maintained back-release branches yet. Always
test against the current `main` before reporting.

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

- Email **hayek_dev@icloud.com**, or
- Open a [GitHub private security advisory](https://github.com/hayek/AppFeedbackSDK/security/advisories/new).

Include reproduction steps, affected version/commit, and impact. We aim to
acknowledge within a few days and will coordinate a fix and disclosure
timeline with you.

## Scope

In scope: the SDK source in this repository (feedback capture, payload
construction, and transport). Out of scope: vulnerabilities in third-party
dependencies (report those upstream) and issues that require a compromised
device or attacker-controlled toolchain.

The web SDK's security model — relay architecture and token handling — is
documented at <https://hayek.github.io/appfeedback-docs/guides/security/>.
