# ReplayHarness — Specs

## Summary

An event-replay harness over the pure orchestration reducer, closing the corpus gap: the
`RealWorldScenariosTests` corpus pins KERNEL decisions, but most 2026-07 regressions lived in ADAPTER
seams — event-handler choices, synthetic-fact projections, cross-pass orchestration — which one-shot
kernel calls can't execute. The orchestration now lives in `WindowEventReducer.reduce(inout TrackedWindowState,
ReducerInput) -> [ReducerEffect]` (the adapters are an IO shell around it — see `TrackedWindowStateBridge`), so a
recorded debug log replays as a unit test: fixture = initial `TrackedWindowState` + input sequence, assertions =
invariants checked after EVERY step.

## The architecture the harness rides on

- **`TrackedWindowState`** (pure, both targets): the whole orchestration state — the window list in `Windows.list`
  order (title/geometry matching is order-sensitive), app facts, the `TabGroupsTable` registry, the
  hold/pending sets, the activation entries, Space topology. Synthetic facts (`held`, `spaceIsBorrowed`,
  `isFullscreenMirrored`) are first-class fields; `TrackedWindowState.tabWindow` is the ONE projection to the
  kernels, masking or forwarding each — the rec14/15/20/21 rule, enforced in ONE place: the live model's
  last group mutation (`TabGroups.repPicker`) goes through this same projection rather than a copy of it.
- **`ReducerInput`**: one WindowServer event (create/destroy/move/resize/order/focus/Space add-remove/Space
  change), one async read RESULT landing (discovery, title+tabs, WS state, the Spaces re-query, liveness,
  the CGS window lists), or one timer check firing (hold release, drag-out). Each case carries the payload
  plus the ambient facts the live handler read at that instant (uptime, in-Space-transition) — so a
  recording transcribes input by input.
- **`ReducerEffect`**: every side effect the handlers used to fire inline (AX reads, WS queries, captures,
  UI refreshes, timers, log facts). The live shell executes them verbatim; the harness records
  requests/timers and applies pure twins of the model-mutating ones (`removeWindow`).

## Which level pins what (THE RULE)

Every real-world scenario gets pinned at the level where its bug lived:

- **A wrong RULE gets a kernel test** — exact expectations (`matched=`, `untracked=`, a verdict) against
  `TabWindow` snapshots. This is the level for iterating on a fix (a failure names the broken rule), for
  unrolling races as input states (a recording only samples one side), and for property sweeps
  (`frameCorpus` runs the frame invariant over every capture × both claim paths — inexpressible as replays).
- **A wrong CHAIN gets a replay fixture** — the bug was in sequencing, synthetic-fact plumbing, or
  cross-pass orchestration (rec13's leak, rec15's flood, rec19's churn, rec21's merge). The fixture replays
  the recorded events end-to-end and the step invariants police it, plus every OTHER fixture,
  retroactively — the "fix one, regress nowhere" property.
- Usually a chain fix also yields a small kernel test documenting the rule that fell out of it; write both.

Don't move kernel pins up to the replay level: replays assert coarse invariants over one recorded ordering,
kernels assert exact outputs over many orderings — different axes, both needed. And both levels read ONE
transcription of the recorded data: fixtures build their windows from the corpus's `CapturedWindow` raw
facts via `modelWindow(...)` wherever a capture exists.

## Fixture conventions (same law as `RealWorldScenariosSpecs.md`)

- Transcribe RAW recorded facts with provenance (recording file, timestamp, gesture). The initial state is
  the MODEL state at the starting instant, so synthetic markers (borrowed Spaces on background tabs, the
  mirrored fullscreen flag) belong in it — they are model facts, and mis-marking them is itself a bug class.
- Reuse the corpus first: if a window is already a `CapturedWindow`, build it with
  `capture.modelWindow(spaceIds:spaceIsBorrowed:isFullscreenMirrored:lastFocusOrder:)` — raw facts from the
  capture, model-state facts as parameters. Transcribe directly only windows no kernel test needed.
- Never hand-tune values to make a test pass; if behavior changed, change the expectation.
- Timer steps (`holdReleaseCheck`/`dragOutCheck`) are explicit inputs: replay the timing the recording
  sampled, or unroll the orders it didn't — races are data.
- Verify TEETH: reverting the fix a fixture pins must make it fail. That check is also the gate for
  RETIRING a fixture — once a `TestScenario` fails under the same reverted fix, the recording goes.

## The step invariants

1. **One tile per group** — ≤ 1 displayed member always; exactly 1 while the group has a screen claim,
   0 once it's dead remains (rec22).
2. **A group's members must agree on their frame — as much as the way it was formed justifies.** The
   cross-cutting theft rule (rec8/10/11/12), now split, because stated as "same frame" it asserted something
   FALSE about real tab groups and fired on correctly-grouped windows:
   - **Guessed** (geometry alone noticed these windows look alike) → the FULL frame must match, unchanged.
     That is exactly where a window at one frame stole a window at another, so the guard keeps full strength
     where it earned it.
   - **Proven** (the OS reported this window has tabs — `tabCount > 1`) → only the WIDTH must match. A tab
     bar appearing changes the window's HEIGHT, and after "Merge All Windows" background tabs keep their
     pre-merge POSITION indefinitely; both measured live on macOS 26. Width held across every case measured,
     so width is what the rule says. Without this split no fix for the tab-bar case could pass.

   The design's sanctioned transitional states stay exempt either way: a pending drag-out verdict, a held
   member, an unrenderable (0×0/nil) frame, and a group with a GENUINELY-fullscreen member. That last
   exemption is whole-group on purpose: fullscreen resizes only the ACTIVE tab, so a fullscreen window's tabs
   legitimately wear several frames at once (frozen before the transition vs frozen after it), and frames
   carry no theft signal there.
3. **The focused window is never hidden** — most recently focused window of the frontmost active app.
4. **A real on-Space window is never claimed** — tabbed ⇒ Space empty/borrowed/held; exempt while a
   creation is in flight (the sanctioned atomic claim) or the wid is a pending drag-out's outgoing
   representative (its genuine Space outlives the swap by a few ms — observed in rec19).
5. **Space-less ungrouped unheld windows are hidden** (rec15/rec20 strays) — unless the WindowServer has
   them ORDERED IN, which `PhantomWindowDetector.syncVerdict` already treats as decisive before it reaches
   Space-lessness ("a window the WindowServer is still showing on screen is not a phantom"). That state is
   reachable: a window LEAVING fullscreen is ordered back in while CGS has not yet listed it on the windowed
   Space. A real stray is ordered OUT, which is what the recordings caught.
6. **The representative is the most recently focused presentable member** (rec18/rec19 — focus is
   authoritative, read order is not evidence).

## No fixtures remain

`ReplayScenariosTests` has been DELETED (2026-07-18): every recorded chain bug is now reproduced from user
actions by `TestScenarioSimulator`, each teeth-verified. The runner itself is still the engine underneath —
the scenario layer drives it, and its per-step invariants police every scenario.

## What stayed in the shell, and why

- **Acquisition + admission + attribute ingestion** (`WindowAdmissionResolver`, `findOrCreate`,
  `bestEffortTitle`): AX/CGS IPC and object creation; the reducer takes over at `discoveryLanded`.
- **Throttling/coalescing** (`windowAttributesThrottler` etc.): IO pacing, carried on effects as flags.
- **`Windows.removeWindows`**: view/scheduler/subscription cleanup stays live; the reducer decides WHEN
  (`removeWindow` effect) and the harness twins the model part. The MRU-shift semantics exist twice
  (live + harness twin) — the one accepted duplication.
- **Timers** (`armHoldReleaseCheck`/`armDragOutCheck`), the NSWorkspace observers, the factless activation's
  bounded focused-window read, the Space-transition debounce, `Window.init`'s `checkIfFocused` seed, and the
  full-rescan sweeps (`discardDeadPhantomWindows`) — pure IO or init-time seeding.

## Test scenarios

Mirrors `TestReducerRunnerTests.swift` 1:1.

### A. The harness's own teeth

An invariant that cannot fail is decoration, so each one is fed the bug shape it exists to catch and must
report a violation. These are tests OF the harness, not of the reducer.

- **testHarnessFlagsAClaimedOnSpaceWindow** — a tabbed member holding a GENUINE Space (not borrowed, not
  held, no creation in flight) is the claimed-real-window class (rec10's theft) and must be flagged.
- **testHarnessFlagsAGroupSpanningDistinctFrames** — a non-fullscreen group across two frames is the
  cross-frame theft (rec11/rec12); the borrowed marker keeps the on-Space check quiet so the frame check is
  isolated.
- **testHarnessFlagsAHiddenFocusedWindow** — the focused window claimed as a background tab (rec18's
  ejection).
- **testHarnessFlagsARepresentativeThatIgnoresFocus** — a representative that is not the most recently
  focused presentable member (the rec19 churn shape).
- **testLeavingAGroupKeepsTheLentSpaceSoALiveWindowIsNotHidden** — seen live: the exact-set re-form ungroups
  the torn-out window; it keeps the Space the group lent it (marker still set) instead of being asserted
  Space-less, which had hidden a live window for 515ms.
- **testHarnessSpacelessStrayIsHiddenAndHeldIsExempt** — a Space-less, ungrouped, unheld window must be
  hidden by the phantom rule (rec15's stray; rec20's orphaned ex-representative reaches it once `spacesSynced`
  confirms CGS places it nowhere, not on the ungroup itself); a HELD one is exempt.

### B. Replayed chains

- **testNewTabCreationRaceReplaysWithoutViolations** — the creation race clean end to end: the old active's
  1326 lands before the new tab's discovery, the hold keeps its tile through the gap, the new tab's AX titles
  claim it atomically, the hold releases on the claim. Every step satisfies every invariant.
- **testMintedTabThatGoesFullscreenBeforeDiscoveryKeepsItsSpace** — a minted tab FULLSCREENED before its
  discovery lands keeps the fullscreen Space it was given, instead of being forced Space-less as a
  backgrounded tab: both look identical to `pendingSpaceRemoval`, which is why it records the SPACE.
- **testFullscreenBurstKeepsTheHeldTileWhileAnotherFullscreenWindowExists** — rec27: bursting ⌘T inside a
  fullscreen Finder window made its tile disappear ~2.5s while a second fullscreen window existed.
- **testRepresentativeDoesNotBorrowASpaceItJustLeft** — a representative going Space-less must not borrow a
  Space that CONTRADICTS the one it just left (a tab left over from the window's pre-fullscreen life still
  carries the old windowed Space).
- **testMintedTabPairingIgnoresARepresentativeLeavingAnotherSpace** — the minted-tab pairing is by TIME, so
  it must also require the same Space, or a tab joining one window's fullscreen Space pairs with an unrelated
  window's representative leaving the windowed one.
- **testFullscreenTabSwitchToAReusedWidFrontsItAtDiscovery** — a fullscreen switch to a REUSED background wid
  carries no focus signal at all, so the incoming tab must be fronted explicitly at discovery; otherwise the
  switcher shows the PREVIOUS tab until reopened (2026-07-22 QA).
- **testTitlesThatNameNothingKeepTheGroup** — an AX read naming 2+ tabs and matching NO window says the
  titles aren't comparable (#5785) or the siblings aren't tracked; either way the group stands.
- **testTitleReadThatChangesMembershipLeavesAFixedPoint** — a title read that changes membership must
  reconcile, or derived per-member facts (above all the fullscreen mirror) stay stale and the state is not a
  reconcile fixed point.

### C. Order-in, and what it is still allowed to mean

An 815 cannot move the window order any more (see `WindowEventReducerFocusSpecs`), so what is left here is
the bookkeeping it still owns: an untracked wid it names, and the sequences a real capture recorded.

- **testTwoAltTabsIntoTheSameAppBothMoveTheOrder** — two alt-tabs 219ms apart into one app. The second is a
  switch inside the app that is already frontmost, so no activation follows it and AltTab naming its own
  target is the only thing that says the user moved. Unheard, nothing ever corrects it (#5785's stuck
  switcher).
- **testLeavingFullscreenDoesNotRefrontTheAppsOtherWindows** — the recorded #5849 follow-up: leaving
  fullscreen re-shows the whole desktop Space and every window on it is ordered in. A replay of the capture,
  kept now that the inference that misread it is gone.
- **testReshownWindowLandsBehindWhatWasFocusedDuringItsDiscoveryGap** — the one thing an untracked order-in
  still does: an app that hides its window keeps the CGWindow, so reopening re-shows the same wid with no
  create and no 808 (#5785). It is discovered rather than lost, and it claims no rank of its own — where it
  lands is decided the next time its app speaks.
- **testReshownWindowOfAnAppThatWasNotFrontmostIsNotPromoted** — the pid gate on the circumstantial
  promotion: an untracked order-in counts only for the app that was frontmost when the window appeared, and
  the pid can only be checked once discovery names it.

### C2. The group token, and what it retires

- **testTabsJoinOneGroupByTokenWhenTitlesAndFramesNameNobody** — two tabs whose AX titles name nobody (#5785's
  composed titles) and whose frames share no cluster (a tab bar resized one) still end up in ONE group,
  because each named the same `AXTabGroup` element while it was the selected tab. The point of the fixture is
  what it does NOT contain: no create, no pairing window, no clock — the second read lands whenever it lands
  and the group is still exact. This is the signal `recentPairingWindow` reconstructs by arrival time; the
  timer stays for what the token cannot see (a fullscreen group in Terminal / TextEdit exposes no element,
  and a tab nobody has ever selected has no token), so the two are layered, not swapped.

### D. The handover edge (`recordHandover`)

The kernel guards reading `replacedByWid` / `replacedWid` are decoration unless the edge is actually written
from the event stream, so these pin the RECORDING. The two halves are separate WindowServer datagrams whose
order nothing pins, so both arrival orders are tested — the same thing `HandoverOrder` fuzzes end-to-end.

- **testHandoverIsRecordedWhenTheLeaveLandsFirst** / **testHandoverIsRecordedWhenTheJoinLandsFirst** — both
  orders record the same edge. The second is the order the live captures happen to show.
- **testHandoverIsNotRecordedAcrossApps** — time-pairing alone crosses wires between apps; the pid is known
  for two tracked windows, so it is checked there.
- **testHandoverIsNotRecordedDuringASpaceTransition** — a Space switch emits joins and leaves for many
  unrelated windows at once, and any pairing among them is invented.
- **testHandoverIsNotRecordedOutsideThePairingWindow** — two events far enough apart are not one event.
- **testHandoverToAnUntrackedWidIsAppliedAtItsDiscovery** — the MINTED switch: the incoming half is a wid
  never seen, so the edge waits in `pendingHandoverEdge` and is applied at discovery.
- **testPendingHandoverIsDroppedWhenTheDiscoveredWidBelongsToAnotherApp** — the pid check moves to
  CONSUMPTION when one side was untracked, that being the first moment a pid exists.
- **testMintedTabSwitchRefreshesTheIncomingFrameFromTheWindowServer** — the minted tab arrives wearing the
  frame it had as a BACKGROUND tab, and no geometry event will ever correct it (we subscribe to that wid only
  after its order-in). Forming the group asks the WindowServer, as the tracked half does on `joinedSpace`.
- **testPendingHandoverIsDrainedWhenTheMintIsSuperseded** — a mint superseded before discovery never becomes
  a window, so the edge naming it dies with it.
- **testPendingHandoverIsDrainedWhenTheMintIsRejectedByTheDiscriminator** — the other way a mint never
  becomes a window. `accepted: false` is the ONLY moment we learn that for certain (Finder's 804 lags or
  never fires, and a wid joining a non-visible Space is never even scheduled for discovery), so both pending
  maps drain there. Consumption is not time-bounded, so a leaked edge could later dress a window in a stale
  `replacedWid` that `dragOutVerdict` reads as settled.
- **testMintedTabSwitchKeepsTheTabsTheTitlesAlreadyGrouped** — the handover claims a REPRESENTATIVE, not a
  membership. When the AXTabGroup titles land in the same discovery and group the mint with every tab of the
  window, re-forming from the inherited pair would evict the rest, since `formGroup` is exact-set. Live QA
  C-10: one 4-tab Finder window drawn as two tiles.
- **testHandoverIsClearedWhenTheReplacedWindowComesBack** — the edge describes the CURRENT state, so it
  expires when either end moves again.

### D. The z-order seed (`zOrderRead`, the very first summon)

The blocking CGS stacking query AltTab fires while it has no focus history, applied through the MRU model
instead of over it. It is re-made as startup discovery lands (`Windows.reseedZOrderDuringStartup`) so the
order settles before the user looks; the first summon still fires one last call, which should now find
nothing to change. Anything it decides after a render, the user watches happen — which is why what it moved
has to be reported accurately.

- **testZOrderSeedsWindowsWithNoFocusHistory** — with no focus history at all, stacking IS the order: AltTab
  launched into a desktop it did not watch being built, and top-most first is the best guess it has.
- **testZOrderNeverDemotesAWindowThatWasActuallyFocused** — a window the OS told us was focused keeps its
  place, because the seed is written into the `focusedAt` TIEBREAK rather than over it. Teeth-verified:
  assign the ranks directly, as `Windows.sortByLevel` used to, and this fails with the live symptom — the
  live capture where the just-focused Terminal tab, backgrounded and therefore absent from the query, fell
  from tile 0 to tile 3 twenty milliseconds in, taking the highlight with it.
- **testZOrderReportsWhatItMovedOnAColdModel** — the seed writes its answer into `lastFocusOrder` and only
  then asks `recomputeFocusRanks` what moved, so on a cold model (every `focusedAt` still 0, which is the
  launch case it runs in) the re-derivation finds its own answer already in place and reports nothing. The
  reducer then emits no log and no `.refreshUi` while the order really has changed, and an open switcher
  keeps drawing the old list. Teeth-verified: it fails against the pre-fix `return recomputeFocusRanks()`.
  Live evidence — the 2026-08-25 QA run moved the MRU front onto a Finder window with no
  `zOrder seed reordered` line anywhere in its debug log, which is why three investigations dead-ended.
- **testZOrderThatChangesNothingSaysNothing** — the other side: a seed that really changes nothing stays
  silent, so a first summon does not repaint for nothing.
- **testZOrderPutsWindowsItCannotSeeBehindTheStackedOnes** — the query lists the visible Spaces' windows, so
  a background tab, a minimized window and another Space's window are absent; they keep their relative order
  behind the ones it did see, since being off screen says nothing about which was touched last.

## Switching to a tab we adopted but never grouped

A tab switch emits no focus event, only the Space swap, so the Space-join of a background tab while its app
is frontmost IS the focus signal. The gate for that used to require `isTabbed`, which asks whether we had
managed to link the tab into a group — our own bookkeeping, not the user's reality.

- **testSwitchingToAnAdoptedButUngroupedTabFrontsIt** — Finder's tabs share one title and keep a stale frame
  while backgrounded, so the AX-title match names nothing and geometry sees two different positions: the tab
  is adopted by the brute-force scan and then sits Space-less, ordered-out and in no group. Switching to it
  wrote no focus at all, and the group formed a beat later (once the tab was on-screen and readable)
  re-elected the tab the user had just LEFT as the one it draws. Teeth-verified: without the second arm the
  MRU stays `[549, 544]` and `groupRepresentative` answers 549, which is the live symptom.
- **testAnUngroupedTabJoiningASpaceOfAnInactiveAppDoesNotFront** — the control: the same join with the app in
  the background is not a switch the user made, and fronts nothing.
