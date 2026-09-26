# Main-thread IPC

Point-in-time audit, 2026-09-02, macOS 26.6.2 (25G83). The rule this exists to serve is in `AGENTS.md`;
this file is the inventory behind it.

Ordinary AppKit calls can turn into a synchronous XPC round trip. That was not known here until #5981: a
user's main thread sat for 3.017s inside `searchField.stringValue = ""`, because mutating a field that is
first responder makes AppKit resign it, and resigning deactivates the system text-input context, a
synchronous call into the input-method services that returned only by timing out. The three off-main
schedulers (`AXCallScheduler`, `CGSCallScheduler`, `ProcessCallScheduler`) do not cover this family.

## What is actually thread-safe

"AppKit is main-thread-only" is too coarse, and getting it wrong in either direction costs something, so
this was checked against the SDK headers, Apple's Main Thread Checker, and a live probe (below).

**Main-thread-only, enforced at runtime.** `NS_SWIFT_UI_ACTOR` sits on `@interface NSResponder` itself, so
the whole hierarchy is `@MainActor` in Swift: `NSWindow`, `NSView`, `NSControl`, `NSTextField`,
`NSSearchField`, `NSApplication`. Apple's Main Thread Checker
(`Xcode.app/Contents/Developer/usr/lib/libMainThreadChecker.dylib`) implements the same rule by swizzling
*every* method on classes descending from `NSResponder`, `NSCell` and `NSTextInputContext`, minus a short
whitelist it treats as genuinely thread-safe: `postEvent:atStart:`,
`discardEventsMatchingMask:beforeEvent:`, `abortModal`, `stopModal`, `stopModalWithCode:`, `lockFocus`,
`lockFocusIfCanDraw`, `lockFocusIfCanDrawInContext:`, `unlockFocus`, `openGLContext`, `snapshot`,
`beginDocument`, `performTextOperations:`. Nothing this app calls on a critical path is on that list.

**Documented thread-safe.** `NSRunningApplication` is `NS_SWIFT_SENDABLE` and its header says it "is thread
safe, in that its properties are returned atomically"; `NSWorkspace.runningApplications` says "This property
is thread safe, in that it may be called from background threads". Neither class is `NS_SWIFT_UI_ACTOR`, and
the Main Thread Checker does not swizzle them. So the LaunchServices reads in this codebase — including
`Application.fetchAppIcon`'s `runningApplication.icon` on `screenshotsQueue` — are correct by contract, not
by luck. Moving them back onto main would be the mistake.

### Verified by probe, macOS 26.6.2

A throwaway harness (a plain `swiftc` binary: `NSApplication` with `.regular` policy, a titled window holding
an `NSSearchField`, activated so the text-input context was live) made each call from a background queue,
one call per process so a crash in one didn't hide the others:

- `field.stringValue = "hello"` — **deadlocks**, permanently. `sample` shows an ABBA lock inversion: the
  background thread is inside `__NSConcreteTextStorageLockedForwarding` holding the text-storage lock, and
  reaches `SwiftUICore`'s `_MovableLockSyncMain` waiting for the main thread; the main thread is in the
  CoreAnimation commit's layout pass, blocked in `objc_sync_enter` on the same `NSTextContentStorage`. AppKit
  text does have internal locking, which is probably where the "parts of AppKit are thread-safe" impression
  comes from, but the lock is what builds the deadlock rather than what prevents it.
- `window.makeFirstResponder(...)` — **throws** `NSInternalInconsistencyException`,
  `-[_NSViewGeometryInWindowConcreteObservation invalidate] must be called on main thread only`, raised
  inside `-[NSTextView resignFirstResponder]`. That is the #5981 code path exactly. It only survives when no
  field editor exists to tear down.
- `window.orderOut(nil)` — **traps**. Disassembling `-[NSWMWindowCoordinator performTransactionUsingBlock:]`
  shows AppKit calling `[NSThread isMainThread]`, and on false falling through to
  `_os_crash("Must only be used from the main thread")` followed by `brk #0x1`, unless the app opts into the
  `NSWMBackgroundThreadCompatibility` app config. That is the `EXC_BREAKPOINT` the probe died on.
- `NSWorkspace.frontmostApplication` (0.58ms), `runningApplications` (0.10ms),
  `NSRunningApplication(processIdentifier:)` (0.14ms), `bundleURL` + `isHidden` + `icon` (56ms), and
  `activate(options:)` (8.5ms) all ran off-main with no complaint.

One number from the same harness is worth keeping: on the main thread, with a live input context,
`makeFirstResponder(nil)` took **62.9ms**. Resigning first responder is expensive even when nothing is
wrong, which is what makes the #5981 tail as bad as it is.

## Which lever applies

"Move it off the main thread" is available for almost none of this. What is left, roughly in order of how
often it applies:

1. **Reorder** so the stall lands after everything the user is waiting for. What #5981 did: the panel hides
   and the focus request goes out in `beginHideUi`, all bookkeeping in `endHideUi`.
2. **Defer one runloop turn.** The CoreAnimation transaction commits when the turn ends, so `alphaValue = 0`
   or an `orderOut` earlier in the same turn has *not* reached the screen yet — blocking later in that turn
   keeps the old frame up. Anything that can stall and isn't itself the visible work belongs in a
   `DispatchQueue.main.async`, with a guard for the state having moved on.
3. **Cache**, when the value is already maintained elsewhere from the same notifications
   (`Applications.frontmostPid` vs `NSWorkspace.shared.frontmostApplication`).
4. **Pre-warm at launch**, for one-shot lazy costs (`LiquidGlass.canUsePrivateLook`). Note where this does
   NOT reach: the first summon of a launch costs roughly 60ms more than later ones (`updateItemsAndLayout`
   22-29ms vs 2-6ms, `makeKeyAndOrderFront` 25-29ms vs 4-10ms, AppKit's frame render 29-33ms vs 4-6ms).
   Forcing a layout pass over the recycled tiles at launch was tried and moved none of it — it costs 0.8ms
   because empty views have nothing to lay out. The cost is first contact with real window content, so the
   only pre-warm that would work is running the whole summon invisibly at launch, which is not worth the
   risk or the CPU at login for 60ms once.
5. **Replace with a lower-level call that does no IPC.** Rarely available for AppKit.
6. **Move off-main**, for the set that permits it: Foundation, CoreGraphics, `CGS*` reads, AX calls, and
   `NSWorkspace` / `NSRunningApplication`. The first four already have their three front doors; use them.

Where none apply, the stall is unavoidable and the code should say so. `TilesPanel.orderOut`,
`makeKeyAndOrderFront` and `setContentSize` are the visible work: there is nothing to reorder them behind.

## On a critical path

Critical paths are: summoning the switcher, each keystroke while cycling or searching, dismissal with focus.

The per-keystroke path was measured separately, by scripting 25 `App.cycleSelection` steps 60ms apart with
the threshold at 1ms. With Preview off (the default) **not one step exceeded 1ms**. With Preview forced on,
the only costs are the preview window's own geometry and ordering, listed below. So the cycling path carries
no unbounded stall of the #5981 kind; the summon and the dismissal are where the risk lives.

| Call site | Service | Path | Evidence | Treatment |
|---|---|---|---|---|
| `TilesView.endSearchSession` — `stringValue` / `isEditable` | input-method services (`CursorUIViewService`, `CharacterPalette`) | dismissal | 3.017s in a reporter's unified log, plus `IMKServerXPCInvocation timed out`; 2–12ms measured here | deferred one turn (#5981), via `takeTheCaretFromTheField` |
| `TilesView.disableSearchMode` — `isEditable` / `stringValue` | same, deactivation side | Escape while searching | 4-7ms measured here, ahead of the `refreshUi` that restores the unfiltered list; the reporter's follow-up flow (#5981, summon → search → Escape → arrows → Enter) is this path | deferred one turn, same `takeTheCaretFromTheField` as the dismissal |
| `TilesView.enableSearchEditing` — `makeFirstResponder(searchField)` | same, activation side | summon in search style; search shortcut mid-session | <1ms measured; reporter's console shows `Create CursorUIViewService: TUINSRemoteViewController` 40–75ms after each summon | deferred one turn, with `giveTheFieldTheCaretNow` on the key path so a keystroke can't beat it |
| `Windows.voiceOverWindow` — `makeFirstResponder(tile)` | in-process | every selection change | 0.10-0.16ms over 29 calls. A tile is a plain view with no input context, so the responder change costs ~100µs against the 62.9ms a live text field costs — the price is the input context, not the responder change | already deferred 10ms, with a comment describing the symptom ("creates a delay in showing the main window") without naming the cause. Nothing more to do |
| `TilesPanel.show` — `alphaValue` + `makeKeyAndOrderFront` | WindowServer | summon | 14ms first summon, 7ms steady | unavoidable; it *is* the visible work |
| `TilesPanel.updateContents` — `setContentSize`, `setFrameOrigin` | WindowServer | summon, every search keystroke | the IPC here is small: `setContentSize` 2-4ms on the first summon and under 1ms after, `repositionOrFreeze`'s `setFrameOrigin` under 1ms always. What the step actually costs is `TilesView.updateItemsAndLayout`, our own view layout: 22-29ms first summon, 2-6ms steady | nothing to do here as IPC. If this step ever needs to get faster it is a layout problem, not a round-trip problem |
| `TilesPanel.orderOut` | WindowServer | dismissal | 3–9ms | unavoidable; visible work |
| `KeyboardEvents.updateEscapeAbsorptionTap` — `CGEvent.tapIsEnabled` + `tapEnable` | WindowServer event server | dismissal | 0–8ms, and it sat ahead of the panel hide | moved from `beginHideUi` to `endHideUi` |
| `CursorEvents.toggle` / `TrackpadEvents.setAbsorbTapEnabled` — `CGEvent.tapEnable` | WindowServer event server | summon, dismissal | <1ms | fine as is; already at gesture boundaries only, never per event |
| `ContextMenuEvents.toggle(true)` | in-process (`NotificationCenter`) | summon | 2ms on the first summon only | no IPC; first-call cost |
| `PreviewPanel.show` — `setFrame`, `order(.below:)`, `level` | WindowServer | every selection change, when Preview is on (off by default) | over 25 scripted cycles: `setFrame` 1-2ms on 6 of them, `order(.below:)` 2ms and 6ms, `level` always under 1ms. `PreviewPanel.hide()`'s `orderOut`, taken when the selected window has no frame yet, cost 4-5ms | none. It is bounded and it is the visible work for that feature. `order(.below:)` could be skipped while the panel is already visible and already on a lower level, but the flicker it exists to prevent (#preview z-order, see the comment there) needs two monitors to reproduce, so that is not worth trading blind for ~4ms on a minority of keystrokes |
| `Window.focus` — `NSWorkspace.shared.frontmostApplication` | LaunchServices | dismissal with focus, cross-Space branch only | 0.58ms off-main in the probe | left deliberately. It is thread-safe, so it *could* move into the AX block, and `Applications.frontmostPid` carries the same value — but both change WHEN the value is sampled, and it must be sampled before the focus request for the #5586 origin-Space repair to be right. Not worth re-risking for half a millisecond |
| `Window.focus` — `launchApplication` / `NSRunningApplication.activate` | LaunchServices | dismissal with focus, windowless-app branch | not measured | unavoidable; it *is* the requested action |
| `Windows.updatesBeforeShowing` — `Spaces.refresh` | SkyLight | summon, only mid-Space-transition | 0.1ms p50 (#5864) | already bounded to the topology read |
| `NSScreen.withActiveMenubar` — `CGSCopyActiveMenuBarDisplayIdentifier` | WindowServer | summon | one call, hoisted out of the per-screen predicate | fine as is |
| `Applications.findOrCreate` — `NSRunningApplication(processIdentifier:)`, `ApplicationDiscriminator` | LaunchServices, Carbon process IPC | new-pid path on main; `refreshBadges_` while open | — | already memoised per pid; the LaunchServices lookup is AppKit-cached |

## Every switcher interaction, swept

The table above grew out of the summon and the dismissal. This is the sweep of the rest, done the same way
(threshold at 1ms, scripted interaction, marks around single statements). The headline: **outside the summon
and the dismissal, the switcher does almost no IPC at all.** What remains is our own layout and AppKit's
frame render.

| Interaction | IPC on the path | Measured | Verdict |
|---|---|---|---|
| Cycle with the keyboard | none by default | no step over 1ms across 25 scripted cycles | clean |
| Cycle, Preview on | `PreviewPanel` `setFrame` / `order(.below:)` | 1-2ms and 2-6ms on a minority of keystrokes | bounded, and it is the visible work |
| Type in search | **none** | 8-20ms per keystroke: `Windows.updateSearchQuery`'s `sort()` 1-4ms, `refreshUi` 1-4ms, `updateContents` 3-9ms, AppKit's frame render 3-19ms | the heaviest interaction, but it is layout, not IPC. `CachedUserDefaults` memoises, so no cfprefsd read per keystroke, and search only re-sorts — it does not rebuild the filters |
| Mouse hover | none | `mouseLocationOutsideOfEventStream` is 0.0002ms mean and 0.0056ms worst over 300 separate runloop turns, so it is a local read, not a cursor query to the WindowServer. Tile hit-testing is a linear scan; `ensureTooltipsInstalled` is latched behind `tooltipsDirty` | clean. Do not "optimise" the location read by threading `cgEvent.location` through — there is nothing to win |
| Scroll | none | the tap callback only filters continuous scroll and runs off-main | clean |
| Trackpad gesture | `CGEvent.tapEnable` at gesture boundaries | under 1ms | already restricted to boundaries, never per event |
| Context menu | none | the switcher opens no `NSMenu`; `ContextMenuEvents` only observes other menus' tracking notifications | nothing to audit |
| Drag and drop | `NSWorkspace.open` on the drop | not measured | it is the requested action |
| Close / minimize / fullscreen / quit a tile | Accessibility | — | already on `BackgroundWork.accessibilityCommandsQueue` |

### The one place a stall costs more than a frame

`CursorEvents` is the only event tap whose callback runs on the main thread (`CFRunLoopGetMain()`); the
keyboard, scroll, trackpad, attention, Dock and CLI taps all run on their own threads. The justification in
that file is sound — it hit-tests views, which has to be on main. The consequence is worth naming: when the
main thread stalls, that tap is the one macOS can disable with `tapDisabledByTimeout`, and the symptom is
hover and clicks going dead in the switcher rather than merely a late frame. It self-heals via
`reEnableTapIfNeeded`, and no timeout was observed in any run here, but it is an extra reason the ordering
rules above are not just about smoothness.

## Not on a critical path

These do IPC and are allowed to block: nothing the user is mid-gesture for waits on them.

- `MainMenu.create` — `NSApp.servicesMenu` (pbs), `NSFontManager.shared`. Launch only. `MainMenu.toggle` and
  `toggleEditMenu`, which *do* run on the switcher path, only mutate `keyEquivalent` on menu items already
  built: in-process, no pbs.
- `SystemPermissions` — `TCCAccessCheckAuditToken`, `CGPreflightScreenCaptureAccess` (tccd),
  `CGWindowListCopyWindowInfo`, `SCShareableContent` (WindowServer). All on `permissionsCheckQueue`. What the show path reads
  (`ScreenRecordingPermission.status`) is a cached static.
- `Keychain` — `SecItem*` (securityd). License code only; unreachable during a summon.
- `ExceptionsTab`, `MoveToApplicationsFolder` — `NSWorkspace.icon(forFile:)`, `urlForApplication`,
  `runningApplications`, `Bundle(url:)` (LaunchServices + disk). Settings UI.
- `NSWorkspace.shared.open` for the support / checkout / account URLs (LaunchServices). Menu actions.
- `Application.fetchAppIcon`, `Applications.updateAppIcons` — `NSRunningApplication.icon` (IconServices).
  Already on `screenshotsQueue`, which the class's documented thread safety makes correct rather than lucky.
  Measured at 56ms for the first `bundleURL` + `isHidden` + `icon` read of a process, so it must stay there.
- Thumbnail capture — `CGSHWCaptureWindowList` / `SLSHWCaptureWindowListToIOSurfaceProxying` (WindowServer,
  then replayd). Already on `screenshotsQueue`; ~50–60 per summon.
- `UserDefaults` (cfprefsd). Reads go through `CachedUserDefaults`; there is no `synchronize()` in the tree.
- `LiquidGlass.canUsePrivateLook` — a `static let` that instantiates `NSGlassEffectView()`. First touched at
  launch through `TilesPanel.init` → `TilesView.initialize`, so the cost is pre-paid, not paid mid-gesture.
- `NSPasteboard` — the Debug window's copy button, and drag-type registration.
- `NSSpellChecker`, `NSCursor`, `NSToolTipManager`: not called on main outside the above.

## Finding the next one

`MainThreadStall.step()` at the top of a main-thread function reports that step by name when it runs past
`MainThreadStall.thresholdInMs`. Every number in the table above was measured with it, by temporarily
lowering the threshold to 1ms and adding marks around individual statements.
