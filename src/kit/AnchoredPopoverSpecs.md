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

The same deadline applies when an apparently usable anchor keeps rejecting native presentation.
Try the unanchored fallback once; if macOS rejects that too, release the content and prompt slot
without marking the message seen. Later eligible opportunities follow the journey's retry policy.

An item switched off in System Settings while AltTab runs keeps reporting a usable frame; the
popover then points at where the icon was. That still shows the content, and the arrow tells the
user an icon lives there.

Replacing a request, closing the popover, purchasing Pro or summoning the switcher invalidates
all previously queued presentation work. A blocked-feature popover already visible survives switching
and re-summoning; its application-defined lifetime is specified in `ProTransitionSpecs.md`. It opts out
of explicit application activation and making its window key, including when anchor layout finishes
after the chosen app has received focus. Other anchored popovers retain their activation behavior. The trial announcement is consumed by the matching
did-show notification or an explicit action in the displayed content, not by merely asking AppKit
to display it. Both share one acknowledgement: a fast style choice before the appearance animation
ends must not leave the Day 4 retry armed or consume the daily message budget twice.

Explicit dismissal uses `close`, not `performClose`, which AppKit can refuse for child windows
or a delegate veto. Close without an outgoing animation before opening Settings or replacing
content. Release the content after both explicit and transient dismissal: button callbacks can
retain the popover through its own content view.

`AnchoredPopoverTests` runs the real request/observer/cancellation code with native presentation
and activation replaced. It covers delayed layout, rejected shows, cancellation by a newer
flow, replacement, actual-show acknowledgement, and content release. These tests do not display
windows or drive the desktop; they do not assert macOS's own animation or window-order behavior.

## Appearance

Native popovers have their own appearance (defaulting to vibrant light), so status-item
popovers explicitly follow the application's effective appearance while a presentation is
active, including live theme changes. Closing stops that observation; reopening resolves
the current theme again. `testPopoverFollowsAppThemeWhilePresentedAndWhenReopened` covers
this independently of the anchor's appearance.

## Visual capture fixture

Only during a `QaSurfaces` capture, an anchored status-item popover uses a transparent fixed
anchor at the horizontal center of the screen. A wide popover near the screen edge otherwise
keeps its body clamped to that edge while its arrow follows the status item's moving position
(for example when the clock changes width). The fixed anchor preserves the complete native
outline for pixel comparison, without widening tolerance or masking the arrow. It inherits
the real anchor's appearance and is excluded from the photographed windows.

Closing the visual surface clears the override and hides the fixture. Ordinary presentations,
hidden-icon fallbacks, in-window info popovers and lifecycle tests retain their real positioning.
The override does not exist in Release builds.

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
- **testAReadyAnchorThatRejectsPresentationFallsBackAtTheDeadline** — a usable frame cannot keep a rejected show waiting forever.
- **testRejectedFallbackReleasesThePromptSlotWithoutAcknowledgingOrRetrying** — failed presentation releases its slot and consumes no message budget.
- **testSummoningTheSwitcherCancelsAQueuedLessonBeforeItCanTakeFocus** — a cancelled request never shows.
- **testReplacingAnUnshownLessonOnlyPresentsTheLatestContent** — two requests show once, with the
  latest content.
- **testTheTrialAnnouncementIsConsumedOnlyAfterThePopoverAppears** — the callback waits for the
  matching did-show, and runs once.
- **testAButtonActionBeforeTheAppearanceAnimationFinishesAcknowledgesOnlyOnce** — immediate action
  consumes the announcement once; a later notification cannot repeat it.
- **testClosingAQueuedReminderPreventsItFromAppearingAfterPurchase** — closing before the show cancels
  both the show and its callback.
- **testClosingReleasesContentThatRetainsItsPopover** — `close` breaks the content-popover cycle.
- **testTransientDismissalAlsoReleasesTheContent** — a dismissal AppKit made does the same, and
  nothing shows again.
