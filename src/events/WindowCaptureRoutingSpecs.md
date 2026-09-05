# WindowCaptureRouting — Specs

## Summary

The routing policy selects the lowest-risk capture backend for a thumbnail or a focused-window preview.
It also rejects background work when the user disables background capture.

## Behavior

- macOS 27 uses WindowServer for thumbnails after a trusted Screen Recording grant.
- macOS 27 uses ScreenCaptureKit for a focused-window preview because that feature needs a full-size frame.
- macOS 26 keeps the existing ScreenCaptureKit thumbnail backend.
- macOS 25 and older keep the existing WindowServer thumbnail backend.
- A closed switcher with background capture disabled gets no backend and submits no capture request.
- A focused-window preview needs an active switcher.

## Test scenarios

- `testMacOS27UsesWindowServerForTrustedThumbnails`
- `testMacOS27UsesScreenCaptureKitForFocusedPreview`
- `testMacOS26KeepsScreenCaptureKitThumbnailBackend`
- `testOlderMacOSKeepsWindowServerThumbnailBackend`
- `testBackgroundCaptureDisabledReturnsNoBackend`
- `testBackgroundCaptureEnabledUsesSafeMacOS27Backend`
- `testFocusedPreviewNeedsAnActiveSwitcher`
