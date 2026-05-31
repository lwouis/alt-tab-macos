# PermissionCalloutResolver — Specs

> **Line coverage:** _pending — run `/coverage-explore` to populate_

## Summary

The menubar shows a callout — "AltTab is running without Screen Recording permissions. _X_ won't
show." — with a "Grant permission" button. It used to appear for **every** user missing the
permission, including users who deliberately skipped it and don't use any feature that needs it
(reported in [#5623](https://github.com/lwouis/alt-tab-macos/issues/5623)), and it always blamed
"Thumbnails" even when the user relied on window previews instead.

Screen Recording is consumed by exactly two features: the **Thumbnails** appearance style (window
screenshots) and the **preview selected window** overlay. `PermissionCalloutResolver` is the pure
kernel deciding when the callout is worth showing and which feature(s) it names, split in two:

- `dependentFeatures(usesThumbnails:usesPreviews:)` — classify the two independent "used by any
  shortcut" flags into the affected feature set: `.none`, `.thumbnails`, `.previews`, or `.both`.
- `shouldShowCallout(screenRecordingGranted:dependentFeatures:)` — given the permission state and the
  affected features, show the callout? (missing permission AND not `.none`.)

## Behavior & edge cases

- **The two inputs are independent dimensions.** The callout shows only at their intersection:
  permission missing **and** at least one feature depends on Screen Recording. The combinations where
  the permission is granted, or where `dependentFeatures` is `.none`, all hide it.
- **`screenRecordingGranted` collapses three permission states into two.** Production passes
  `ScreenRecordingPermission.status == .granted`, so both `.skipped` (user opted out) and
  `.notGranted` (never granted) map to `false` → "permission missing". They behave identically.
- **`dependentFeatures` is an OR of each flag across all shortcut slots.** Production computes it as
  `Preferences.screenRecordingDependentFeatures`, which OR-s the Thumbnails flag and the Preview flag
  independently over every shortcut (`0...maxShortcutCount`) using the *effective* per-shortcut
  appearance style and preview flag. So a per-shortcut override that turns on Thumbnails/Preview on a
  single slot is enough to surface the callout, even when the global appearance is Titles/App Icons.
- **Titles and App Icons render no screenshots**, so they pass `usesThumbnails: false`. Only the
  `.thumbnails` style passes `true`.
- **The copy names only the affected feature(s)**, so the callout never promises back a feature the
  user doesn't use. The message is one reusable template with the subject inserted at `%@`; the
  Thumbnails subject reuses the existing "Thumbnails" appearance-style translation.

## Test scenarios

Mirrors `PermissionCalloutResolverTests.swift` 1:1.

### Which features the settings depend on
- **testThumbnailsOnlyClassifiedAsThumbnails** — Thumbnails on, Preview off → `.thumbnails`.
- **testPreviewsOnlyClassifiedAsPreviews** — Preview on, Thumbnails off → `.previews`.
- **testBothFeaturesClassifiedAsBoth** — both on → `.both`.
- **testNeitherFeatureClassifiedAsNone** — Titles/App Icons, Preview off → `.none` (the #5623 case).

### When the callout shows vs. stays hidden
- **testGrantedNeverShowsEvenWhenUsed** — permission granted + `.both` → hide (it works, no need to nag).
- **testGrantedNeverShowsWhenUnused** — permission granted + `.none` → hide.
- **testMissingPermissionShowsForThumbnails** — permission missing + `.thumbnails` → **show** (names Thumbnails).
- **testMissingPermissionShowsForPreviews** — permission missing + `.previews` → **show** (names Window previews).
- **testMissingPermissionShowsForBoth** — permission missing + `.both` → **show** (names both).
- **testMissingPermissionHiddenWhenUnused** — permission missing + `.none` → hide (the #5623 fix).
