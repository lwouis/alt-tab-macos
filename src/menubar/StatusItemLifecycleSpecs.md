# Status-item lifetime

AltTab's hidden-icon preference means no status item exists. A hidden launch must not create
one, even temporarily. Hiding an existing icon invalidates its visibility observation, detaches
the badge layer, calls `NSStatusBar.removeStatusItem`, and clears the owned reference. Merely
setting `isVisible = false` retains the status-item window; this was reported to block Apple-menu clicks on macOS 15.8.1
([#6142](https://github.com/lwouis/alt-tab-macos/issues/6142)).

Showing the icon creates an item only when needed. Configure its target, left/right mouse-down
actions, preferred image and badge before observing command-drag removal. Apply the image during
creation to avoid AppKit layout recursion. Updating an existing item reuses it. Recreating one
uses the current icon and license badge state; it retains the same menu and permission callout.

A command-drag visibility change queues removal on the next main-queue turn, outside AppKit's
KVO callback, then persists the hidden preference and updates Settings controls. A newer preference
change or a replaced item cancels obsolete removal work. Programmatic removal invalidates the
observer first and must not be interpreted as a command-drag preference change.

Menu initialization is independent of status-item existence: Settings and preference callbacks
remain available while hidden. Onboarding and Pro popovers pass a missing item through to
`AnchoredPopover`'s unanchored fallback. Opening the status menu while hidden does nothing.

`StatusItemLifecycleTests` exercises the production lifecycle with injected native effects:
hidden launch, configuration order, reuse, observer invalidation, reference release, repeated
hide/show with updated icon/badge inputs, deferred command-drag persistence and obsolete callbacks.
`AnchoredPopoverTests.testMissingStatusItemStillProvidesVisibleFeedback` covers the missing anchor.
These tests do not create a native status item, display windows or drive the desktop.
