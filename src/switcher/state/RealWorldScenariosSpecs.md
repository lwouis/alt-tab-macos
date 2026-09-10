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

Run the app with `--logs=debug` (one line per event: the input, then every decision the reducer made for it,
plus the per-show tile dump with frames/spaceIds/flags), reproduce ONCE on a real machine, then transcribe the
raw values into a new `static let` capture with a provenance comment (app, macOS version, date, gesture) and
iterate offline against it. Extend `frameCorpus` when the capture has 2+ windows, so the cross-cutting frame
invariants cover it too. Never hand-tune the numbers to make a test pass — if behavior changed, change the
expectation. When a capture samples a RACE, don't trust the one order it recorded: write down the partial
order and unroll the free pairs as input states (see the "Race interleavings" section in the test file).

## Corpus

- **`terminalMerge4Tabs`** — Terminal "Merge All Windows" over 4 windows. All `~`, 757×583; active (29328)
  holds Space 3 + AXTabGroup `["~"×4]`, three background tabs Space-less, no AXTabGroup. **Positions corrected
  2026-07-30**: the original recording put all four at ONE position (683,101), which the OS does not produce —
  a merge never converges the tabs' frames. The merged window is a brand-new wid one cascade step past the
  windows it absorbed, and those keep their positions, frozen, so the group spans four origins 29px apart and
  only the SIZE is shared. Re-measured from the live QA run (Terminal, `757x543@942,277 / @913,248 /
  @884,219 / @855,190`, active first; Finder is the same shape at 920×436) and mapped onto this capture's
  wids in the same MRU order. The single position is why every kernel test here passed while both live merges
  formed NO group: the cascade is exactly what `framePartitions` splits on.
- **`finderTabDraggedOutStillClaimsThreeTabs`** — Finder, Window ▸ Move Tab to New Window (live QA
  2026-07-30). The torn-out window at (290,712) still reports the 3 tabs it had as the group's active,
  beside the group it left at (1116,683). The capture of a stale `tabCount`.
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
  Finder case: tabs "lwouis"(inactive)/"git"(active) +
  a same-app standalone "Movies". Distinct titles, so a clean unambiguous match.
- **`tabbedWindowMovedBetweenSpaces`** — a tabbed window changing Space: 1326 (leave old) + 1325 (join new),
  each carrying (spaceId, wid). The events that fire reconcile so the group follows the move.
- **`missionControlAxCycle`** — MC begin/end from the Dock AX stream (`AXExposeShowAllWindows` / `AXExposeExit`).
  Reference only: MC has no pure-kernel consumer and moves no window between Spaces (it orders thumbnails in/out);
  the ids it fires (818, 1327, 1328) are intentionally not routed. `AXExposeExit` is the clean end-of-transition hook.

## 2026-07-14/15 captures (the rec8–rec13 QA rounds)

- **`terminalLiveGroupActive` / `BackgroundTab`** — a live 2-tab group whose ACTIVE transiently reported a nil
  AXTabGroup. A nil read is routine churn; it must never dissolve a group.
- **`terminalAfterDissolutionActive` / `Orphans`** — the aftermath of a wrongful dissolution: orphans hold a
  STALE Space and aren't tabbed ⇒ unclaimable. Proves un-tabbing is irreversible, hence never dissolve on nil.
- **`terminalNewTabActive` / `StaleOldActive` / `SettledTabs`** — the creation race: the old active's 1326 lags
  the new tab's discovery ⇒ 2 tiles unless the new active claims it (`activeIsNewlyDiscovered`).
- **`fullscreenTerminalNewTab` / `OldActive` / `SettledTabs`** — fullscreen Cmd-T: no AX titles, the new tab's
  own fullscreen flag lags, both actives hold the ONE fullscreen Space for a beat.
- **`fullscreenTabSwitchEvents`** — a fullscreen tab switch emits NO focus event and no add-for-a-tracked-wid;
  the incoming tab is re-DISCOVERED and must be fronted explicitly.
- **`fullscreenFinderAddTabNewTab` / `HeldOldActive` / `FrozenSibling`** — the visible-pick inversion: the held
  old tab had a borrowed Space while the brand-new tab was Space-less; only `newlyDiscovered` can say which
  member took over.
- **`fullscreenFinderSwitchHeldVisible` / `BackgroundTabs`** — a Space-less held visible: any rule phrased as
  "holds a Space the visible doesn't" degenerates against an empty visible Space.
- **`twoFullscreenFinderWindowsWithTabs`** — every fullscreen window is screen-sized ⇒ ONE size cluster
  spanning TWO Spaces; the fullscreen invariant is per SPACE, not per cluster.
- **`twoFullscreenFinderWindowsMidSpaceSwitch`** — mid-transition EVERY window reports BOTH Spaces ⇒ no
  member's Space is evidence ⇒ form no group.
- **`fullscreenFinderDragOutWindows`** — 3 extracted fullscreen windows on 3 Spaces, all carrying the original
  group's stale link ⇒ the two holding their own fullscreen Space have LEFT (unlink).
- **`terminalVisibleWithForeignSpaceTabs`** — background tabs reporting a FOREIGN Space disjoint from their
  visible's, yet genuinely tabs. Disproves "disjoint Space ⇒ not a tab" outside fullscreen.
- **`finderTwoWindowsSharingATabTitleActive` / `Other`** — "the void": at launch everything is newly TRACKED,
  so the on-screen claim must not fire; a real window sharing a tab title was swallowed and hidden.
- **`finderFocusedWindowWronglyTabbed`** — the focused window can never be a background tab; the focus signal
  recovers a coherent group whose visible got wrongly tabbed (`groupRepresentative`).
- **`finderDuplicateTabTitlesActiveA/B` / `TabsOfB` / `Standalone`** — rec10: two groups sharing tab titles;
  the frames are the ground truth (one window's tabs agree on the frame; the standalone sits at its own).
- **`finderSelfOnlyLinkNewTabGapVisible` / `Backgrounding`** — rec8: a window linked only to ITSELF (its tabs
  untracked) confirms no cluster; a self-only link must never be written or trusted.
- **`finderTwoCascadedWindowsActiveA` / `TabsA` / `TabsB`** — rec11: two windows 29px apart (the macOS cascade
  offset), same size, every tab titled "lwouis" — position is the ONLY fact separating them. Also proves the
  AX title COUNT bounds nothing (Finder destroys backgrounded tabs' windows).
- **`finderTabSwitchIncomingStale` / `IncomingSettled` / `Outgoing`** — rec13: the windowed tab-switch
  handover, which no claim path covers (geometry needs a Space-less member; the title claim needs a brand-new
  active). The incoming tab's own position is STALE at claim time and settles ~215ms later.
- **`finderStaleRead*`** — rec18 (2026-07-16): rapid tab switching; a QUEUED AX read landed as from window
  78103 right after the user had switched to 78111, ejected the real active from its own group
  (`untab=[78111]`) and made the reader the representative — successive stale reads then fought over the
  group, ending in 2 shown tiles for one window that never healed. Ground truth: focus is authoritative — a
  read from a less recently focused member neither ejects nor displaces the fresher one.
- **`finderOrphanedExRep*`** — rec20 (2026-07-16): Finder mints a new wid per tab switch; when the tracked
  outgoing window died, the representative fell back to an older member and normalize lent it a Space — then
  the next incoming tab (a brand-new wid no keep-rule can recognize) re-formed the group without it, and it
  stood as a permanent stray tile holding the Space WE lent it. Third variant of "our synthetic Space defeats
  our evidence rules" (rec14 hold, rec15 stale CGS, rec20 borrow) ⇒ `spaceIsBorrowed` is now a first-class
  fact: claim-plausible like the hold, and dropped when the membership that justified it ends.
- **`terminalSameFrameBurst*`** — rec14 (2026-07-16): 3 separate Terminal windows stacked at ONE position +
  a tab burst + a switch to a burst tab. The held outgoing tab, carrying the Space the anti-vanish rule
  BORROWED onto it, was rejected by the claim's on-screen protection and stood as a ghost 4th tile for
  ~200ms. Ground truth: a held window is claimable (its Space is ours); the two genuinely separate windows
  (4px taller — no tab bar) stay unclaimed. Also the live proof that the separate-window ambiguity Terminal
  poses is decided by SIZE (tab bar) + the hold, never by position (all at one point).

## #5785 — composed window titles (`composedTitle*`, `reporterComposedTitle*`)

Captured 2026-07-26 on macOS 26 by restoring the reporter's Terminal profile (`ShowDimensionsInTitle` +
`ShowActiveProcessInTitle` on, which is the macOS DEFAULT), plus their own numbers from the #5785 logs.
The whole title signal can be **absent**, not merely noisy: Terminal composes its WINDOW title from
components the TAB title has no setting for, so the two strings are never equal.

    WINDOW "~/Documents — -zsh ▸ -zsh — 80×23"     TAB "~/Documents"

Logged live before the fix: `updateState active#28963 titles=[…3…] matched=[] untracked=[…3…]`, so
`siblingWids.count == 1` dissolved the group as `axTitlesSolo` on every AX read while geometry re-formed it
on every WindowServer event. Only 1 of the 3 Terminal windows survived in the model. This is the corpus's
ground truth that a title comparison cannot discover these tabs at all, which is why the AXTabGroup's COUNT
confirms the geometry cluster instead (`TabGroupResolverSpecs.md`).

`CapturedWindow.tabWindow` DERIVES `tabCount` from `axTabTitles`, the same relationship the live reducer
records, so every pre-existing capture now carries its real count too. The whole corpus still passes
unchanged, which is the evidence that the new confirmation clause alters no recorded scenario.

## The cross-cutting frame invariant

Every recorded theft (rec8/10/11/12) was ONE bug — a window at frame F grouped with a window at frame F' —
fixed each time only on the path its scenario took. `frameCorpus` + `testNoGeometryGroupEverMixesDistinctFrames`
+ `testNoTitleMatchEverClaimsAcrossFrames` pin the rule over the WHOLE corpus and BOTH claim paths, so the next
claim path added has to satisfy it too. Extend `frameCorpus` with every new multi-window capture.

**The one exception, forced by the OS (2026-07-30).** Merge All Windows never converges the tabs' frames, so a
merged group spans a 29px cascade for as long as it lives and the invariant held unconditionally meant no merged
group could form. On the GEOMETRY path frames may now differ where AX itself accounted for every member — the
visible's AXTabGroup count equals the cluster size — and the invariant test asserts exactly that, plus that the
SIZE still matches. The TITLE path keeps the invariant unconditionally: there, waiving position is rec11
(11 titles, 8 tracked wids, all identical), and it doesn't need waiving because geometry writes the link that
`positionsCompatible` already honours.

## Two coexisting groups of one app (`twoGroupsSameApp`)

Recorded LIVE: with `TABDBG` logging armed, the user hand-dragged tabs between two real TextEdit groups (and
closed one window mid-way). Both AXTabGroups were captured from the log: A = ["Untitled", "Untitled 2",
"Untitled 3"], B = ["Untitled 7", "Untitled 9"], plus 3 standalone windows. `testTwoCoexistingGroups_*` pin
the durable invariant a between-groups move must preserve: each group's `matchSiblings` resolves ONLY its own
tabs, never the other group's or the standalones. (Automating the atomic single-tab drag is impractical —
TextEdit Cmd-T = Show Fonts, a torn-off tab detaches into a new window unless dropped exactly on a tab bar,
and AltTab's off-screen windows block computer-use drop targets — so it was done by hand and read from the log.)
`textEditGroup6` is a separate real single-group capture (distinct titles, the clean-match contrast to `~`).

## Event-replay fixtures (`ReplayScenariosTests` — see `TestReducerRunnerSpecs.md`)

This corpus pins KERNEL decisions; adapter-seam regressions (event orchestration, synthetic-fact
projections, cross-pass sequencing) replay END-TO-END through `WindowEventReducer` via the
`ReplayHarness`: fixture = initial `TrackedWindowState` + recorded input sequence, invariants checked after every
step. Same transcription law as here (raw facts, provenance, no hand-tuning).

**THE RULE — pin every real-world scenario at the level where its bug lived.** A wrong RULE gets a kernel
test here (exact expectations, race unrolling, the `frameCorpus` property sweeps); a wrong CHAIN gets a
replay fixture (the recorded events end-to-end, policed by the step invariants across ALL fixtures — the
"fix one, regress nowhere" property). A chain fix usually also yields a small kernel test documenting the
rule that fell out of it; write both. Both levels share ONE transcription: replay fixtures build their
windows from these `CapturedWindow`s via `modelWindow(...)` wherever a capture exists. **No replay fixtures
remain** — rec19/21/24/24c/24e were all RETIRED (2026-07-18) once `TestScenario`s reproduced their bugs from
user actions alone, each teeth-verified against the same reverted fix, and `ReplayScenariosTests` was
deleted. See `TestScenarioSimulatorSpecs.md`.

**This kernel corpus is NOT being retired.** The migration targets replay fixtures (chain-level pins). These
captures pin RULES — exact expected outputs, unrolled races, the `frameCorpus` property sweeps — which the
model's coarse properties cannot replace, and the pin-level rule above says kernel pins never move up to a
coarser layer.

## Known gaps (capture when reproducible)

- Dragging a window (with tabs) to another Space's thumbnail in Mission Control. The resulting event pair is
  captured (real events) in `tabbedWindowMovedBetweenSpaces`; the live end-to-end drag is not.
- The atomic single-tab drag BETWEEN two groups (the before/after states are in `twoGroupsSameApp`; the drag
  itself was interleaved with other gestures).
- Post-fix re-recordings of the rec8/9/10 theft shapes — every existing capture of them predates the fixes,
  so a fresh clean run is the only live confirmation the thefts are gone (the kernel tests pin them offline).
- The windowed tab-switch handover's DESIRED outcome (`finderTabSwitch*` captures the failing state; no kernel
  test yet pins a fix, since none is implemented — see the capture's comment for the two-part candidate).

## Test scenarios

- **testMergedTabsGroupByGeometry** — merged group ⇒ `geometryGroups` groups the 3 Space-less tabs under the active.
- **testADraggedOutWindowIsNotFoldedBackByAStaleTabCount** — live: the torn-out window, its drag-out
  already confirmed, was folded straight back by geometry because a BACKGROUND member's stale `tabCount`
  accounted for the cluster while the genuine on-screen member read a smaller count. Teeth-verified, and note
  it only bites with the live fact that the AX read had re-formed the real group in the same dispatch — the
  visible is then AX-confirmed, which is exactly the case that skips the tab-count bound.
- **testMergedTabsFormAGroupFromNothingButTheTabCount** — the state a merge ACTUALLY leaves: no window carries a
  link (the title path can't make one — same title, four different positions), so geometry was the only path and
  it formed no cluster at all. 4 windows, 0 groups, 3 hidden as phantoms. The AXTabGroup count accounts for
  every member, which is what may override the cascade (`tabCountAccountsForEveryMember`).
- **testASecondWindowsActiveTabIsNotSweptInByACountItAlsoDeclares** — the other side of that override: two
  same-size Finder windows with 3 tabs each, the top one mid tab-switch. Its outgoing active is Space-less for
  the handover, so the bottom window is the cluster's only genuine Space holder and its declared 3 matches the
  3 members — but one of them is the TOP window's active tab, which reports an AXTabGroup of its own from
  another position. The count is a coincidence there, not an account, and waiving the position split handed one
  window's active to the other's group (live QA T-20, 2026-09-10).
- **testSeparateWindowsNeverGroup** — separate windows (incl. a flaky Space-less read) ⇒ no group (the gate holds).
- **testMergedTabsMatchByTitleOnlyOnceGeometryHasLinkedThem** — the title path cannot bootstrap a merged group
  and must not be taught to: four distinct cascade positions with one shared title is rec11's exact shape, where
  position is the only separating fact. So the first read names nobody and reports 3 titles untracked; once
  geometry has written the link, `positionsCompatible`'s link bypass makes this path agree and the group is
  stable instead of re-decided against the stale cascade on every read.
- **testNineTabsLeaveThreeUntracked** — 9 `~`, 5 tracked ⇒ 5 matched, 3 untracked (→ discovery). "sometimes 9".
- **testFinderTabsAllUntracked** — only the active Finder tab tracked ⇒ all 3 other titles untracked.
- **testBackgroundTabPhantomFlipsWithTabDetection** — a Space-less tab is phantom until `isTabbed`, then exempt.
- **testRemovedFromSpaceStormRouting** — every 1326 in the storm routes to `.updateSpaceMembership` (the churn trigger).
- **testFullscreenTabsNotGroupedByGeometryAlone** — divergent sizes under fullscreen ⇒ geometry can't group; the
  `tabbedSiblingWids` link is what holds the group.
- **testFullscreenTabPositionCompatibleViaExistingLink** — an already-linked inactive tab stays compatible despite
  divergent fullscreen position/size.
- **testComposedWindowTitleMatchesNoSibling** — the defect: 3 AX tab titles, not one matchable to a window,
  reproducing the logged `matched=[] untracked=[all three]`. Nothing may be un-tabbed on that silence either.
- **testComposedTitleGroupIsFormedByTheTabCount** — the fix: the count from that same unusable read confirms
  the cluster, so the tabs group into one tile with no title comparison.
- **testComposedTitleGroupStaysUnformedWithoutTheCount** — the counterfactual: `tabCount` 0 and these same
  two windows are the #5830 case (same app, same size, one briefly Space-less) and stay ungrouped. The count
  is doing the work, not the geometry.
- **testReporterComposedTitlesGroupByTheTabCount** — the same at the reporter's own numbers (1017×610).
  Their capture holds ONLY what their logs contain: no AX tab titles (the diagnostics flag they were
  asked to relaunch with never took effect, which is part of why that flag is gone) and no position (their logs record size but never position). The test supplies `tabCount: 2`
  itself, justified by the Space-swap signature in their log rather than by an AX read.
- **testDragOutShrinksTheGroup** — active tab leaves 4-window group ⇒ shrink to the 3 survivors.
- **testDraggedOutWindowNotReAbsorbedByGeometry** — the escaped window (new size, holds a Space) isn't re-collapsed.
- **testDragOutVerdictConfirmsTheRealDragOut** / **testDragOutVerdictConfirmsTheRealTabSwitchAsASwitch** /
  **testDragOutVerdictUndecidedWhileTheIncomingFrameIsStale** — the recorded drag-out settles at another
  frame (⇒ expelled from its group), the recorded rec13 switch settles at the same frame (⇒ membership
  stays), and the rec13 stale-position trap documents why the verdict is re-checked (and frames WS-refreshed)
  rather than trusted once.
- **testFinderStandaloneWindowNotSweptIntoGroup** — "Movies" (same app, non-tabbed) stays out of the git/lwouis group.
- **testFinderInactiveTabIsPhantomUntilTabbed** — "lwouis" Space-less ⇒ phantom until `isTabbed`.
- **testFullscreenDragOutExtractedWindowsAreUnlinked** — 3 separate fullscreen Finder windows on 3 Spaces, all
  still carrying the original group's stale link ⇒ the two holding their own fullscreen Space are reported as
  having LEFT the group (unlink), so all three show.
- **testForeignSpaceBackgroundTabsAreNotTreatedAsDeparted** — a NORMAL Terminal group whose background tabs
  report a foreign Space disjoint from the visible's ⇒ NOT departed. The ground truth that "holds a Space the
  visible doesn't" can't mean "not a tab" outside fullscreen.
- **testFullscreenSpacelessBackgroundTabsAreNotDeparted** — a fullscreen group's Space-less background tabs are
  never departed (that's exactly what a background tab looks like).
- **testFullscreenAddTabShowsTheNewTabNotThePrevious** — fullscreen Finder + add a tab: the new tab is
  momentarily Space-less while the backgrounded old tab is held with a BORROWED Space, so the visible-pick
  chose the old one (switcher showed the previous tab, then two tiles). Pins that `newlyDiscovered` identifies
  the member that took over, and that a fullscreen cluster spanning one Space folds the rest as background.
- **testHeldSpacelessVisibleNeverStrandsItsOwnTabs** — fullscreen Finder tab switch: the group's visible had
  just backgrounded (Space-less, held) while its tabs kept the backfilled Space ⇒ nothing has departed.
  Judging "holds a Space the visible doesn't" against a Space-less visible unlinked the group's own tabs and
  showed a tile per tab, permanently.
- **testTwoFullscreenWindowsEachResolveToOneTile** — 2 fullscreen Finder windows + their tabs all share the
  screen size ⇒ ONE size cluster spanning TWO Spaces. Must yield one group per Space (2 tiles). Asking whether
  the whole CLUSTER spans ≤1 Space bailed and left the second window's tabs as extra tiles.
- **testMidSpaceSwitchNeverFoldsTwoFullscreenWindows** — switching between two fullscreen windows, EVERY window
  of the app transiently reports BOTH Spaces (`sp[4310, 4305]`) ⇒ no member's Space is evidence ⇒ form no
  group. Folding then hid the second fullscreen window, sending the default selection past both its tiles.
- **testSpacesSettleThenTheTwoFullscreenWindowsResolveSeparately** — the same windows once the Spaces settle:
  each Space resolves on its own, and the other fullscreen window is never a background tab.
- **testWindowDiscoveredAtLaunchNeverClaimsAnotherRealWindow** — "the void": two separate Finder windows share
  the tab title "lwouis"; at launch both are merely newly TRACKED (nothing created), so the on-screen claim
  must not fire. It firing tabbed a REAL window, hid it, and the switcher's default selection was computed
  without it — then it reappeared, leaving the selection stale on an unrelated tile.
- **testSeparateWindowSharingATabTitleIsNeverClaimed** — rec10: several Finder groups share the tab title
  "lwouis"; a separate window at its own frame must never be claimed by title.
- **testTabSwitchInOneWindowIsNotAnnexedByAnotherSameSizeWindow** — the rec10 theft itself: a tab
  backgrounding INSIDE window B is not adoptable by a same-size unrelated window (a live group — one whose
  own member still holds a Space — is never orphaned; `isOrphanedTab`).
- **testWindowLinkedOnlyToItselfConfirmsNoTabCluster** — rec8's seed: a self-only link confirms no cluster.
- **testASwitchingWindowIsNotFoldedIntoTheNeighbourItOutranksInMru** — live 2026-08-02: a tab switch in the
  FRONT Finder window let the OTHER Finder window's cluster claim it, so a tile stopped being drawn and the
  summon 15ms later offered four tiles instead of five. MRU is what refuses the fold — a group's active tab
  is its most recently focused member by definition, so a window that outranks the candidate representative
  cannot be one of its background tabs. The neighbour's own group must still form.
- **testCascadedWindowTabsAreNotClaimedAcrossWindows** / **testGeometryDoesNotClusterCascadedWindowsOfTheSameApp**
  — rec11/rec12: the 29px cascade collision, closed on BOTH claim paths (titles: exact-position match;
  geometry: `framePartitions`).
- **testGroupIsNotRepresentedByAnUnrenderableIncomingTab** — rec11: a 0×0 incoming tab never represents its
  group; the outgoing, still-captured tab keeps the tile.
- **testWindowDiscoveredAtLaunchNeverClaimsAnotherRealWindow** — "the void": the on-screen claim never fires
  for merely newly-TRACKED windows (launch).
- **testNewTabClaimsStaleOldActive** / **testStaleOldActiveNotClaimedOnAPlainReview** — the creation-race
  claim fires exactly when the active is newly CREATED, and never on a review.
- **testNewTabRaceBothInterleavingsGroupTheOldActive** /
  **testFullscreenNewTabRaceBothInterleavingsGroupTheOldActive** — both orders of the un-guaranteed
  `removedFromSpace(old)` vs `discovered(new)` pair resolve to ONE tile (races unrolled as data).
- **testDissolvedGroupCannotBeRebuiltByMatching** / **testLiveGroupSurvivesNilTitlesRead** — why a nil
  AXTabGroup read must never dissolve a live group (irreversible from the resulting facts).
- **testFullscreenNewTabGroupsWithOldActiveOnSameSpace** / **testFullscreenAddTabShowsTheNewTabNotThePrevious**
  — fullscreen creation: one group, and the NEW tab is the visible (`newlyDiscovered`).
- **testFullscreenTabSwitchEmitsNoAddForATrackedWindow** — the fullscreen switch arrives via discovery, not
  focus; the incoming tab must be fronted explicitly.
- **testMidSpaceSwitchNeverFoldsTwoFullscreenWindows** /
  **testSpacesSettleThenTheTwoFullscreenWindowsResolveSeparately** /
  **testTwoFullscreenWindowsEachResolveToOneTile** — the fullscreen Space invariant: per-Space resolution,
  and no verdict while Spaces are unsettled.
- **testHeldSpacelessVisibleNeverStrandsItsOwnTabs** — a Space-less visible proves nothing left its group.
- **testFinderNewWindowNotSwallowedByTabGroup** — Finder cmd-N: an on-Space window never fills a tab title.
- **testDistinctTitleTabsAllMatchCleanly** — the TextEdit contrast case: distinct titles are the easy path.
- **testTwoCoexistingGroups_A_matchesOnlyItsOwnTabs** / **testTwoCoexistingGroups_B_matchesOnlyItsOwnTabs** —
  coexisting groups of one app resolve only their own tabs.
- **testTabbedWindowMovedBetweenSpacesRouting** / **testMissionControlCycleIsAxDrivenNotSpaceMembership** —
  event-routing pins (Space moves carry payloads; MC ids stay unrouted).
- **testStaleReadNeitherEjectsNorDisplacesTheFocusedMember** — rec18: the stale read keeps the more recently
  focused on-screen member, and the representative pick follows focus, not the reader.
- **testExRepresentativeWithABorrowedSpaceIsClaimable** / **testExRepresentativeWithAGenuineSpaceStaysProtected**
  — rec20: the borrow flag opens the claim exactly when the Space is ours, and the same shape with a genuine
  Space keeps the void protection.
- **testHeldOutgoingTabIsClaimableDespiteItsBorrowedSpace** / **testUnheldOnScreenWindowStillProtectedInTheSameShape**
  — rec14: the held leg opens the claim exactly when the hold says "backgrounding tab", and the on-screen
  protection still rejects the identical shape without the hold.
- **testNoGeometryGroupEverMixesDistinctFrames** / **testNoTitleMatchEverClaimsAcrossFrames** — the
  cross-cutting frame invariant over the whole `frameCorpus`, both claim paths.
- **testAnotherWindowNeverClaimsAFullscreenedGroupsFrozenTabs** — rec21: window B's read must not claim
  window A's frozen tabs. They sit at A's frame, so the exact-position test protects them — but only because
  the projection hands the kernel GENUINE fullscreen; the mirrored flag waived the frame test and merged 25
  windows across three frames.
