# RealWorldScenarios — Specs

## Summary

A durable corpus of **real data recorded from a live machine** (macOS 26, 2026-07-06, #5830 investigation),
fed to the pure decision kernels (`TabGroupResolver`, `PhantomWindowDetector`, `WsEventRouting`). The messy
facts that break tab detection — duplicate `~` titles, identical tab geometry, Space-less background tabs,
the removed-from-Space event storm — are captured ONCE as `CapturedWindow` / raw-event fixtures, so heuristics
can keep changing while the ground truth stays fixed, and we never re-record from a live machine again.

`CapturedWindow` holds only RAW API output (AXTitle / AXSubrole / AXTabGroup titles / WindowServer bounds /
`CGSCopySpacesForWindows` / minimized / fullscreen). Nothing derived (`isTabbed`, grouping) is stored — each
test projects a capture onto the record its kernel needs (`TabWindow` / `WindowState`) and supplies the
algorithm state for the step under test. So a kernel refactor moves the projections, not the recordings.

## How to add a scenario

Record with a temporary `Logger.debug` at the AX/CGS read sites (e.g. `Applications.addDiscoveredWindow`
`extractTabTitles`, `TabGroup.updateState`, `WindowServerEvents.handle`), reproduce on a real machine, then
transcribe the raw values into a new `static let` capture with a provenance comment (app, macOS version,
date, gesture). Never hand-tune the numbers to make a test pass — if behavior changed, change the expectation.

## Corpus

- **`terminalMerge4Tabs`** — Terminal "Merge All Windows" over 4 windows. All `~`, 757×583 @ (683,101);
  active (29328) holds Space 3 + AXTabGroup `["~"×4]`, three background tabs Space-less, no AXTabGroup.
- **`terminalActive9Titles` / `terminal9TabsTracked`** — mid-creation of a 9-tab group: active reports 9 `~`,
  only 5 background siblings tracked yet (3 tabs not yet discovered).
- **`finderActive4Tabs`** — Finder 4-tab window, AXTabGroup `["QRHYWK4QHQ","lwouis","lwouis","lwouis"]`; only
  the active tab is a real window (Finder inactive tabs aren't separate windows).
- **`terminalSeparate4Windows`** — DEFAULT tabbing: 4 genuinely separate Terminal windows, same size/position,
  all hold a Space, none exposes an AXTabGroup. The "must never group" ground truth.
- **`removedFromSpaceStorm`** — the raw SkyLight (id, wid) burst when Terminal windows left a Space at once
  (807 resized / 816 orderedOut / 1326 removedFromSpace).
- **`terminalFullscreenActive` / `terminalFullscreenBackgroundTabs`** — a 3-tab group fullscreened: active on
  fullscreen Space 2 at 1440×864, background tabs frozen at 757×543 (Space-less), AXTabGroup unreadable (nil).
- **`dragOut*`** — "Move Tab to New Window": the leaving tab shrinks 757×543 → 757×527 (tab bar gone) and goes
  standalone; the 3 survivors stay 757×543. Pre-drag group `[30238, 30236, 30231, 30230]`.
- **`finderGitActive` / `finderLwouisInactiveTab` / `finderMoviesStandalone`** — the maintainer's recorded
  Finder case (see `experimentations/TabbedWindowDetection.swift`): tabs "lwouis"(inactive)/"git"(active) +
  a same-app standalone "Movies". Distinct titles, so a clean unambiguous match.
- **`tabbedWindowMovedBetweenSpaces`** — a tabbed window changing Space: 1326 (leave old) + 1325 (join new),
  each carrying (spaceId, wid). The events that fire reconcile so the group follows the move.
- **`missionControlAxCycle`** — MC begin/end from the Dock AX stream (`AXExposeShowAllWindows` / `AXExposeExit`).
  Reference only: MC has no pure-kernel consumer and moves no window between Spaces (it orders thumbnails in/out);
  the ids it fires (818, 1327, 1328) are intentionally not routed. `AXExposeExit` is the clean end-of-transition hook.

## Two coexisting groups of one app (`twoGroupsSameApp`)

Recorded LIVE: with `TABDBG` logging armed, the user hand-dragged tabs between two real TextEdit groups (and
closed one window mid-way). Both AXTabGroups were captured from the log: A = ["Untitled", "Untitled 2",
"Untitled 3"], B = ["Untitled 7", "Untitled 9"], plus 3 standalone windows. `testTwoCoexistingGroups_*` pin
the durable invariant a between-groups move must preserve: each group's `matchSiblings` resolves ONLY its own
tabs, never the other group's or the standalones. (Automating the atomic single-tab drag is impractical —
TextEdit Cmd-T = Show Fonts, a torn-off tab detaches into a new window unless dropped exactly on a tab bar,
and AltTab's off-screen windows block computer-use drop targets — so it was done by hand and read from the log.)
`textEditGroup6` is a separate real single-group capture (distinct titles, the clean-match contrast to `~`).

## Known gaps (capture when reproducible)

- Dragging a window (with tabs) to another Space's thumbnail in Mission Control. The resulting event pair is
  captured (real events) in `tabbedWindowMovedBetweenSpaces`; the live end-to-end drag is not.
- A tab switch INSIDE a fullscreen window — transient, hard to snapshot deterministically.
- A tab switch INSIDE a fullscreen window (which sibling holds the fullscreen Space swaps) — transient, hard to
  snapshot deterministically.

## Test scenarios

- **testMergedTabsGroupByGeometry** — merged group ⇒ `geometryGroups` groups the 3 Space-less tabs under the active.
- **testSeparateWindowsNeverGroup** — separate windows (incl. a flaky Space-less read) ⇒ no group (the gate holds).
- **testMergedTabsAllMatchByTitle** — 4 `~` titles all resolve to the tracked windows, nothing untracked.
- **testNineTabsLeaveThreeUntracked** — 9 `~`, 5 tracked ⇒ 5 matched, 3 untracked (→ discovery). "sometimes 9".
- **testFinderTabsAllUntracked** — only the active Finder tab tracked ⇒ all 3 other titles untracked.
- **testBackgroundTabPhantomFlipsWithTabDetection** — a Space-less tab is phantom until `isTabbed`, then exempt.
- **testRemovedFromSpaceStormRouting** — every 1326 in the storm routes to `.updateSpaceMembership` (the churn trigger).
- **testFullscreenTabsNotGroupedByGeometryAlone** — divergent sizes under fullscreen ⇒ geometry can't group; the
  `tabbedSiblingWids` link is what holds the group.
- **testFullscreenTabPositionCompatibleViaExistingLink** — an already-linked inactive tab stays compatible despite
  divergent fullscreen position/size.
- **testDragOutShrinksTheGroup** — active tab leaves 4-window group ⇒ shrink to the 3 survivors.
- **testDraggedOutWindowNotReAbsorbedByGeometry** — the escaped window (new size, holds a Space) isn't re-collapsed.
- **testFinderStandaloneWindowNotSweptIntoGroup** — "Movies" (same app, non-tabbed) stays out of the git/lwouis group.
- **testFinderInactiveTabIsPhantomUntilTabbed** — "lwouis" Space-less ⇒ phantom until `isTabbed`.
