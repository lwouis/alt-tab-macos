# Menubar popover lifetime

An existing status-item window with a nonempty frame is not enough to present a popover.
Its window must be visible and the anchor's bounds must intersect its visible rect. AppKit
silently ignores `show` otherwise (`NSPopover.h`). The window must also lie inside a screen's menu
bar, clear of the notch: macOS 27 parks an item it has no room for, or one hidden by AltTab's own
setting, off-screen at (0, -33) while still calling it visible, and AppKit then shows the popover
in the bottom-left corner of the screen. An item switched off in System Settings before launch is
never placed at all. `StatusItemAnchor` holds the measurements.

Keep the pending content until view/window layout or an application update makes the anchor
usable, for at most `settleTimeout` (1s; macOS places a new item in 50 to 300ms). Past that, or at
once when AltTab's setting hides the icon, show the same content without the arrow, centered under
the menu bar of the main screen. One timer per request fires at the deadline, since an item that is
never placed produces no layout event. Coalesce retries on the main queue; there is no polling
after presentation or cancellation. A pending trial popover also counts as occupying the prompt
slot, so Search education does not overlap it, and the deadline bounds how long it does.

An item switched off in System Settings while AltTab runs keeps reporting a usable frame; the
popover then points at where the icon was. That still shows the content, and the arrow tells the
user an icon lives there.

Replacing a request, closing the popover, purchasing Pro or summoning the switcher invalidates
all previously queued presentation work. The trial announcement is consumed only by the
matching did-show notification, not by merely asking AppKit to display it.

Explicit dismissal uses `close`, not `performClose`, which AppKit can refuse for child windows
or a delegate veto. Close without an outgoing animation before opening Settings or replacing
content. Release the content after both explicit and transient dismissal: button callbacks can
retain the popover through its own content view.

`AnchoredPopoverTests` runs the real request/observer/cancellation code with native presentation
and activation replaced. It covers delayed layout, rejected shows, cancellation by a newer
flow, replacement, actual-show acknowledgement, and content release. These tests do not display
windows or drive the desktop; they do not assert macOS's own animation or window-order behavior.

## Test scenarios

- **testAFrameAloneDoesNotMeanTheStatusItemCanHostAPopover** — a hidden window, an empty frame, empty
  bounds or bounds outside the visible rect each keep the anchor unusable.
- **testAnItemParkedOffScreenIsNotAnAnchor** — the (0, -33) parking spot waits, then falls back.
- **testAnItemNeverPlacedFallsBackOnceTheDeadlinePasses** — a zero-height item falls back after the deadline.
- **testAnItemUnderTheNotchIsNotAnAnchor** — a frame overlapping the notch is not usable.
- **testAnItemOutsideTheMenuBarIsNotAnAnchor** — below the menu bar or past the screen's edge is not usable.
- **testAnItemOnAnotherScreensMenuBarIsAnAnchor** — any screen's menu bar counts.
- **testAHiddenItemIsUnavailableAtOnce** — AltTab's own setting needs no waiting.
- **testAnUnavailableIconShowsTheContentWithoutAnchor** — the fallback shows the content once, unanchored.
- **testTheSettleDeadlineFallsBackWithoutAnotherEvent** — the deadline alone triggers the fallback.
- **testOnboardingWaitsForAUsableAnchorAndShowsOnceAfterLayout** — the request waits, shows on the first
  application update after the anchor is ready, and never again.
- **testAButtonLayoutChangeRetriesWithoutAnotherUserEvent** — a frame change on the anchor alone is
  enough to retry.
- **testARejectedNativeShowIsRetriedOnTheNextLayoutUpdate** — a `show` AppKit ignored stays pending.
- **testSummoningTheSwitcherCancelsAQueuedLessonBeforeItCanTakeFocus** — a cancelled request never shows.
- **testReplacingAnUnshownLessonOnlyPresentsTheLatestContent** — two requests show once, with the
  latest content.
- **testTheTrialAnnouncementIsConsumedOnlyAfterThePopoverAppears** — the callback waits for the
  matching did-show, and runs once.
- **testClosingAQueuedReminderPreventsItFromAppearingAfterPurchase** — closing before the show cancels
  both the show and its callback.
- **testClosingReleasesContentThatRetainsItsPopover** — `close` breaks the content-popover cycle.
- **testTransientDismissalAlsoReleasesTheContent** — a dismissal AppKit made does the same, and
  nothing shows again.
