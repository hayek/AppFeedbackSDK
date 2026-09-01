# Theming

Customize the accent colors and all visible copy via ``FeedbackTheme``.

## Overview

``FeedbackSheet`` reads two kinds of customization from its ``FeedbackTheme`` parameter:

- **Two accent colors** — one for bug reports (``FeedbackTheme/bugAccent``) and one for feature requests (``FeedbackTheme/featureAccent``). These drive the hero gradient, type-selector highlights, success ring, and submit-button accents.
- **All visible strings** — collected in ``FeedbackTheme/Copy`` so you can swap in pre-localized text without the SDK shipping a strings table.

One thing the theme deliberately does not cover: the native App Store rating prompt that can follow a submission. Its copy, layout, and localization come from the system, so there is nothing for ``FeedbackTheme/Copy`` to override.

```swift
FeedbackSheet(
    client: feedback,
    theme: FeedbackTheme(
        bugAccent: .red,
        featureAccent: .blue,
        copy: .default
    )
)
```

## Matching your brand

Most apps want the bug accent to look like a "destructive" color and the feature accent to look like a "primary" color. Both should have sufficient contrast against `Color.white` (the icon color on filled chips and the hero rectangle):

```swift
FeedbackTheme(
    bugAccent: Color(red: 0.95, green: 0.30, blue: 0.40),
    featureAccent: Color(red: 0.45, green: 0.45, blue: 1.00),
    copy: .default
)
```

`Color`-based instantiation works on all supported platforms; if you prefer asset-catalog colors:

```swift
FeedbackTheme(
    bugAccent: Color("BugAccent"),
    featureAccent: Color("FeatureAccent"),
    copy: .default
)
```

## Defaults

``FeedbackTheme/default`` provides a balanced red/blue palette and English copy. Use it as the starting point for partial overrides:

```swift
var theme = FeedbackTheme.default
theme.bugAccent = .orange   // matches AcmeApp's brand
let sheet = FeedbackSheet(client: feedback, theme: theme)
```

## Customizing the description limit

The character limit shown next to the description label is separate from the theme — it's a constructor parameter on ``FeedbackSheet`` because it affects validation, not visuals:

```swift
FeedbackSheet(client: feedback, theme: .default, descriptionLimit: 2000)
```

The sheet shows the count in monospace and turns red over the limit, but does not currently block submission. Enforce hard limits in your transport if needed.

## Topics

- ``FeedbackTheme``
- ``FeedbackTheme/Copy``
- <doc:Localization>
