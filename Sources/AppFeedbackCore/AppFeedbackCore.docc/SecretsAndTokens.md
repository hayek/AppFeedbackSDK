# Secrets and Tokens

Shipping a GitHub Personal Access Token inside an app binary is a known trade-off. Here's how the SDK handles it honestly.

## Overview

``GitHubDirectTransport`` requires a `token` parameter to POST to GitHub Issues. Wherever that token lives — embedded constant, obfuscated blob, fetched at runtime — the threat model is the same: **anyone with the binary can recover the token**. Disassembly, runtime memory dump, or a hooked HTTPS proxy will eventually surface it.

The SDK does not pretend otherwise. It exposes `token: String` directly and lets you decide the trade-off:

| Approach | Effort | Resists casual extraction | Resists determined extraction |
| --- | --- | --- | --- |
| Plaintext constant | trivial | no | no |
| XOR / obfuscated blob decoded at runtime | small | yes | no |
| Token fetched from your server at app start | medium | yes | no (once fetched, lives in memory) |
| Server-side relay holds the token | medium-high | yes | **yes** |

Only the last row genuinely contains the blast radius. The first three raise the bar; an attacker who actually wants the token will still get it.

## Acceptable use of an embedded token

A PAT inside the binary is reasonable when:

- The repo is a *write-only* feedback inbox and the worst-case abuse is spam issues you can delete.
- You can rotate the PAT quickly if abuse occurs (and have monitoring to notice).
- The PAT's scope is the minimum that lets it open issues — typically `public_repo` or `repo` for a private repo, nothing more.
- You're comfortable with someone using the same endpoint to spam your inbox.

If any of these stop being true, move to a relay.

## Moving to a relay

The cleanest mitigation is to keep the credential on a server you control and expose a thin HTTPS endpoint. The SDK ships a ready-made ``RelayTransport`` for exactly this — point it at your relay's URL and your app never sees a GitHub token:

```swift
let transport = RelayTransport(
    endpoint: URL(string: "https://your-relay.example.com/api/feedback")!,
    captchaTokenProvider: { await captcha.freshToken() }  // optional, fetched per submit
)
let feedback = FeedbackClient(appName: "AcmeApp", transport: transport)
```

``RelayTransport`` is wire-compatible with the same relays the AppFeedback Web and Android SDKs target. See <doc:CustomTransports> if you need to write your own transport for a different backend.

Once the relay holds the token, you also get:

- Rate-limiting per device / IP without burning GitHub's API quota.
- Spam filters before they reach your repo.
- Optional attachments (screenshots, logs) via your own CDN — the GitHub REST API doesn't accept binary uploads, but your server can mirror to one.
- Schema evolution without shipping a new app version.

## Don't store tokens in your repo

Even if you're embedding a PAT in the binary, the source should never have it in plaintext. Common pattern:

1. Keep the obfuscated/encoded form in source.
2. Decode it at runtime just before constructing the transport.
3. Restrict the PAT scope to issues-write only.
4. Have a documented rotation procedure.

## Topics

- ``GitHubDirectTransport``
- ``RelayTransport``
- <doc:CustomTransports>
