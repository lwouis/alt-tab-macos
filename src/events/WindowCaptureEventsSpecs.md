# WindowCaptureEvents — Specs

## Summary

One-shot window screenshots for thumbnails and Preview. macOS 27 routes trusted thumbnails through
the private `CGSHWCaptureWindowList` path. It keeps ScreenCaptureKit only for full-size Preview frames.
macOS 26 keeps ScreenCaptureKit for both uses. Older versions use `CGSHWCaptureWindowList`.

## SCK API selection

Two public one-shot APIs exist, each broken differently:

- `captureSampleBuffer` returns a zero-copy IOSurface, but Apple implements each call by creating and
  destroying a capture stream. On some machines that churn leaks WindowServer memory until macOS
  force-logs-out the session (#5786). Each call also emits WindowServer `Creating sharing context` events
  and `Screenshots via streams are inefficient` warnings.
- `captureScreenshot` (new in macOS 26) creates no per-call stream (zero of the above events), but:
  - it fails with `SCStreamError -3811` for a fullscreen window whose Space is not frontmost (it succeeds
    when that Space is frontmost, and for minimized, other-Space, partially-offscreen, and tabbed windows);
  - it returns a copied `CGImage` instead of an IOSurface, which measurably slows full-resolution captures
    of large windows (relevant to Preview; at thumbnail sizes it is slightly *faster* than
    `captureSampleBuffer`).

Routing: `captureScreenshot` for every window, except fullscreen windows and, when any shortcut's
effective settings enable preview-selected-window, all windows (full-resolution path) — those use
`captureSampleBuffer`.

On macOS 27, this routing applies only to full-size Preview frames. Trusted thumbnails use WindowServer
to avoid repeated replayd identity resolution. An SCK error keeps the prior image and starts a 15-second
cooldown. A successful non-prompting preflight does not convert that error into a permission prompt.

## Edge cases

- **Stale fullscreen state**: `isFullscreen` is snapshotted on the main thread when the burst is built, so
  a window mid-transition can be routed to `captureScreenshot` and fail with -3811. Deliberately no
  fallback/retry: the thumbnail keeps its previous contents and the next refresh re-routes. A fallback
  would silently reintroduce stream churn and hide new failure modes.
- **Preview is burst-wide, not per-window**: background captures aren't tied to a shortcut, so if any
  shortcut slot enables preview, every capture in the burst is full-resolution and uses
  `captureSampleBuffer` (`Preferences.anyShortcutUsesPreview`).
- **Privacy attribution cost is API-independent**: both APIs flip replayd's screen-capture attribution
  (~4 `updateScreenCaptureDidStart` events per capture) and cost systemstatusd the same CPU (measured
  within 2%). Switching APIs fixes the WindowServer leak, not the per-capture attribution overhead.
- **Background capture disabled**: a closed switcher submits no capture request. Focused-window
  background capture follows the same setting.

## Measurements (2026-07-11, macOS 26.5.1, M-series, 29-window payload, 10 switcher cycles per run)

| per run (~355 captures) | captureSampleBuffer | captureScreenshot |
|---|---|---|
| WindowServer sharing contexts / warnings | ~355 / ~355 | 0 / 0 |
| capture latency mean (thumbnail sizes) | 706 ms | 644 ms |
| capture latency mean (full-res, ≤5.2 MP) | 709 ms | 664 ms |
| replayd CPU | 2.0 s | 1.8 s |
| systemstatusd CPU | 4.8 s | 4.7 s |
| failures | 0 | only fullscreen-on-inactive-Space, always -3811 |
