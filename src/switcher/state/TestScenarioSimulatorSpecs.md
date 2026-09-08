# Test model + simulator — Specs

## Why this exists

For days we fixed tab/phantom detection by **recording a live failure, transcribing it, pinning it** — and
kept regressing the same *area* (fullscreen Finder tabs). That loop is **example-based and reactive**: each
recording is one point in a huge space of event interleavings, added only *after* a bug ships, and we never
wrote down what CORRECT behavior is. The model layer is the shift to **model + properties**.

## The pieces (all `Test`-prefixed = test-only, used together)

- **`TestUserAction`** — one thing the user does (`newWindow` / `openTab` / `switchTab` / `enterFullscreen`
  / `switchToSpace` / `show`). A **`TestScenario`** is a `[TestUserAction]`; a test IS that sequence.
- **`TestInteractionModel`** — THE model of OS behavior: `[TestUserAction ⇒ OS events]`. Holds GROUND TRUTH
  (real windows, their tabs, which is active, per-tab frame/Space/fullscreen) and, per action, emits the
  WindowServer/AX event sequence AltTab would observe as `TestReducerRunner.Step`s. Performs nothing itself,
  so the same action can be replayed under different event ORDERINGS. Four OS-behaviour switches, each
  observed live: `duplicateTitles` (Finder names every window after its folder), `reusesTabWindows` (a switch
  reuses the tab's own window, `added tracked#` — rec19 — instead of minting a fresh wid with no create
  event, `added untracked#` — rec24b), and the two that #5785 forced (see "Two facts the model was missing").
- **`TestReducerRunner`** — feeds `ReducerInput`s to `WindowEventReducer`, applies pure twins of model-side
  effects, and checks the per-frame invariants (one tile/group, no cross-frame group, focused shown, no
  on-Space claimed, spaceless-ungrouped hidden, rep follows focus) PLUS **convergence/idempotence** (a
  settled state must be a reconcile fixed point — catches the "never settles" churn no per-frame check sees).
- **`TestScenarioSimulator`** — the driver: runs a `TestScenario` through model + runner and checks the
  GROUND-TRUTH property no raw-state test can — **N real windows ⇒ N tiles**, each shown by its own active
  tab, no group spanning two windows. `fuzzFailure` re-runs the scenario under every `Ordering` (the
  interleaving fuzz). It also checks, after every read UNIT, that **a tile never vanishes or doubles**:
  these bugs are TRANSIENTS (the tile came back ~800ms later), so the settled end state looks perfect and
  only a per-unit check sees them. That one is deliberately weaker than the end-of-run property — mid-switch
  the HELD outgoing tab is legitimately the tile — so it demands one tile, not the active one.

## The four testing layers

1. **Kernel tests** (`TabGroupResolverTests`) — one decision, exact output, hand-built states; race-unroll;
   `frameCorpus` sweeps.
2. **Recordings** (`RealWorldScenariosTests` corpus + `ReplayScenariosTests` replays) — real captured facts.
   The replays have been MIGRATED into `TestScenario`s and deleted as covered (R4); one remains, see below.
   The kernel corpus STAYS — see "Why the kernel corpus is not migrated".
3. **Runner invariants** (`TestReducerRunner`) — per-frame + convergence, checked after every step.
4. **The model + simulator** (this file) — `TestScenario`s (CORE detection: steady states) fuzzed over
   **event interleavings** (EDGE cases: races) — reproduces bugs WITHOUT a live capture.

Pin rule: a wrong RULE → kernel test; a correctness property (count / no-hidden / convergence) → a
`TestScenario`.

## Faithfulness — the four facts settled by live capture (rec26, 2026-07-18)

The model had INFERRED these from old recordings. A ten-minute scripted session settled them, and three of
the four were wrong or unverified. This is why the layer is worth the trouble: the errors were invisible
until measured, and each had been quietly deciding test outcomes.

| assumed | measured | consequence |
| --- | --- | --- |
| a tab switch MINTS a fresh wid | **REUSE** — every one of eight windowed and fullscreen switches announced `added tracked#<wid> isTabbed=true` | `reusesTabWindows` now defaults TRUE; minting is the rare case (the tab's window is gone) |
| `Windows.list` is creation order | **MRU** — `Windows.sort()` re-sorts before every show; after a switch the new rep is at index 0, ahead of its own tabs | `.sortByMru` step; this is what finally made rec24 reproducible |
| unsure what CGS returns for a backgrounded tab | **empty, always** — every probe in the capture was `#<wid>→[]` | the model was right; the reducer comment claiming it "still reports its OLD Space" is wrong for this case |
| background tabs stay frozen after fullscreen | **confirmed** — background tabs at 920x436 while the active is 1440x900, and a tab backgrounded WHILE fullscreen freezes at 1440x900 | per-tab frames and the whole-group frame exemption are both justified |

Two of the four migrations silently LOST their teeth when the model was corrected, and had to be repaired
before they could be trusted again: with reuse, no tab is ever left untracked, so rec24e's adoption never
fired (it now opts into `reusesTabWindows: false`); and MRU ordering put the windowed group's own tabs ahead
of the fullscreen window, so rec24c's claim never reached it — until `switchToSpace` was also taught to FOCUS
the window it moves to, which is what fronts it in the list, reproducing the recording's `matched=[78459, …]`.

**Re-run the teeth checks after any model change.** A scenario can pass for a reason that has quietly stopped
being the reason.

## Faithfulness (grounded in the recordings)

A tabbed window shows ONE tile; its active tab holds the window's Space, background tabs are Space-less;
switching tabs either MINTS a fresh wid for the incoming tab — its prior wid LINGERS alive + AX-reachable
(rec25 accumulation — stale wids are NOT dead, they stay tracked and reconcile folds them) — or REUSES the
tab's own window (`reusesTabWindows`); a fullscreen window's tabs share ONE fullscreen Space, and only its
ACTIVE tab is resized, the rest staying frozen at their old frames; an inactive tab AltTab never tracked is
brute-force adopted Space-less; a `show` runs the pre-show reconcile (discover the untracked incoming active,
adopt inactive tabs, AX-title read for windowed groups, authoritative Space re-query, phantom pass), and all
of its reads are ISSUED before any of them land. When a fuzz failure looks like a bug, first rule out a model
**faithfulness** gap — and when a teeth check does NOT bite, suspect one too.

## The interleaving fuzz

THREE axes, run as a cross product — one written scenario → twelve interleavings. **Bounded on purpose** (a
fixed, named set, so failures reproduce). The generator sweep was halved to 0..<150 to pay for the third:
the same budget buys more seeds or more orderings, and orderings win — every bug it has found lived in a
race, not in an exotic action sequence.

`TestScenarioSimulator.Ordering` varies how a `show`'s async read UNITS land: `.inOrder` (baseline),
`.reversed`, `.settleFirst` (the Space re-query + phantom pass land BEFORE the discovery/title reads).

`TestScenarioSimulator.HandoverOrder` varies which half of a Space HANDOVER arrives first. A tab switch is
one window leaving a Space (1326) and another joining it (1325); those are two separate WindowServer
datagrams, delivered on whichever thread snarfs each one and then hopped to main
(`WindowServerEvents.notifyProc`), so nothing pins their relative order. The live captures show both orders
across operations — a fullscreen tab switch arrived JOIN-first with the outgoing tab's 1326 lagging
(`fullscreenTabSwitchEvents`), a Space move LEAVE-first (`spaceMovementEvents`). The model emits one
canonical order per action; the axis replays the other. **Currently all-green**: the app already tolerates
either order, so this is cheap insurance rather than a bug found.

`TestScenarioSimulator.LateRead` holds an action's TITLES read back and lands it at the END of the next
action — the rec18 class, where a read applies against a model the user has already moved on from. See the
"Holes" entry it closed. It exists because any move toward treating
the handover PAIR as first-class evidence (rather than inferring tabs from geometry) rests entirely on that
pairing, and a corpus that only ever delivers it one way round would go green on a detector the OS breaks.

Two things it deliberately does NOT permute, both learned the expensive way:

- **The same wid leaving one Space and joining another** is a window MOVING (entering fullscreen), not a
  handover. The first version of the axis reversed every membership step indiscriminately and "found" 10
  failures in 22 scenarios, every one a fullscreen transition made transiently Space-less by the axis itself.
  Rule out the harness first, as with the model. A handover is now defined narrowly: **two different wids,
  opposite directions, the same Space.**
- **The create→leave order of a new tab**, which IS guaranteed (the new tab is what backgrounds the old, so
  its 811 precedes the old tab's 1326 — `RealWorldScenariosTests`). Permuting a guaranteed order manufactures
  races the OS never delivers, and each one costs a triage.

### Slow OS work straddles the next action (`ActionEvents.deferred`)

Most reads land in ~ms, so they belong to their own action. A **Space transition** does not: it settles over
~500ms, long enough that whatever the user does next happens INSIDE it. `deferred` units model exactly that
— they land at the END of the following action, deliberately OUTSIDE the ordering, because they ARE the
transition settling and landing them earlier would model a transition that ended before it ended. So every
read of the straddled action lands in the gap: summon the switcher mid-Space-switch and all its reads see
the transitioning window as Space-less, which is the rec24c situation. Bounded to ONE action deep on
purpose — a blunt "defer everything to the next show" is unfaithful and produces false failures (verified).

While a transition is in flight the model also OMITS the window from the authoritative Space re-query and
the phantom pass's visible set. CGS does not list a transitioning window on its Space — that is WHY it reads
as Space-less — and without the omission the re-query heals the transient the scenario exists to expose.

### Two other faithfulness facts the model needs

- **A beat between actions.** Events within an action are ms apart; separate user actions are SECONDS apart,
  and the reducer's recency windows (`hadRecentWindowCreate`, 0.5s) key off that difference. Without the gap
  every scenario ran inside one creation window, leaving holds armed that real usage would have released —
  and a held window is exempt from claims, which silently hid the very races being tested.
- **Duplicate titles** (`TestInteractionModel(duplicateTitles:)`). Finder names each window after the folder
  it shows, so title collisions are the norm — and a title is what `matchSiblings` claims a tab BY, so
  collisions are where a group steals a window (rec8/10/11/24c).

### Two facts the model was missing (#5785, 2026-07-27)

The switcher showed two tiles for one Terminal window every time a user opened its FIRST tab, while 789 tests
stayed green. The model could not express the situation at all, so no sweep could ever have found it. Both
facts are now axes, off by default because they change the geometry and titles every existing scenario
asserts on:

- **`tabBarResizesWindow`.** The tab bar appears with the SECOND tab and GROWS the window. The incoming tab
  is drawn at the grown frame; the outgoing one keeps its own, because a background tab gets no geometry
  event to correct it. So the two tabs of one window report DIFFERENT sizes for as long as the pair lives,
  and every clustering rule keys on size. Measured via `SLSWindowQueryWindows`: one Terminal window at
  757x547, then New Tab → active 757x583, background 757x543. The reporter's capture is the same shape,
  1017x610 against 1017x565. Before this, every window and tab in the model shared ONE size — which no real
  tabbed window ever has.
- **`composedWindowTitles`.** The app composes its WINDOW title from more than its TAB title, so the two
  never match. Note this is NOT `duplicateTitles`, which makes every title the SAME string — those still
  MATCH, and the title path still works. Nothing here could express titles that match NOTHING, which is the
  actual #5785 condition.

Either fact alone is survivable; together they are the bug (`testFirstTabInAStandaloneWindowIsOneTileDespiteTheTabBarResize`,
three actions). The same investigation also found the model was omitting the Space JOIN that tab creation
emits — real logs show create → JOIN(new tab) → LEAVE(old tab) — and that join is the half of the handover
that names the successor, so without it no scenario could exercise the handover pairing at all.

## Bugs the model found + we fixed (pinned as `TestScenario`s, fuzzed over all orderings)

1. **Superseded-incoming-tab promotion** (`newWindow → openTab → switchTab → openTab → show`): switching to
   a tab armed its focus promotion; opening another tab superseded it before discovery, and the stale
   promotion made it the group rep over the real active. Fix: drain `pendingFocusPromotion` when an
   untracked wid backgrounds (`WindowEventReducer`).
2. **Two fullscreen windows of one app merged on transition**: the second, transiently two-Spaced, fed the
   single-Space fullscreen fold. Fix: the fold only folds Space-less members or members settled on the
   cluster's single settled Space (`TabGroupResolver.resolveGroup`).
3. **A window split across two groups, so it showed two tiles** (seeds 106/125, and a third repro found once
   the shrinker was fixed): the membership a minted wid carries was dropped whenever it stopped being the
   active before discovery reached it. Fix: hand it to the successor, or keep it when nothing superseded it —
   see "The last two seeds" below.

## Fullscreen tab reading: investigated, and deliberately NOT used

A long probe established that a fullscreen window's tab
bar IS reachable — unevenly. Finder and Script Editor list the containing AXGroup as a child of the window;
Terminal and TextEdit do not, and theirs lives in a separate `NSToolbarFullScreenWindow` that no downward
walk reaches (only a coordinate hit-test, via `SLSCopyAssociatedWindows` for the exact bounds).

**We chose not to use any of it.** A fullscreen Space holds one window and its tabs, so the Space invariant
plus Space-less-ness already identifies them, and reading tabs for SOME apps only bought an asymmetry with a
real cost: a fullscreen active that can suddenly read its tabs reaches `matchSiblings`, where nothing stopped
it claiming a windowed window's tab (generator seed 48 — a real window hidden). Fullscreen grouping is
geometry's job, uniformly, and the model says so (`TestInteractionModel.tabsReadable`).

The accepted gap is that a fullscreen window's background tabs are not LISTED until the user visits them
once. Visiting one makes it join the fullscreen Space (an event we do see), so it is discovered and resized
to the fullscreen frame, and folds into the cluster permanently. It shows only in "separate window for each
tab"; the default grouped mode is correct throughout. Pinned by
`testPreexistingUnswitchedFullscreenTabsStillShowOneTile`.

## Cold start — AltTab launched into a desktop that already existed

Every scenario above starts from nothing and watches every window from birth. That is the one condition
under which a history-based detector cannot fail, because history covers everything — and it is not the
condition AltTab launches in. `TestScenarioSimulator(preexisting:)` seeds a world and emits **no event for
it**: the first `show` is the launch discovery, and the only facts available are the ones readable NOW (the
AXTabGroup, the frames). This is the initial condition, and it is what separates the two sources tab
detection can draw on: events are a *derivative* (they report CHANGES in Space occupancy), and a derivative
cannot be integrated without one.

**These scenarios assert `requireCompleteGroups`, and that is the point of them.** The tile-count property
is BLIND here: an un-grouped background tab is Space-less ⇒ phantom ⇒ hidden, so a window whose tabs were
never linked at all still shows exactly one tile and passes. Only asking whether the GROUP formed
distinguishes "tab detection worked" from "the tabs happened to be invisible" — and "Group tabs: separate
window for each tab" renders that difference to the user.

Three faithfulness rules the cold-start work established, two of them corrections to what was already here:

1. **Adoption of an inactive tab is causally DOWNSTREAM of its active's discovery.**
   `Applications.discoverInactiveTabs` is driven by `untrackedTitles`, which comes from `matchSiblings`,
   which needs the active tracked and its AXTabGroup read. The model used to emit both in one show and let
   the ordering land the adoption FIRST — an interleaving the app cannot produce. At cold start (where every
   active is untracked) that unreachable order made a background tab the group's representative and hid the
   genuine active, in 5 of the 6 first cold-start scenarios. `show()` now gates adoption on the active
   having been tracked when the show began, so a pre-existing group converges over TWO shows. Every earlier
   scenario is unaffected: their actives were tracked by an earlier action. **Rule out the model first** —
   this is the sixth instance.
2. **"Vanish" means a tile that was THERE and went.** `checkNothingVanished` treated any tracked wid as
   "must show a tile", which is false during launch discovery: landing a background tab's read first leaves
   the window tracked-but-not-yet-showable for a beat, and blaming the app for a tile it had not had the
   chance to draw is a false failure. Now gated on the window having shown a tile at least once. The
   DOUBLING half stays ungated — two tiles is a defect whenever it happens.
3. **A background tab freezes at the frame it last had while active**, so what a pre-existing fullscreen
   window's tabs wear depends on what the user did after fullscreening (`tabsFrozenAtWindowedFrame`).
   Switched tabs since ⇒ the fullscreen frame, and geometry clusters them fine. Never switched since ⇒ still
   the windowed frame, and then nothing reaches them at all — see the hole below.

## Recordings retired into this layer (R4, 2026-07-18)

A replay fixture may be deleted ONLY once the model provably reproduces its bug — proof is a TEETH CHECK:
revert that recording's fix, confirm the new `TestScenario` FAILS, restore, confirm green. Deleting one the
model can't reproduce silently drops real coverage (verified at the outset: disabling rec24's fix left every
scenario green, so the recordings were pinning something the model did not yet reach).

| retired | `TestScenario` | fix the teeth check reverted |
| --- | --- | --- |
| rec24c | `testWindowedGroupNeverAnnexesAFullscreenWindowDuringASpaceSwitch` | `matchSiblings`' `!s.isFullscreen` |
| rec24e | `testAdoptedInactiveTabDoesNotWipeTheFullscreenActivesSpace` | `newlyDiscovered: adoptedAsInactiveTab ? nil : wid` |
| rec21 | `testFullscreenMirroredTabsAreNeverClaimedAcrossFrames` | the mirror mask in `tabWindow` |
| rec19 | `testReusedTabSwitchIsOneAtomicRepresentativeSwap` | the atomic `setGroupRepresentative` on a Space-join |
| rec24 | `testMintedTabSwitchDoesNotDropTheTileWhileDiscoveryIsInFlight` | `hadRecentUntrackedSpaceJoin` |

**`ReplayScenariosTests` is gone — zero replay fixtures remain.** rec24 was the last, and it was retired only
after a live capture (rec26) overturned the assumption that had blocked it: `Windows.list` is NOT creation
order. It is re-sorted by MRU before every show, so the outgoing representative sits AHEAD of its own
background tabs — and that is exactly what the vanish needs, since `applyWindowSpaces` backfills a Space-less
window from its active sibling (a member walked before the rep would find a live Space and rescue the group).

### What each retirement cost (all of it faithfulness work, not test-writing)

Every one of these needed a MODEL fix first, and each fix had been quietly masking races in every scenario:

- **The clock.** It advanced 10ms per event, so whole scenarios sat inside one 0.5s `hadRecentWindowCreate`
  window; holds stayed armed, and a held window is exempt from claims. Now +1s between actions.
- **Hold release.** The app schedules a `holdReleaseCheck` once the replacement lands; the model never fired
  it, so every hold stayed armed forever — and a held tab keeps a borrowed Space, which made the
  authoritative Space re-query unable to wipe anything at all.
- **Per-tab frames.** Fullscreen resizes only the ACTIVE tab. One shared frame per window made a fullscreen
  group span two frames the moment a tab backgrounded after the transition.
- **Reads are issued before they land.** `show()` marked the incoming active tracked while BUILDING its
  events, so the Space re-query named a wid the same show was still discovering. Tracked-ness is now
  snapshotted when the reads are issued.
- **The empty map.** A re-query returning nothing is unreachable in the app (#5791 backfills any tracked wid
  the enumeration missed, and that query still reports a backgrounded tab's OLD Space), so the model no
  longer emits one.

Each surfaced because a teeth check came back GREEN. **A teeth check that doesn't bite is a finding.**

## The generator (`TestScenarioGenerator`)

Random-but-valid scenarios from a seeded LCG, plus a delta-debug shrinker. Determinism is the point: seed N
always yields the same scenario, so `testGeneratedScenariosStayCorrect` is an ordinary regression test, and a
failure prints a repro already shrunk to four or five readable actions. The OS-behaviour flags
(`duplicateTitles`, `reusesTabWindows`) are part of the generated input, because they decide which races are
reachable at all.

**Triage discipline — most findings are the MODEL's fault, and that is fine.** Of the first four:

1. `switchToSpace` onto the Space you are already on emitted a whole transition (model bug — fixed).
2. The deferred Space settle re-added the wid captured when the transition STARTED, so a tab opened
   mid-transition left the group showing the previous tab (model bug — fixed; the settle steps are now built
   when they fire).
3. A tab backgrounding inside one fullscreen window was adopted by ANOTHER fullscreen window (REAL app bug —
   FIXED by `lastLeftSpaceId`; the repro is now a live regression guard,
   `testFullscreenTabBackgroundingIsNotStolenByAnotherFullscreenWindow`).
4. Convergence was demanded BETWEEN the two halves of a Space swap, where two members legitimately hold the
   same Space for a millisecond (harness bug — fixed; the 1326 that completes the swap is still checked).

**`lastLeftSpaceId` — the history fact the generator forced into existence.** Its first real find could not
be decided from current facts at all: a tab that just backgrounded inside fullscreen window A is, by every
fact the kernel had, identical to a brand-new tab of fullscreen window B (Space-less, same app, same
screen-size, unlinked) — so geometry handed one window's tab to the other. Tightening the fullscreen
confirmation clause to require `newlyDiscovered` was tried and REVERTED (13 corpus tests require a fullscreen
visible to group without it). What separates the two cases is HISTORY: the 1326 names the Space the window
left. That is now carried on `TrackedWindow`/`TabWindow` as `lastLeftSpaceId` (set on a leave, cleared on a
join) and read by `settledOnAnotherWindowsSpace`. Unlike `isHeld`/`spaceIsBorrowed` it is genuine CGS
evidence, so the kernel projection forwards it rather than masking it. Pinned by
`testFullscreenTabBackgroundingIsNotStolenByAnotherFullscreenWindow`.

**The backlog: `TestScenarioGenerator.knownFailingSeeds`** — started at 12 of the first 40 seeds, and is now
EMPTY (see the note further down); 0..<600 was swept clean when it emptied, and the committed sweep runs
0..<150. Recompute it after ANY edit to `scenario(seed:)`: the list names scenarios, not bugs, and changing
generation reshuffles which seed produces what. While it was non-empty every survivor was fullscreen tab
churn, and each shrank to a DIFFERENT minimal repro after each fix — the area has layers, and each round
peels one.

**A fix whose scenario still fails needs its own pin.** Three fixes landed with NO teeth because the seeds
they fixed remain in the skip-list, so nothing exercised them: the sweep skips those scenarios wholesale. They
are now pinned at runner level (`testRepresentativeDoesNotBorrowASpaceItJustLeft`,
`testMintedTabPairingIgnoresARepresentativeLeavingAnotherSpace`,
`testTitleReadThatChangesMembershipLeavesAFixedPoint`). Check for this whenever a fix is motivated by a seed
that is still failing for other reasons.


**Most generator findings are the MODEL's fault, and each fix makes every scenario sharper.** Of the eight
triaged so far, five were model or harness artefacts and three were real app bugs. The model ones are worth
listing, because they were all the same mistake — asserting something the OS never does:

| model bug | what it wrongly claimed |
| --- | --- |
| `switchToSpace` onto the Space you are already on | a whole Space transition |
| the deferred settle used the wid captured at transition START | that the tab active when it FINISHED was elsewhere |
| convergence demanded between the two halves of a Space swap | that an atomic pair was churn |
| generating actions on a window on a NON-VISIBLE Space | that you can click a tab you cannot see |
| `newWindow` leaving you on a fullscreen Space | that a new window opens without taking you to it |
| `switchToSpace` to a WINDOWED target emitting the Space-less transient | that a still window had left its Space |

The last three each produced failures that looked exactly like app bugs — a window hidden, a focus signal
suppressed — and in every case the app was doing the right thing with a lie. **Rule out the model first.**

## The icon flash — a defect no other check could see

`TileView` draws the app icon exactly when `thumbnail == nil`, so a tile handed to a wid whose capture hasn't
landed FLASHES: screenshot → app icon → screenshot. The tile never disappears, every count stays right, and
convergence holds — so nothing in this suite noticed. The model now tracks thumbnails (a new window arrives
with none; captures land as their own read unit) and `checkNoIconFlash` asserts a window never shows a wid
with no pixels while a sibling still has some. It caught the live report on the first generator sweep.

## The two arms of `pendingGroupInheritance` are NOT redundant (measured 2026-07-27)

Group inheritance for a minted tab switch is armed from two places, and they read as duplicates: the hold
branch of `spaceMembershipChanged` pairs a leave with an untracked join BY TIME, while `discoveryLanded`
arms the same thing from the handover EDGE, which names a wid, is recorded from either arrival order, and
confirms the pid at consumption. Strictly better evidence, so the older one looks like accretion.

It isn't. They partition by regime, and the generator says so in both directions:

- Drop the WINDOWED-only gate on the edge arm (so it also covers fullscreen): **seed 31 breaks** under
  ordering `.inOrder` / handover `.swapped` / lateRead `.prompt`. In fullscreen, forming a partial group from
  the edge pre-empts the per-Space geometry fold that owns fullscreen grouping (this is seed 77's shape).
- Delete the hold-branch arm entirely: **`testMintedTabSwitchInheritsTheGroupItTookOver`,
  `testSupersededMintedTabHandsItsGroupToTheWidThatSupersededIt` and
  `testSupersededMintedTabDoesNotStrandALiveBackgroundTabInAnOrphanGroup` all fail**, plus the generator
  sweep — and every failing scenario contains `enterFullscreen`.

So: fullscreen is the hold branch's, windowed is the edge's, and the fullscreen gate on the edge arm is the
line between them. Anyone reaching for the obvious simplification should re-run those two experiments first.

## The last two seeds (106/125) — the split generation, FIXED

Both reduced to: a MINTED tab switch, then fullscreen, then more tab activity. The window ended up split
across TWO groups — the pre-fullscreen wids and the post-fullscreen ones — and the orphan group's
representative stood as a second tile. It is HELD, which exempts it from the phantom rule, so live only the
20s safety cap ended it.

The hold looked like the culprit and is not. **Releasing it was tried twice and reverted twice** (a vanish at
seed 140; a wholly phantom window), and neither could work: while the generation is split off as its own
group, nothing tells "a redundant orphan" from "this window's only group". The defect is one step upstream —
`pendingGroupInheritance`, the membership a minted wid carries until its discovery, was DROPPED whenever that
wid stopped being the active before discovery reached it. The generation it was carrying then had no way back
into the group.

The fix is in `WindowEventReducer.spaceMembershipChanged`'s untracked-drain, and it has two halves:

- **Superseded** (another brand-new wid just took over — a minted Space-join, or a WS create): hand the
  membership ON to that successor, with the superseded wid riding along so it is folded in too. The pairing is
  by TIME, so it is confirmed by pid at consumption, where the pid is finally known (the seed-30 cross-wire).
- **Not superseded** (no such signal): the membership simply STAYS. The commonest way to get here is a Space
  TRANSITION — the active tab drops its Space for the length of the animation and rejoins when it settles, and
  the app cannot know a transition has begun.

Keeping the generation in ONE group is what makes the stale wids derive `isTabbed` and hide by themselves, so
no phantom-rule exception is needed at all — the rec25 accumulation stops being a display problem without
having to decide when a minted-away wid stops being a window. Pinned as
`testSupersededMintedTabHandsItsGroupToTheWidThatSupersededIt`,
`testSupersededMintedTabDoesNotStrandALiveBackgroundTabInAnOrphanGroup` and
`testActiveTabKeepsItsPendingGroupAcrossASpaceTransition`. `knownFailingSeeds` is now EMPTY.

### The shrinker was minting scenarios no user can perform

Seed 106 resisted twice because its shrunk repro switched a tab in a window sitting on a Space the viewport
had left — the documented seeds-11/15 class. `scenario(seed:)` inserts a `switchToSpace` before reaching such
a window; the shrinker dropped actions blindly and removed those hops, so it produced a failure the app is not
responsible for and pointed the fix at the wrong rule. `shrink` now rejects any candidate failing
`isReachable`. **A repro is only evidence if a user could have performed it.**

## Holes in coverage

- **A pre-existing FULLSCREEN window's unswitched tabs are grouped by nothing** — KNOWN AND ACCEPTED. It
  self-heals on first visit and is invisible in the default mode; only "separate window for each tab" shows
  it, as tabs missing until visited once.

  The fix this file used to propose is DEAD, and worth recording so nobody spends a day on it: "the AXTabGroup
  COUNT is readable for a fullscreen window even when the titles are not" is false. `tabCount` is written only
  from `tabGroupInfo`, which reads DIRECT children, and a cold-start fullscreen window has never had a
  windowed read, so its count is 0 for every app. That premise was the same lore the fullscreen probe later
  corrected: a fullscreen tab bar IS reachable, but only
  by hit-testing the separate `NSToolbarFullScreenWindow` that hosts it, and the cheap alternative (descend
  one level into AXGroup children) was tried and reverted — it works for Finder and Script Editor, not for
  Terminal or TextEdit, and that app-dependent asymmetry lets a fullscreen active reach `matchSiblings`,
  where nothing stops it claiming a windowed window's tab.

  So closing this means implementing the hit-test chain (`SLSCopyAssociatedWindows` → the toolbar wid → its
  bounds → several hit-tests → walk up to an AXWindow → require the wid to be ours). Its costs are written
  down where it was probed: the window must be on screen, and it spends one CGS call plus up to a dozen AX
  hit-tests per fullscreen window per read. That is the trade to weigh, not a count that can simply be read.
- **A new tab's own 1325 is not modelled.** `openTab` emits the create and the OLD tab's leave, matching what
  the recording guarantees (`RealWorldScenariosTests`: create → removedFromSpace(old)), and the incoming
  tab's Space arrives via its discovery's `queriedSpaceIds` instead. So opening a tab is the one handover the
  `HandoverOrder` axis cannot fuzz — there is only one membership event in it. Closing this needs a capture
  of a real ⌘T, not a guess.
- **Storms are routing-only.** `removedFromSpaceStorm` is asserted against `WsEventRouting.action(for:)` and
  never driven through the reducer, so a Space switch or Mission Control burst — many adds and leaves on one
  Space at once, where handover pairing is ambiguous by construction — is untested end to end.
- **Cross-action async interleaving (stale reads landing late — rec18/rec24)** — NOW CLOSED, in the bounded
  form this entry prescribed: `LateRead.titlesOneActionLate` holds each action's TITLES read back and lands
  it at the end of the next action. Bounded to the titles read because that is the one genuinely queued
  behind `AXCallScheduler` and the one rec18 caught landing ~800ms late; the blunt defer-all had been tried
  and reverted (7/8 scenarios failed falsely). **All-green**, which is itself a result worth writing down:
  the open lead it was built for — an occasional tile vanish-then-reappear after switching a tab in a
  NON-fullscreen window — is NOT reproduced by it. Either the shape is different, or the model still cannot
  express it. Do not close that lead on the strength of this axis being green.
- Gestures not modeled: drag-tab-out, window close + 804-lag timing, Space-move via Mission Control,
  multi-monitor, hidden apps. (minimize/unminimize and leaving fullscreen are modelled.)
- **A tab frozen at the fullscreen frame after its window leaves fullscreen.** `exitFullscreen` restores the
  ACTIVE tab's frame; a background tab gets no geometry event, so it keeps the fullscreen size — which is
  screen-sized, i.e. the size cluster of every fullscreen window on the machine. The frame invariant
  (`checkNoGroupSpansDistinctFrames`) exempts a group with a genuinely-fullscreen MEMBER, not one whose
  member is merely frozen at that frame, so a tabbed window's exit trips it. Seen by adding the action to the
  generator's pool (which reshuffles every seed, so that change is not committed): shrunk to
  `[newWindow, openTab, switchTab, enterFullscreen, switchTab, exitFullscreen, show]`. Unread: it is either
  that exemption gap or a real staleness, and it is NOT the reporter's shape (Chrome, no tabs).
- Non-Finder tabbing (Terminal/Safari mint wids differently).
- Non-Finder tab lifecycles beyond the two modelled switch behaviours (Safari/Terminal differ again).

## Why the kernel corpus is not migrated

`RealWorldScenariosTests` (the `CapturedWindow` corpus) is NOT a migration target, and deleting it would
drop real coverage. Those are KERNEL tests: one decision, exact expected output, race unrolling, `frameCorpus`
property sweeps. The model checks COARSE properties (tile counts, no vanish, convergence) over whole event
sequences — strictly weaker per decision. The user-ratified pin-level rule says a wrong RULE is pinned at
kernel level and kernel pins are never migrated up to a coarser layer; "zero recordings" means zero REPLAY
fixtures, not the loss of the rule-level pins the captures feed.

## Test scenarios

Mirrors `TestScenarioSimulatorTests.swift` 1:1. Every scenario is a list of USER ACTIONS, and each is fuzzed
over the interleaving axes (ordering / handover order / late read), so one entry is many replays.

### A. Core detection (steady states)
- **testStandaloneWindowsEachShowOneTile** — separate windows stay separate.
- **testWindowedTabbedWindowShowsOneTile** — a windowed tab group is one tile.
- **testFullscreenTabbedWindowShowsOneTile** — and so is a fullscreen one, where AX names nothing.

### B. The churn class (many switches — rec24f)
- **testManyWindowedTabSwitchesStayOneTile** / **testManyFullscreenTabSwitchesStayOneTile** — repeated
  switching must not accumulate tiles or fail to settle; the per-step convergence check is what sees it.
- **testFullscreenTabbedWindowCoexistsWithWindowedWindows** — the fullscreen group and ordinary windows of
  the same app do not bleed into each other.

### B2. Leaving fullscreen (`exitFullscreen`)

The inverse of `enterFullscreen`, and NOT its events played backwards. Measured live (2026-09-08, macOS 26,
Chrome, twice in one session): the window is raised, drops its fullscreen Space, has its windowed frame back
within 50ms, is ordered OUT for the animation, and rejoins the windowed Space ~516ms later — so it spends
half a second Space-less, ordered out, and wearing the size cluster of every other window of its app, while
the WindowServer snapshot that clears `isFullscreen` is still a read in flight. Modelled with the rejoin as a
`settlingWindow` straddle, exactly like `switchToSpace`, because that gap is the point.

- **testLeavingFullscreenKeepsBothWindowsOfTheApp** — two same-sized windows, one goes fullscreen and comes
  back: two tiles throughout. The reporter's shape.
- **testLeavingFullscreenNextToATabbedWindowKeepsBothTiles** — the same exit next to a window that really has
  tabs, so the fold has an established group to swallow the returning window into.
- **testRepeatedFullscreenRoundTripsKeepBothWindows** — four round trips: a fold that only survives one of
  them still hides the window for good, since nothing re-splits an established group.

### C. Real bugs the model found and we fixed (each pinned, each fuzzed)
- **testSupersededIncomingTabDoesNotBecomeRepresentative** — switching TO a tab arms its focus promotion;
  opening another tab supersedes it before discovery, and the stale promotion made it representative over
  the real active. Fixed by draining `pendingFocusPromotion` when an untracked wid backgrounds.
- **testTwoSeparateFullscreenWindowsDoNotMergeDuringTransition** — a second window entering fullscreen is
  transiently two-Spaced, which fed the single-Space fold and merged two real windows.
- **testWindowedGroupNeverAnnexesAFullscreenWindowDuringASpaceSwitch** — rec24c: switching Spaces TO a
  fullscreen window makes it transiently Space-less, so with duplicate titles a windowed group's read claimed
  the fullscreen WINDOW and the membership union bridged everything into a mega-group.
- **testAdoptedInactiveTabDoesNotWipeTheFullscreenActivesSpace** — rec24e: an adopted inactive tab announced
  as `newlyDiscovered` was elected visible and backfilled its empty Space over the whole group.
- **testMintedTabSwitchDoesNotDropTheTileWhileDiscoveryIsInFlight** — rec24: Finder mints a fresh wid with no
  create event, and in the gap before discovery the group is invisible to the show's Spaces re-query.
- **testFullscreenMirroredTabsAreNeverClaimedAcrossFrames** — rec21: fullscreening resizes only the active
  tab, so the mirrored flag on frozen tabs must never reach the kernel as genuine fullscreen.
- **testReusedTabSwitchIsOneAtomicRepresentativeSwap** — rec19: a reused-wid switch is a representative move,
  nothing more; treating it as "left its group" dissolved and re-formed the group ~800ms later.
- **testSecondFullscreenWindowNeverSwallowsTheFirstsGroup** — rec26 (14 members across two real windows): the
  newcomer is UNSETTLED, so it contributes no Space, and an unsettled visible may fold nothing.

### D. Cold start (AltTab launched into a desktop that already existed)

Every other scenario watches each window from birth, which is the one condition under which a history-based
detector cannot fail — and it is not the condition AltTab launches in. These seed a world with `preexisting`.

- **testPreexistingStandaloneWindowsEachShowOneTile** — the baseline with no history at all.
- **testPreexistingTabbedWindowIsGroupedAtLaunch** — a pre-existing group is found by the launch-time read.
- **testPreexistingTabbedWindowWithDuplicateTitlesIsGroupedAtLaunch** — Finder names every tab after its
  folder, so the titles collide and the read must claim anyway.
- **testPreexistingSameAppTabbedWindowsStayApartAtLaunch** — two tabbed windows of one app, all tabs sharing
  a title: they differ only by frame (macOS cascades), which is the fact a cold start still has.
- **testPreexistingFullscreenTabbedWindowIsGroupedAtLaunch** — fullscreen at launch exposes no readable
  AXTabGroup, so geometry is all that is left; it suffices while the background tabs wear the fullscreen
  frame.
- **testPreexistingUnswitchedFullscreenTabsStillShowOneTile** — KNOWN GAP, GREEN on purpose (it asserts the
  tile count, which is right, not complete groups, which is not): the
  same window never switched since fullscreening, so its tabs are frozen at the windowed frame and NEITHER
  source reaches them.
- **testFirstTabInAStandaloneWindowIsOneTileDespiteTheTabBarResize** — #5785's residual: the tab bar grows
  the window, so incoming and outgoing disagree on height while sharing app, position and width.
- **testFirstTabIsOneTileWhenTitlesStillMatch** — the same shape with matching titles, isolating which of the
  two facts the fix must handle.

### E. The generator (random scenarios, shrunk to a minimal repro)
- **testGeneratedScenariosStayCorrect** — a FIXED seed range, so it is a deterministic regression test rather
  than a flaky explorer. It covers the races nobody thought to write down.
- **testFullscreenTabBackgroundingIsNotStolenByAnotherFullscreenWindow** — FIXED, now a live regression
  guard: every fullscreen window is screen-sized, so a tab merely backgrounding inside one could be handed to
  another until `lastLeftSpaceId` gave the kernel the history to refuse it.
- **testNewFullscreenTabInheritsTheTileFromTheTabItReplaced** — the app-ICON flash: a multi-Space fullscreen
  cluster used to DROP its Space-less members, so the incoming tile inherited no thumbnail.
- **testMintedTabSwitchInheritsTheGroupItTookOver** — seed 7: nothing links a minted wid to the tabs it
  joins, since fullscreen exposes no AXTabGroup and the frozen siblings aren't in its size cluster.
- **testReusedTabSwitchInheritsTheOutgoingTabsPixels** — seed 142: the atomic swap made the reused wid
  representative but handed it no pixels, so the tile flashed the icon.
- **testSupersededMintedTabHandsItsGroupToTheWidThatSupersededIt** — seed 106: the superseded wid carried the
  membership, and draining it orphaned the whole pre-fullscreen generation.
- **testSupersededMintedTabDoesNotStrandALiveBackgroundTabInAnOrphanGroup** — seed 125, the same supersede
  reached by OPENING a tab, where the orphaned generation still holds a LIVE tab.
- **testActiveTabKeepsItsPendingGroupAcrossASpaceTransition** — the same drain with no supersede at all,
  found once the shrinker stopped minting scenarios no user can perform.
