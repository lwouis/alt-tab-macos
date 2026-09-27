# Menubar popover lifetime

An existing status-item window with a nonempty frame is not enough to present a popover.
Its window must be visible and the anchor's bounds must intersect its visible rect. AppKit
silently ignores `show` otherwise (`NSPopover.h`). Keep the pending content until view/window
layout or an application update makes the anchor usable. Coalesce retries on the main queue;
there is no timer and no background polling after presentation or cancellation. A pending trial
popover also counts as occupying the prompt slot, so Search education does not overlap it.

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
