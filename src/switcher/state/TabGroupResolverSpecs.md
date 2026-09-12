# TabGroupResolver — Specs

## Summary

`TabGroupResolver` holds the pure decisions behind macOS **OS-tab** detection — deciding which windows are
inactive tabs of one tabbed window, given the facts AltTab can read. macOS exposes no public API that maps
an inactive tab to its window: `_AXUIElementGetWindow` on an AXTabButton returns the *parent* window's WID,
not the tab's own, so tabs must be matched to windows **by title**. Inactive tabs also appear in no CGS
list, so the WindowServer-driven
discovery never sees them until the user focuses one. Extracted as a pure kernel from `TabGroup` (which
keeps the `Windows.list` reads/writes and the AX/CGS side effects) so the brittle matching is unit-testable
without the `Window` graph. Operates on the flat `TabWindow` record — the tab analogue of `WindowState`,
carrying the `pid` / `wid` / `size` / `position` / `tabbedSiblingWids` that grouping needs and `WindowState`
omits.

Several independent signals locate tabs, used at different times:

- **AX group identity** (`TabGroupToken`, the strongest) — the `AXTabGroup` element's own `AXUIElementID`,
  read out of the same call the titles come from. Every window of a group hands out the SAME element while
  it is the selected tab, so two windows naming it are siblings by construction: no title has to match, no
  frame has to cluster, and nothing has to arrive within a time window. Measured across Cmd+T, tab switch,
  drag-reorder, Merge All Windows, tear-out, a cross-group drag and fullscreen, in Finder / Terminal /
  TextEdit. Its limits are what keep the other signals alive:
  only the SELECTED tab exposes a tab bar at all, Terminal's and TextEdit's fullscreen bars sit in a window
  no downward walk reaches, and the element is REPLACED by Merge All Windows and by every fullscreen
  transition — so it is a token windows agree on while it lives, never a durable id, and a window nobody has
  ever read as a selected tab has none. The tab BUTTONS are deliberately not used: they are rebuilt by
  ordinary operations (Finder rebuilds all of them on one Cmd+T) and each reports the SELECTED window's wid
  rather than its own, so a button is neither stable nor self-naming.
- **AX titles** (`matchSiblings`) — authoritative but only available for the *active* tab (an inactive tab
  reports no AXTabGroup), read at discovery and on each show. Matches by title, so it's fragile when titles
  are dynamic (Terminal renames tabs by cwd/command) or drift between the tab-button title and the window's
  own title. That drift can be TOTAL, not marginal: an app may compose its WINDOW title from components its
  TAB title has no setting for, which is what stock Terminal does (`"~/Documents — -zsh ▸ -zsh — 80×23"` as a
  window, `"~/Documents"` as a tab, #5785). Then nothing matches, ever, and this signal is simply absent.
- **AX tab COUNT** — the half of the same read that is never in doubt. macOS exposes no per-tab window
  handle (`_AXUIElementGetWindow`, `AXWindow`, `AXParent` and `AXTopLevelUIElement` on an AXTabButton all
  return the PARENT window's wid — re-probed on macOS 26, don't re-litigate), but the AXTabGroup's presence
  means tabbed and its button count is exact. So the count confirms a geometry cluster when titles can't,
  and bounds it.
- **Geometry** (`geometryGroups`) — reactive, AX-free: within one app, windows sharing an exact size where
  one holds a Space and the others are Space-less are a tabbed window and its background tabs. Catches the
  tab switch that AX missed (the "pop-in"), and fullscreen tabs that expose no readable AXTabGroup. Geometry
  alone does not **create** a group: it only fires when the visible window is fullscreen or was already
  AX-confirmed as tabbed (`tabbedSiblingWids != nil`). Otherwise separate windows of one app that share a
  default size and go briefly Space-less (a Space transition, a flaky CGS read) get collapsed into a phantom
  tab group, hiding real windows (#5830).

## Functions

- **`geometryGroups(windows, newlyDiscovered: nil) -> [GeometryGroup]`** — group same-app, same-**frame**
  (size, then split by POSITION — `framePartitions`) candidates where the visible tab holds a Space and
  ≥ 1 sibling is Space-less. Position was once excluded because a background tab's position goes stale while
  ordered out — but size comes from the same frame and goes stale with it, so the size half of the key already
  fails then (`terminalFullscreenBackgroundTabs`: 757×543 vs. their fullscreen active's 1440×864). All it
  bought was merging distinct windows: macOS cascades by 29px, so two Finder windows at the default 920×436
  were one cluster and one annexed every tab of the other mid-burst, vanishing its tile (rec12). A cluster with
  ANY fullscreen member is left whole — a fullscreen window's tabs can't share its frame, and a new tab's
  `isFullscreen` LAGS, so the flag is only trustworthy cluster-wide; two fullscreen windows are separated by
  the per-Space partition instead. Minimized / size-less windows are excluded. A separate real window is never
  Space-less, so two visible same-size windows are **not** collapsed. The cluster must be CONFIRMED — the
  visible was AX-confirmed tabbed (`tabbedSiblingWids != nil`), OR any member is fullscreen (its tabs expose
  no readable AXTabGroup and a new active's own fullscreen flag lags discovery), OR a background candidate is
  already grouped **and its group has lost its visible** (no other member of it still holds a Space — a new tab
  taking over that group) — so geometry never fabricates a group from unconfirmed same-size windows (#5830).
  The visible's own AXTabGroup COUNT (`tabCount > 1`) is a fourth confirmation, for the app whose titles
  never match: `tabbedSiblingWids` is written only by the title path, so without it that gate could never
  open and the tabs churned as separate tiles forever (#5785). It can only be ADDITIONALLY true where no
  group was formed — an app whose titles match already has `tabbedSiblingWids` — so it cannot change those
  apps' behaviour. A fold confirmed ONLY this way is BOUNDED by the count: more background candidates than
  `tabCount - 1` means the cluster holds a non-tab (a separate same-frame window gone transiently
  Space-less, a second group at the same frame), which one is undecidable, and guessing would hide a real
  window — so the whole fold is refused. The bound is scoped to that clause because the model legitimately
  holds MORE candidates than the window has tabs while a wid-minting tab switch is in flight (retired wids
  aren't swept yet, generator seed 163).
  A group whose own active tab is still on-screen is LIVE and never adopted: geometry is a guess and must not
  overrule the AX read that linked it. Dropping that clause let an unrelated same-size window annex a tab that
  had merely backgrounded inside another window, hiding a real window (rec10). The test is Space-holding, not
  `newlyDiscovered` — that flag means newly TRACKED, and at launch everything is. The visible parent is a BRAND-NEW active (on-screen, no link yet — a
  just-created tab that took over) else the ESTABLISHED visible (`!isTabbed` **and** holding a Space) — **not**
  any Space-holder: `updateState` backfills the active's Space onto every background tab, so several members
  hold a Space, and picking an arbitrary one flipped which wid the group shows (thumbnail bouncing to the app
  icon and back). A HELD member never wins the pick while an un-held candidate exists (held = the OUTGOING
  tab, and its Space is borrowed — rec14), but stays the last fallback (hysteresis for a mid-gap group whose
  only Space-holder is its held rep). A held member also counts as BACKGROUND despite its borrowed Space —
  the same fact as `matchSiblings`' held leg, patched on both claim paths. If no member is currently the
  visible tab, the group is skipped — the AX paths re-establish it. **`newlyDiscovered`** (the wid this pass discovered) overrides the pick: in fullscreen AX names nothing
  AND a brand-new tab is often momentarily Space-less — indistinguishable from an ungrouped background tab by
  facts alone — so only the caller can say which member just took over. Without it geometry picked the *held*
  old tab and the switcher showed the PREVIOUS tab, then flipped to two tiles.
  **Fullscreen: resolve per SPACE.** Every fullscreen window is SCREEN-sized, so one size-cluster can hold
  several fullscreen windows *plus all their tabs*. The invariant is about each Space, not the cluster: when a
  cluster is fullscreen and spans **several** Spaces it is partitioned, and each Space resolved on its own —
  one window and its tabs. (Asking "does the CLUSTER span ≤1 Space" instead made a second window's tabs each
  get a tile.) A Space-less member can't be attributed to any of them, so it's left to a later pass — which is
  why the partition is skipped when the cluster spans ≤1 Space, the case where attribution IS decidable (a
  brand-new visible is momentarily Space-less and must still fold its old active in).
  **`foldEveryMember`** is the "one Space ⇒ one window" side: every non-visible member is a background tab,
  even one still holding the Space because its 1326 hasn't landed. Off for normal windows (a normal Space is
  shared by many), where only Space-less members are background, so a same-size standalone isn't swept in.
  Output sorted by `visibleWid`.
- **`matchSiblings(active, axTitles, sameAppWindows, activeIsNewlyDiscovered = false) -> SiblingMatch`** —
  resolve the active tab's AXTabGroup titles to tracked windows. The active title is removed once (duplicates
  allowed); each remaining title matches the first compatible, not-yet-matched same-app window that is
  PLAUSIBLY an inactive tab: already `isTabbed`, Space-less, or holding a SYNTHETIC Space — `isHeld` (a
  backgrounding tab mid-swap, rec14's ghost 4th tile) or `spaceIsBorrowed` (a Space COPIED from a sibling by
  the backfill / the representative borrow; rec20's ex-representative, orphaned with the Space we lent it,
  stood as a permanent stray tile). A held/borrowed Space is our annotation, not CGS evidence, so it must not
  count as on-screen protection; both legs are size-gated so a held/borrowed tab of a DIFFERENT same-position
  window isn't claimable across groups. A genuinely on-Space window is never claimed (it's on-screen, so by
  definition not an inactive tab; without this a new same-title window filled a title whose real tab has no
  window, Finder cmd-N). The borrow OUTLIVES the membership that justified it: leaving a group used to strip
  the lent Space, which states "CGS places this window nowhere" — the strong phantom signal — about a window
  nobody had asked CGS about, and hid live ones, seen live. The marker alone keeps an orphaned ex-member from
  looking on-screen, and a genuinely-gone one is turned phantom by the next `spacesSynced`. A GENUINELY-fullscreen candidate is
  ALSO never claimed (the fullscreen Space invariant: it is its own window on its own Space) — switching
  Spaces TO a fullscreen window makes it transiently Space-less, and `positionsCompatible`'s fullscreen
  waiver (there to claim a fullscreen window's frozen NON-fullscreen tabs) would otherwise let a windowed
  group annex the fullscreen WINDOW, whose links geometry's union then bridges into a mega-group hiding real
  windows (rec24c: 10 members, 9 hidden). **Second pass**, only when `activeIsNewlyDiscovered` (this active is
  a window the user JUST CREATED — a new tab that took over its group; newly CREATED, not merely newly
  tracked: at launch every window is newly tracked, and firing there had two real windows sharing a tab title
  swallow each other): fill any still-unmatched title with a
  same-app, same-**size** on-screen sibling too. That sibling is the previous active tab, backgrounding as
  this new tab takes over, whose "removed from Space" event hasn't landed yet — claiming it now groups the
  pair atomically so it doesn't flash as a 2nd tile. Safe because a genuinely separate new window carries its
  OWN AXTabGroup as the active element and never reaches this path (`testOnScreenWindowNeverClaimedAsTab` runs
  with the flag off); still title-gated (coexisting same-app groups keep distinct titles) and bounded by the
  tab count. A window still tabbed into THIS group (`isTabbed` + `tabbedSiblingWids` ∋ active) is then
  **kept** even if no title named it, so a duplicate or renamed title can't flap an inactive tab out (#5830);
  each kept sibling also cancels one `untrackedTitle`. ALSO kept: an on-screen un-tabbed member of this group
  that is MORE RECENTLY FOCUSED than the reading active — AX reads are queued, so a read can land right after
  the user switched to another member, and treating the reader as the active then ejected the REAL active
  from its own group, stranding it as a stray tile that successive stale reads fought over (rec18). Strict
  `<`, so a genuinely-departed window still reaches `toUntabWids`. The whole handover group is also kept while
  the reading active has NO FRAME OF ITS OWN: with the incoming window still 0×0, normalize leaves the
  previous active as the presentable representative, and ejecting that un-tabbed representative flashes a
  second tile during a fast Cmd+T burst (T-02). Keyed on the active's size rather than on `newlyDiscovered`
  alone, because the discovery read and a plain `axMainWindow` read can land in the same millisecond and only
  the first carries the flag (T-12). Returns the group's wids (active first), the
  matched+kept wids, `untrackedTitles` (titles with no window → inactive tabs to discover), and `toUntabWids`
  (windows that were in this group but are no longer tabbed).
  When duplicate titles leave fewer AX slots than compatible tracked windows, an existing member of this
  active's group is matched before an unattached candidate. Otherwise model order can spend the last slot on
  a newly adopted tab and eject the group's visible representative until geometry repairs it (T-01/T-02).
  **Merge All Windows: the tabs never converge on a frame.** "Tabs of one window share its frame" — the premise
  every position rule here rests on — is simply false after Window ▸ Merge All Windows. The merged window is a
  BRAND-NEW wid one cascade step past the last of the windows it absorbed, and those keep the positions they
  had, frozen (no geometry event reaches an ordered-out tab). Measured live in Finder and Terminal alike
  (measured live 2026-07-30; the capture is `terminalMerge4Tabs`): four tabs, one shared SIZE, four positions
  29px apart. So `framePartitions` gave each tab a partition of one, no cluster survived `count > 1`, and no
  merged group could form in any app, ever — the tabs stayed Space-less and un-`isTabbed`, hence PHANTOM, so
  "separate window for each tab" showed 1 tile instead of 4 and three real windows sat exposed to the
  dead-window sweep. That cascade is also exactly the offset the split exists to catch (rec11/rec12), so the two
  requirements genuinely collide on position and are settled with the fact that isn't position:
  `tabCountAccountsForEveryMember` leaves a cluster WHOLE when the visible's AXTabGroup COUNT equals the cluster
  size, because AX has then accounted for every member and no second window can be hiding in it. Two conditions,
  each with teeth:
  - **EXACT equality, never a bound.** One member more than the declared tabs means the cluster holds a non-tab
    and across positions we cannot tell which — rec11 exactly, where AX reported 11 titles for 8 tracked wids
    (Finder destroys a backgrounded tab's window, so titles routinely outnumber wids) and `<=` would have waved
    the whole recording through. Fewer members than tabs is the ordinary mid-discovery state and stays split:
    an unclaimed background tab is hidden either way, and the next read re-decides.
  - **The count must be the ON-SCREEN member's**, and there must be exactly one such member. `tabCount` goes
    stale and a background tab's is stale by construction: only an ACTIVE tab reports an AXTabGroup, and the
    count is deliberately not retired while its window is still in a group (a nil read is transient, and
    retiring on it tore live groups apart). So a window that WAS a 3-tab active keeps `tabCount` 3 after a tab
    is dragged out of it. Live: after Move Tab to New Window, with the drag-out already correctly
    confirmed, that stale 3 "accounted" for a 3-member cluster and geometry folded the torn-out window at
    (290,712) straight back into the group at (1116,683) — `group form g13 members=[72914, 72915, 72910]
    reason=geometry`. Holding a Space did not protect it: its Space was OUR annotation by then (normalize lends
    a group's members one), which is why the test is `hasGenuineSpace` on both counts.
  - **No member spoken for by another group** — every member unlinked, or in ONE group the cluster wholly
    contains. A size cluster routinely holds a SUBSET of each of two windows (a tabbed window's members drift
    apart in size as its tab bar resizes it) and totals one window's tab count by coincidence: generator seed 27
    folded window B's held ex-active into window A, the membership union bridged in the rest, and one group
    spanned two real windows with B showing ZERO tiles. The "geometry never merges two groups" filter did not
    save it — A's active was the most recently focused, so that filter waived itself as a sanctioned takeover,
    an exception written for members that SHARE a frame and worth nothing across positions.
  The waiver stays true of the group it formed, so it doesn't withdraw itself and re-split on the next pass. It
  is position-only: SIZE is what a merge leaves intact, so a differently-sized window is not in the cluster at
  all and no tab count pulls it in. Residual: merging a window that ALREADY had tabs leaves more members than
  the merged window has tabs (the absorbed group's own wids), so exactness refuses it and that shape keeps
  today's split behaviour.
- **The merged active may initially be 0×0.** In that interval it cannot join the absorbed windows' size
  cluster, so `zeroSizedMergeClaim` applies the same exact-count proof on the title path: the active must be
  0×0, its AX count must equal every candidate plus itself, all candidates must be ordered out, and none may
  belong to another visible group. A normally sized active still obeys the strict position rule; the captured
  Terminal merge and `testNoTitleMatchEverClaimsAcrossFrames` pin that boundary. What the claim proves also
  waives the SIZE test on the borrowed/held leg, for the same reason: against a 0×0 active that test can only
  ever fail, and the member it failed on is the one normalize promoted to representative.
- **`positionsCompatible(a, b) -> Bool`** — tabs share their parent's frame. An existing tab link wins (a
  stale position can't split an already-grouped pair). Unknown position or either fullscreen → title-only
  fallback (true). Otherwise positions must match EXACTLY (rounded): macOS cascades new windows by 29px, so
  any tolerance is precisely where a SECOND window lives — a 50px tolerance let two cascaded Finder windows
  swallow each other (rec11). Exact is the safe side of the asymmetry: a missed claim is invisible (an
  unclaimed background tab is hidden anyway), a false claim hides a real window. The link bypass is what
  makes exact affordable.
- **`groupRepresentative(members) -> CGWindowID?`** — which member a group shows: **the most recently FOCUSED
  presentable member**, full stop. Focusing a tab makes it the active tab by definition, so focus
  (`lastFocusOrder`) is the one authoritative signal; every earlier heuristic (un-tabbed Space-holder, then
  the just-backgrounded visible, then focus) approximated it through the derived `isTabbed` and backfilled
  Spaces — circular, and read-order-sensitive exactly when several members look on-screen mid-switch
  (rec18/rec19). Presentable-only (a new tab is 0×0 for ~640ms; handing it the group showed empty pixels,
  rec11 — the outgoing tab keeps the tile until the new one is sized), full-set fallback when nothing is
  presentable. nil ONLY for an incoherent group (members disagreeing on their links).
  `TabGroup.updateState` also asks this kernel (over the pre-mutation facts) which member to pass to
  `TabGroups.form` as representative, so a queued stale read can't displace the member the user is on.
- **`dragOutVerdict(joiner, previousRepresentative) -> Bool?`** — a group member that joined a Space is
  EITHER the group's new active tab (a switch — a pure representative move, no membership churn; the old
  leave-and-rediscover here oscillated the open switcher through several layouts per switch, rec19) or a tab
  DRAGGED OUT to stand alone. Indistinguishable at event time (a dragged tab starts at the parent's frame),
  so the adapter assumes a switch and re-checks this verdict on an interval: nil = joiner's frame not
  settled/known yet (0×0 beat; re-check), false = same frame as the previous representative (switch
  confirmed; stop), true = settled at another frame (it left; remove from the group, which re-picks its
  representative by focus). Judged against the PREVIOUS representative — live on-screen at the join — not
  the other members, whose stored frames go stale (a moved window leaves its background tabs frozen at the
  old frame). Fullscreen excluded: frames are unreliable there and `membersThatLeftGroup` owns fullscreen
  departures. The adapter refreshes both frames from the WindowServer before the first check (the joiner's
  stored position is ~215ms stale after a switch, and a stale frame reads as a drag-out).
  Only a PRESENTABLE member (a usable, non-degenerate size) may represent the group — the OS publishes a new tab
  at 0×0 and sizes it ~640ms later, and that un-renderable tab is otherwise exactly the un-tabbed Space-holder
  the rules prefer, which showed a tile of empty pixels (rec11). Skipping it keeps the outgoing tab — still
  sized and captured — as the tile until the new one can be drawn, so a tab creation never blinks the window it
  spawned on. Falls back to the full set when nothing is presentable (a stale tile beats none).
  **nil** ONLY for an INCOHERENT group — members DISAGREEING on `tabbedSiblingWids` (a wid re-homed into a new
  group while the old group's members still list it); forcing one of those visible spuriously un-hid a
  background tab as a 2nd tile. Note "every member tabbed" is NOT that test: a coherent group whose visible
  got lost must recover (via the focused member), not be abandoned — treating it as stale stranded it hidden.
- **`shouldHoldVisibleThroughDiscovery(isTabbed, becomesSpaceless, hadRecentWindowCreate,
  hadRecentUntrackedSpaceJoin) -> Bool`** — hold a backgrounding tab visible while the incoming tab is
  discovered (~640ms: the OS creates it at 0×0 and sizes it later), so the group never shows ZERO tiles.
  Gated on a REPLACEMENT SIGNAL, which separates "something is coming to take over" from a plain background
  (nothing is → hide normally). Two signals qualify: a recent create (811 — a new tab being made), or a
  recent UNTRACKED window joining the visible Space (rec24: Finder mints a brand-new wid per tab switch and
  emits no create, only that 1325, one beat before the outgoing tab's 1326). A switch between TRACKED tabs
  has neither signal and needs no hold — the representative swap covers it. The timer lives in the adapter;
  this is the decision.
- **`shouldReleaseHold(isTabbed, hasPresentableReplacement, attemptsExhausted) -> Bool`** — the hold's only job
  is "never ZERO tiles for a window mid tab-swap", so it ends once something else can show: the incoming tab
  CLAIMED it (`isTabbed` ⇒ hidden by the tab filter anyway), a replacement is drawable, or the safety cap.
  It once asked `discoveryPending` (`!recentlyCreatedWindows.isEmpty`), which was wrong twice: that set is
  GLOBAL (a Chrome create pinned a Finder tab) and it LEAKED — a burst outruns discovery, so each tab's window
  was created/added/removed while never discovered or focused, and Finder's destroy event never fires, so the
  flag lived forever. The set was then never empty and NO hold released on its own for the rest of the session;
  every one ran the 20s cap, pinning a stale tab as an extra tile (rec13). Observable state can't leak.
- **`hasPresentableReplacement(for:among:) -> Bool`** — is another window ready to take this tile? Same app,
  on-screen, un-tabbed, drawable, at the held tab's own FRAME. Frame, not just size: same-size windows of one
  app are the norm (29px cascade), and releasing because a DIFFERENT window has a tile re-creates the vanish.
  Self-timing, no delay to tune: the OS publishes a new tab at 0×0 and sizes it to the parent's frame ~640ms
  later, so "at my frame and drawable" IS "ready to show" — and a lagging fullscreen tab just isn't ready yet.
- **`membersThatLeftGroup(visible, members) -> [CGWindowID]`** — members that are separate windows still
  carrying a stale `tabbedSiblingWids`, to unlink. FULLSCREEN-only: two fullscreen windows can never share a
  Space, so a fullscreen member holding a Space the fullscreen visible doesn't is its own window (a tab dragged
  out of a fullscreen group — macOS puts it on a brand-new fullscreen Space), and AX exposes no tab titles for
  a fullscreen window to retire the link any other way. Requires the visible to HOLD a Space: a Space-less
  visible proves nothing (against an empty visible Space every member looks disjoint), and it is Space-less
  exactly while mid-transition — judging then unlinked a live group's own tabs and exploded it into a tile per
  tab. Deliberately NOT generalized to "holds a Space the
  visible doesn't": a real background tab's `spaceIds` can be non-empty AND disjoint from its visible's
  (captured live), and un-grouping on that exploded a live Terminal group into one tile per tab. Space-less
  members are never departed — that's exactly what a background tab looks like.
Group SHRINK/DISSOLVE is no longer here. It was `dissolution(siblingWids, leaving, presentWids)`, a resolver
function reading a sibling array plus the set of wids still tracked. The group REGISTRY made both inputs
redundant — membership is the table — so `TabGroupsTable.remove` / `shrinkAfterDetach` owns it: ≤ 1 surviving
member ⇒ dissolve (a single window can't be a tab group), otherwise shrink and re-pick the representative if
it left with the detached members. Section F below still pins the rule, against its new owner.

## Test scenarios

Mirrors `TabGroupResolverTests.swift` 1:1. Helpers build an all-default `TabWindow` and flip only the knobs
each test exercises.

### 0. The handover edge — what the pair decides and geometry cannot

`replacedByWid` / `replacedWid` carry the **Space handover**: a leave and a join on ONE Space, by two wids,
paired within `recentPairingWindow`. It is the same kind of fact as `lastLeftSpaceId` — the events say it
outright, so the projection forwards it unmasked — but strictly stronger where it matters. `lastLeftSpaceId`
names the SPACE left, which identifies a WINDOW only where one window owns a Space: true in fullscreen, false
everywhere else. Two windowed windows of one app SHARE a Space, and Terminal stacks them at the same frame
with the same title, so every Space-based test is true of both at once. The handover names a wid.

Recorded by `WindowEventReducer.recordHandover` from whichever half lands first (the delivery order of two
WindowServer datagrams is not pinned — see the `HandoverOrder` fuzz axis), and deliberately narrow: both wids
tracked and of the same app, not during a Space transition, within the pairing window. A wrong edge would
hide a real window, which is the expensive direction. The cost of "both tracked" is that a MINTED switch
(Finder's brand-new wid, no create event) records no edge — that case keeps its own machinery in
`pendingGroupInheritance`, and rec26 measured the REUSED switch as the normal one.

Written RED before the change, so "it worked" had a definition that predated it:

- **testBackgroundedTabIsNotStolenByAStackedWindowOfTheSameApp** — tab X backgrounds inside window A; before
  A's AXTabGroup read links it, the user clicks stacked window B, which is then the cluster's most recently
  focused member and is elected visible. X (Space-less, same app, same frame, same title) folded in as B's
  tab: a real tab of A hidden under B's tile. `belongsToTheWindowThatReplacedIt` refuses a candidate whose
  successor is present in the cluster and is not the visible.
- **testDragOutIsDecidedByTheMissingLeaveNotTheFrame** — a tab torn out and dropped back over its parent
  starts at the parent's frame, which `dragOutVerdict` read as a tab switch, and finally ("same frame ⇒ stop
  checking"): the window stayed in the group, hidden as a tab of it. Now a join that REPLACED someone is a
  switch (decided from the pair alone, no frame, no waiting), and a join that replaced nobody is a drag-out.
  The second leg needs the pairing window to have ELAPSED, since a 1326 in flight also looks like no 1326 —
  the caller owns that clock (`dragOutCheck` passes `pairingWindowElapsed: attempt > 0`).
- **testAPairedJoinIsATabSwitchWithoutLookingAtFrames** — the other leg, and what makes the first safe: a
  join that DID replace the previous representative is a switch, from the pair alone.
- **testAJoinThatReplacedAnotherWindowsTabIsADragOutFromThisGroup** — a join that replaced SOMEONE ELSE still
  means this tab left the group it is being judged against. The edge is about identity, so it answers both
  directions.

The recording itself is pinned separately in `TestReducerRunnerTests` (`testHandoverIsRecorded…`), both
arrival orders plus the three negatives — cross-app, mid-transition, and outside the pairing window — because
a kernel guard reading a field nothing writes is decoration.

### 0b. Split View — the one exception to the fullscreen Space invariant

*A fullscreen Space holds one window and its tabs* is the invariant every Space-based rule here rests on, and
macOS breaks it on purpose in exactly one place: two windows tiled side by side share a single fullscreen
Space. Measured live (macOS 26, two TextEdit windows via Window ▸ Full-Screen Tile):

    wid 12542  fullscreen=true  frame=(0,36 1022x1116)    spaces=[2267]
    wid 36133  fullscreen=true  frame=(1034,0 1014x1152)  spaces=[2267]

Both hold the Space, so the Space-less rule makes neither background — but the fullscreen fold deliberately
absorbs a member SETTLED on the fold Space, to catch the visible's outgoing tab whose 1326 has not landed.
That is what would swallow a split-view partner and hide a real window. The measured pair happens to differ
in size (one had a toolbar showing) so it never reaches one cluster, but two halves of equal size — two
Finder windows — do.

`isSplitViewPartner` gates it on the ORIGIN: a member genuinely holding the Space at a DIFFERENT origin than
the visible is a separate window. A lagging outgoing tab wears the visible's own frame; split halves sit side
by side and cannot share an origin. Both positions must be known — a brand-new tab is frameless for a beat,
and silence is not a verdict.

- **testSplitViewCapturedGeometryFormsNoGroup** — the measured frames, recorded as the OS produced them.
- **testSplitViewHalvesOfEqualSizeAreNotFoldedTogether** — the hazard the gate exists for (teeth-verified:
  without it, window 2 is folded in as a tab of window 1 and disappears).
- **testFullscreenStillFoldsALaggingTabAtTheSameOrigin** — the fold's own case still works.

### A. geometryGroups

- **testConfirmedVisiblePlusSpacelessIsAGroup** — same app + size, visible holds a Space and carries the
  group's `tabbedSiblingWids` (AX-confirmed), one sibling Space-less → grouped. The tab-switch re-link.
- **testFullscreenVisibleGroupsWithoutAxConfirmation** — visible is fullscreen (no `tabbedSiblingWids`, since
  AX can't read a fullscreen AXTabGroup) + one Space-less sibling → grouped via the fullscreen exemption.
- **testTabCountConfirmsWhenTitlesCannot** — stock Terminal's composed window title (#5785) leaves
  `tabbedSiblingWids` nil forever; the AXTabGroup's COUNT confirms the cluster instead and the tab is grouped.
- **testTabCountRefusesToFoldMoreCandidatesThanTabs** — AX says 2 tabs but two Space-less same-frame
  candidates exist → the whole fold is refused rather than guess which is the intruder and hide a real window.
- **testTabCountBoundDoesNotApplyToAnAlreadyConfirmedCluster** — the bound is scoped to the count clause: an
  AX-confirmed cluster still folds a candidate set wider than the tab count, because a wid-minting tab switch
  in flight leaves retired wids unswept (generator seed 163, the lost thumbnail inheritance).
- **testTabCountKeepsACascadedMergedClusterWhole** — Merge All Windows leaves every tab at its pre-merge cascade
  position, so the position split gave each its own partition and no merged group formed at all (measured live
  2026-07-30). The visible declares as many tabs as the cluster has members, which accounts for all
  of them, so the cascade must not veto the cluster.
- **testAnUnaccountedForMemberRestoresThePositionSplit** — one member more than the declared tabs and position
  goes back to separating windows. Shaped so exactness is the ONLY refusal: the visible is AX-confirmed, which
  is the case that skips the tab-count bound (seed 163), so `<=` here would hide a real window.
- **testAMemberOfAnotherGroupRestoresThePositionSplit** — generator seed 27: the count matched the cluster size
  while the members belonged to TWO windows, and the sanctioned-takeover exception (the visible was the most
  recently focused) let window A annex window B's held ex-active; the union bridged the rest and B showed ZERO
  tiles. A link reaching outside the cluster names a window we can't see here.
- **testMergedClusterStillNeedsTheSizeToMatch** — the waiver is about POSITION only; a same-app window of a
  different size was never in the cluster and no tab count pulls it in.
- **testStaleTabCountAloneDoesNotConfirm** — a window whose tabs are gone reads `tabCount` 0 (the reducer
  retires it on a nil read of an ungrouped window), so it can't keep the gate open.
- **testNormalUnconfirmedNotGrouped** — same app + size, visible is normal and never AX-confirmed, one sibling
  briefly Space-less → **not** grouped. The #5830 fix: geometry alone can't fabricate a group.
- **testTwoVisibleSameSizeNotGrouped** — same app + size but *both* hold a Space (two separate real windows)
  → no group. A real window is never Space-less, so it's never collapsed into a tab.
- **testDifferentSizesNotGrouped** — same app, different sizes → no group.
- **testDifferentAppsNotGrouped** — same size, different pid → no group.
- **testMinimizedSpacelessNotGrouped** — a Space-less *minimized* window is excluded from candidates.
- **testSizelessExcluded** — a window with no size is excluded from candidates.
- **testSingleCandidateNoGroup** — one candidate → no group.
- **testMultipleBackgroundTabsGroupUnderVisible** — one AX-confirmed visible + two Space-less, all same size
  → both backgrounds grouped under the one visible tab.
- **testJoinsExistingGroupWhenBackgroundAlreadyTabbed** — a new visible (no link, not fullscreen) + a
  Space-less background that is ALREADY grouped (`tabbedSiblingWids`) whose group has no other Space-holding
  member → grouped. A new tab joining an existing group whose visible isn't AX-confirmed yet (fullscreen).
- **testDoesNotAdoptATabWhoseGroupStillHasItsVisible** — same shape, except a sibling of the background's group
  still holds a Space → NOT grouped. The group is live; only an orphaned one is up for adoption.
- **testWindowLinkedOnlyToItselfConfirmsNoTabCluster** (real-world, rec8 — in `RealWorldScenariosTests`) — a background linked only to ITSELF
  (`[own wid]`: its AXTabGroup was read but its tabs aren't tracked yet) confirms nothing → NOT grouped.
  `TabWindow.tabbedSiblingWids` non-nil means a real group of ≥ 2; the `TabGroup` adapter never writes a
  self-only link, and the kernel re-checks.
- **testFullscreenFoldsNotYetBackgroundedOldTab** — a new fullscreen tab (visible, fullscreen flag not yet
  set) + the previous active still on the same fullscreen Space → the old one is folded in as background (a
  fullscreen Space holds one window's tabs), so the group is one tile.
- **testTwoSeparateFullscreenWindowsNotMerged** — two same-size fullscreen windows on DIFFERENT Spaces → not
  merged (neither the same-Space fold nor a Space-less background links them).
- **testGeometryPrefersEstablishedVisibleOverBackgroundTab** — several members hold a (backfilled) Space,
  ordered so a tabbed member comes first → the `!isTabbed` member is chosen visible, not the leading tabbed
  one. The hysteresis that stops the group's representative flipping (and its thumbnail flickering).

### B. matchSiblings

- **testMatchesInactiveSiblingByTitle** — active "git" with titles [git, lwouis] + a same-app Space-less
  window "lwouis" → matched; `siblingWids` = [active, lwouis].
- **testNewlyDiscoveredActiveClaimsOnScreenSameSizeSibling** — a brand-new active tab
  (`activeIsNewlyDiscovered`) + a same-app, same-size sibling still on a (stale) Space → the sibling IS
  claimed (its 1326 hasn't landed), grouping the pair atomically so it doesn't flash as a 2nd tile.
- **testNewlyDiscoveredDoesNotClaimDifferentSizeWindow** — same, but the on-screen sibling is a different
  size → not claimed (a separate window, not a backgrounded tab).
- **testNewlyDiscoveredStillTitleGatedAcrossGroups** — the on-screen claim stays title-gated: a same-size
  on-screen window whose title isn't in this active's AXTabGroup (a different same-app group) is left alone.
- **testNotNewlyDiscoveredKeepsOnScreenProtection** — with the flag off (a review / re-read, not a fresh
  discovery) an on-screen same-size same-title window is NOT claimed — the explicit Finder cmd-N contract.
- **testOnScreenWindowNeverClaimedAsTab** — an on-Space, non-tabbed same-title window (Finder cmd-N, close
  position) is NOT claimed as the group's inactive tab; the title is reported untracked instead.
- **testFullscreenWindowIsNeverClaimedAsAWindowedGroupsTab** — rec24c: switching Spaces TO a fullscreen
  window makes it transiently Space-less, so it looks plausible, its shared title matches, and
  `positionsCompatible`'s fullscreen waiver stops the frame test from saving it. The fullscreen Space
  invariant forbids the claim outright: a fullscreen window is its own window on its own Space.
- **testDuplicateTitleRemovedOnce** — titles [git, git] with the active titled "git" + one other "git"
  window → the active title is removed once, the other "git" is matched.
- **testUntrackedTitleReported** — a title with no tracked window → in `untrackedTitles` (to brute-force
  discover), not matched.
- **testStillTabbedSiblingKeptDespiteNoTitle** — a window still tabbed into this group (isTabbed +
  `tabbedSiblingWids` ∋ active) with no matching AX title → **kept** (the #5830 flap fix), not un-tabbed.
- **testDepartedSiblingUntabbedOnceNoLongerTabbed** — once that window's own read clears `isTabbed` (it went
  standalone), the next match un-tabs it (`toUntabWids`), clearing the stale link.
- **testOtherGroupTabsNotUntabbed** — a same-app window in a DIFFERENT group (`tabbedSiblingWids` lacks this
  active) is neither kept nor un-tabbed; coexisting groups of one app don't churn each other.
- **testNonTabbedUnmatchedNotUntabbed** — a same-app window with no tab state and an unmatched title is
  **not** in `toUntabWids` (only windows carrying stale tab state are cleared).
- **testFarPositionNotMatched** — a same-app window with the right title but a far-off position and no
  existing link → not matched; its title is reported untracked.
- **testHeldWindowIsClaimableDespiteHoldingASpace** — a held window with a (borrowed) Space IS claimable:
  held means backgrounding tab mid-swap (rec14's ghost 4th tile).
- **testHeldWindowOfADifferentSizeIsNotClaimable** — the held leg is size-gated: a held tab of a different
  same-position window (Terminal stacks its windows) stays unclaimable across groups.
- **testBorrowedSpaceWindowIsClaimable** / **testBorrowedSpaceMemberCountsAsGeometryBackground** — a Space
  copied onto a window by the tab machinery is not on-screen evidence, on either claim path (rec20).
- **testHeldBackgroundingTabGroupsByGeometryDespiteBorrowedSpace** — the geometry path of the same fact: a
  held member counts as background despite its borrowed Space; both claim paths must agree.
- **testZeroSizedMergeKeepsThePromotedRepresentative** — the size gate on the borrowed leg is waived for a
  member the zero-sized merge claim already proved. After Merge All Windows the merged active is 0x0, so no
  real tab can ever match its size, and the absorbed tab normalize had promoted to representative (un-tabbed,
  holding a lent Space) was ejected from its own group on the next AX read — a second Finder tile that then
  went phantom (measured live, 2026-08-29).
- **testFramelessActiveKeepsThePromotedRepresentative** — the same ejection through the other door: mid
  Cmd+T burst the incoming tab is 0x0, normalize promoted the previous tab to representative (un-tabbed, on
  screen, claimable by no pass), and the read that landed a millisecond behind the discovery one — without
  `activeIsNewlyDiscovered` — untabbed it. The burst drew 3 Finder tiles instead of 2 (measured live,
  2026-08-31).
- **testDynamicTitleMismatchKeepsSibling** — the cause-B flap, now fixed: the active's AXTabGroup reports the
  inactive tab as "B2" (Terminal renamed it) but the tracked window still reads "B1". Title equality fails,
  but the sibling is still tabbed into this group, so it is **kept** (not shown as a separate window) and "B2"
  is **not** reported untracked (we already hold that tab). The #5830 stability fix.

### B2. matchSiblings — the group token

- **testTokenClaimsSiblingNoTitleCanName** — #5785's shape (composed titles name nobody, the tab bar made the
  frames disagree): both windows named the same `AXTabGroup` element, so the sibling is matched anyway. One
  title is still reported untracked, and that is pre-existing accounting, not the token: when an app composes
  tab titles unlike window titles the ACTIVE's own title is absent too, so N titles are shared by N-1
  claimable siblings.
- **testTokenClaimBringsTheSiblingsWholeGroup** — generator seed 18. Only the two most recent tabs had ever
  been read as active, so only they carry a token; `form` is exact-set, so claiming just the one the token
  reached would EJECT the third tab from the group it never left. The claim takes the whole of the group it
  is joining, and un-tabs nobody.
- **testTokenDoesNotClaimAnOnScreenWindow** — a token outlives the read that recorded it, so it can name a
  window since torn out. Outside a creation the on-screen protection stands: hiding a real window is worse
  than failing to group a tab.
- **testNewlyDiscoveredTokenClaimsTheOutgoingTabStillOnItsSpace** — during a creation it IS claimed, the same
  sanctioned atomic claim the size-matched second pass makes, on better evidence: here the frames disagree,
  so only the token can do it.
- **testAbsentTokensAreNotAMatch** — two windows nobody has ever read as a selected tab both have none, and
  must not become siblings by both being unknown (the `nil == nil` trap).
- **testTokenDoesNotClaimAFullscreenWindow** — entering fullscreen REPLACES the element, so a fullscreen
  window never really shares a windowed group's token; the fullscreen Space invariant is stated here too
  rather than assumed.

### C. positionsCompatible

- **testExistingLinkBeatsFarPosition** — `b` already linked to `a` (its `tabbedSiblingWids` contains `a.wid`)
  → compatible even with far-apart positions.
- **testFullscreenFallsBackToTitle** — either window fullscreen → compatible (skip the position check).
- **testUnknownPositionFallsBack** — a missing position → compatible (title-only fallback).
- **testNearbyButNotIdenticalPositionsIncompatible** — 20-30px apart (the cascade offset) → NOT compatible.
  This used to assert the opposite (a 50px tolerance), i.e. it encoded the rec11 bug.
- **testIdenticalPositionsCompatible** — exactly the same rounded position → compatible.
- **testStalePositionNeverSplitsAnAlreadyLinkedPair** — the link bypass: once AX grouped a pair, a stale
  position (Merge All Windows; parent moved while the tab was ordered out) must not split them.
- **testFarPositionsIncompatible** — clearly apart, both positioned, neither fullscreen, no link → not
  compatible.

### D. groupRepresentative

- **testRepresentativeIsTheOnScreenActiveTab** — the `!isTabbed` member holding a Space is the group's tile.
- **testRepresentativePrefersTheMostRecentlyFocusedOnScreenMember** — two on-screen un-tabbed members
  (mid-switch) ⇒ focus decides, not list or read order (rec18).
- **testRepresentativeKeepsTheJustBackgroundedVisible** — mid-swap the visible went Space-less; it is still the
  representative, so the group holds a tile through the discovery gap.
- **testNoRepresentativeForAnIncoherentStaleGroup** — members DISAGREE on their link (a wid re-homed into a new
  group while the old one still lists it) ⇒ nil (never force one visible; that un-hid a background tab as a
  2nd tile).
- **testCoherentGroupThatLostItsVisibleRecoversViaTheFocusedMember** — every member tabbed but links AGREE ⇒
  not stale; the FOCUSED member is the active tab by definition and recovers the group
  (`finderFocusedWindowWronglyTabbed`).
- **testGroupIsNotRepresentedByAnUnrenderableIncomingTab** (real-world, rec11 — in `RealWorldScenariosTests`)
  — a 0×0 incoming tab can't be drawn; the outgoing, still-captured tab keeps the tile.

### D2. dragOutVerdict

Its own subject and its own `// MARK:` in the test file, though it shares section D's question ("which member
does this group show?"): a Space-join is either the group's new active tab or a tab torn out of it.

- **testJoinerAtThePreviousRepresentativesFrameIsATabSwitch** / **testJoinerSettledAtAnotherFrameIsADragOut**
  / **testUnsettledJoinerFrameIsUndecided** — the verdict's three outcomes: same frame ⇒ switch (stop),
  another frame ⇒ it left (remove from the group), frame not settled ⇒ undecided (re-check).
- **testFullscreenJoinIsNeverADragOutHere** — the fullscreen exclusion; frames are unreliable there and
  `membersThatLeftGroup` owns fullscreen departures.
- The two handover-edge legs that beat the frame test entirely are in section 0
  (**testAPairedJoinIsATabSwitchWithoutLookingAtFrames**,
  **testAJoinThatReplacedAnotherWindowsTabIsADragOutFromThisGroup**,
  **testDragOutIsDecidedByTheMissingLeaveNotTheFrame**).

### E. hold-visible through the discovery gap

- **testHoldsBackgroundingTabWhenATabWasJustCreated** — visible + goes Space-less + a create just fired ⇒ hold.
- **testHoldsWhenAMintedTabSwitchAnnouncedItselfViaAnUntrackedSpaceJoin** — the second replacement signal
  (rec24): Finder mints a wid per tab switch and emits no create, only a 1325 onto the visible Space a beat
  before the outgoing tab's 1326. Without this leg the outgoing rep went phantom and the tile vanished ~800ms.
- **testDoesNotHoldOnATrackedTabSwitchOrPlainBackground** — NEITHER signal ⇒ nothing is coming to replace it
  (a switch between TRACKED tabs, which the representative swap covers, or a plain background) ⇒ hide normally.
- **testDoesNotHoldAWindowThatKeepsASpaceOrIsAlreadyATab** — still on a Space ⇒ not backgrounding; already a
  tab ⇒ hidden by the tab filter anyway.
- **testHoldReleasesOnceTheIncomingTabClaimedIt** — `isTabbed` ⇒ release (it's a real background tab now).
- **testHoldPersistsWhileNothingCanReplaceTheTile** — the adaptive part: however long the OS takes, keep the tile.
- **testHoldReleasesOnceAReplacementCanBeShown** — something drawable exists ⇒ the hold's job is done.
- **testReplacementMustBeTheSameWindowsNextTab** — a same-app, same-SIZE window at ANOTHER frame is not a
  replacement (rec13's lesson as a rule): releasing on it leaves this window's group with nothing to show.
- **testAnotherFullscreenWindowIsNotAReplacement** — the frame test proves "same window" only because
  separate windows are cascaded 29px apart, and in FULLSCREEN every window is screen-sized at 0,0. So an
  unrelated fullscreen window on another Space passed as the replacement, released the hold early, and the
  tile went out and came back (rec27). A window SETTLED elsewhere is a different window, whatever its frame.
- **testReplacementIsJudgedAgainstTheSpaceTheHeldTabJustLeft** — and that Space test has to be asked against
  `lastLeftSpaceId`, not `spaceIds`: a held tab is Space-LESS by definition (its 1326 just landed), so the
  first version of the guard compared against an empty list, never fired, and the tile went on vanishing.
- **testReplacementAtTheHeldTabsFrameReleasesIt** — same frame, on-screen, drawable ⇒ release.
- **testUnsizedIncomingTabIsNotYetAReplacement** — a 0×0 incoming tab can't be drawn, so the held tab keeps the
  tile; this is what makes the hold self-timing.
- **testHoldReleasesAtTheSafetyCap** — a wedged discovery can't hold a window visible forever.

### F. dissolution (`TabGroupsTable.remove`, not the resolver)

- **testDissolveWhenOneSurvivor** — group [1, 2], 1 removed → dissolve; the lone survivor is ungrouped too,
  so no group of one can exist for `isTabbed` to misread.
- **testShrinkWhenManySurvive** — group [1, 2, 3], 1 removed → shrink to [2, 3], and since the representative
  left with it, the group re-picks one.
- **testAbsentSurvivorsNotCounted** — group [1, 2, 3] that already lost 3: removing 1 leaves one member →
  dissolve, not shrink.

### F2. the token store (`TabGroupsTable.recordToken`)

- **testNilTokenReadNeverClearsTheStoredOne** — "no token now" is routine for a window that is still a tab
  (not selected, or a fullscreen bar the walk cannot reach), so an absence never clears: same doctrine as nil
  titles, a group shrinks only on a positive signal.
- **testADifferentTokenOverwrites** — a tab dragged into another window's bar keeps its element and its wid
  and reports the DESTINATION's group from then on; overwriting is what stops the old group claiming it.
- **testLeavingAGroupClearsTheToken** / **testDissolvingAGroupClearsEveryToken** — a token must never name a
  window that is no longer in the group, or the next read would drag it back in.

## `lastLeftSpaceId` — history as evidence (2026-07-18)

Every other fact the kernel reads is a snapshot of NOW. That is not always enough: a tab which just
backgrounded inside fullscreen window A and a brand-new tab of fullscreen window B are, at the instant
geometry looks, indistinguishable — both Space-less, same app, both screen-sized, neither linked yet. The
1326 that backgrounded the first one names the Space it left, so `lastLeftSpaceId` (set on a leave, cleared
on a join) carries exactly that, and `settledOnAnotherWindowsSpace` rejects a candidate whose last-left Space
is not one the visible is on.

It is genuine CGS evidence, not an annotation, so — unlike `isHeld` and `spaceIsBorrowed` — the projection
forwards it unmasked. Found by the scenario generator, not by a live capture.

It has since answered two more questions the code had written off as undecidable:

- **Which window does a Space-less member belong to, when a size cluster spans several fullscreen Spaces?**
  `geometryGroups` used to drop those members from every partition ("we can't tell which window it
  backgrounded from"). They go to the Space they just left.
- **Is a candidate replacement really this held tab's next tab?** A held tab's own `spaceIds` is empty by
  definition — its 1326 just landed — so the comparison has to be against the Space it left. Getting this
  wrong made the guard a no-op in precisely the case it existed for (rec27).

Both were live-visible: the first as the tile flashing the app icon, the second as the tile vanishing.

It also guards the TITLE claim path (`belongsToAWindowOnAnotherSpace`): an already-tabbed candidate passes the
plausibility test whatever its Space says — right for this window's own tabs, which carry a borrowed Space
equal to the active's, and wrong for another window's. With duplicate titles a fullscreen active claimed a
windowed window's tab and the membership union merged the two windows. A rule fixed on one claim path has to
be fixed on both; that is now the third time this file has learned it.

## A borrowed membership is never merged with an event

`applySpaceMembershipDelta` used to UNION an incoming 1325 with whatever `spaceIds` the window already had —
including a BORROWED one — and then clear the borrow marker, laundering our own guess into CGS evidence. A
tab that had been lent the windowed Space ended up genuinely on both it and its window's fullscreen Space, so
it read as on-screen and its own group could no longer claim it. A borrowed membership is replaced by the
event, not merged with it.

## Geometry never merges two established groups

Claiming a wid already linked to a group the visible is not in means MERGING TWO GROUPS, and geometry is a
guess that must not overrule the AX or causal link that built them. This is reachable in ordinary use: when a
window's members are all transiently Space-less — a Spaces re-query issued before that window's new active
was tracked lists none of them — its whole group folded into an unrelated fullscreen window sharing the size
cluster, and the window lost its tile.

The exception is the sanctioned takeover: a tab that just became active adopting the group it belongs to.
It is identified by FOCUS, which is already the authoritative "which member is the active tab" signal — the
visible must be the cluster's most recently focused member. `newlyDiscovered` is too narrow a test: one of
the two interleavings in `testFullscreenNewTabRaceBothInterleavingsGroupTheOldActive` has it nil.

## Every member of a group carries its Space

Membership can come from geometry, from AX titles, or from the minted-switch handover, but only geometry used
to backfill the Space onto the members it saw. Members linked by the other two paths stayed Space-less until
some later pass happened to re-run geometry over them — a state that is not a reconcile fixed point, which
the convergence invariant reports. `normalizeGroupVisibility` now backfills every member from the
representative, marked borrowed because it is our inference and not CGS evidence.

### An on-screen window is nobody's background tab (#5954)

Geometry infers a background tab from Space-lessness, and Space-lessness lies whenever our own Space data is
wrong. The WindowServer's ordered-in bit settles it, and the two facts were measured against a real macOS tab
group on macOS 26: a background tab reads ordered-OUT, `spaceTypeMask` 0, and no CGS Space, while its selected
sibling and an unrelated window both read ordered-IN with a Space. So a member that reads Space-less while the
WindowServer still shows it on screen is a real window whose membership we lost, never somebody's tab, and
`TabWindow.isOrderedIn` is forwarded to both fold paths to refuse exactly those.

The reporter's case: four Firefox windows at one frame, one entering fullscreen, three folded behind it, so
the switcher showed one of the four and rotated which one. Firefox exposes no `AXTabGroup` (probed live), so
the fullscreen clause was the only confirmation available and no AX read could ever dissolve the result.

- **testOnScreenWindowsAreNotFoldedIntoAFullscreenNewcomer** — the reporter's four windows: no group forms.
- **testAnOrderedOutTabIsStillFoldedIntoItsFullscreenWindow** — the genuine tab, ordered out and Space-less,
  still folds; the bit is read alongside the Space, not instead of it.
