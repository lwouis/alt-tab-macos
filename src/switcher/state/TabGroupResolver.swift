import CoreGraphics

/// The window facts tab-grouping decisions need, lifted off the `Window` class into a flat,
/// test-constructible record — the tab-grouping analogue of `WindowState` (which omits `pid` / `wid` /
/// `size` / `position` / `tabbedSiblingWids`, all of which live on `Window` and all of which grouping
/// reads). Primitive types only (`CGWindowID` / `CGSize` / `CGPoint` / `UInt64`), so the kernel and its
/// tests compile without `Spaces` / SkyLight / the `Window` graph. The impure `TabGroup` adapter maps
/// `Window` ⇄ `TabWindow`, calls the kernel, and applies the decisions back onto the live model.
struct TabWindow: Equatable {
    var pid: pid_t
    var wid: CGWindowID
    var size: CGSize?
    var position: CGPoint?
    var spaceIds: [UInt64]                  // CGSSpaceID === UInt64
    var title: String
    var isTabbed: Bool
    var isFullscreen: Bool
    var isMinimized: Bool
    /// The group this window belongs to, or nil if it's in none. INVARIANT: non-nil ⇒ ≥ 2 members. A group of
    /// one is not a group — it merely says an AXTabGroup was read whose other tabs aren't tracked yet, and
    /// callers read non-nil as "AX-CONFIRMED tab cluster" (see `geometryGroups`). The `TabGroup` adapter keeps
    /// this on write; the kernel re-checks rather than assume.
    var tabbedSiblingWids: [CGWindowID]?
    /// Held visible through the new-tab discovery gap (`windowsHeldVisibleForTab`): this window just
    /// backgrounded as a new tab took over. The hold is KNOWLEDGE the claim rules must see: the adapter
    /// borrows a Space back onto a held tab so its tile can't vanish, which makes its `spaceIds` lie about
    /// being on-screen — without this fact the on-screen protection rejected the incoming tab's claim and
    /// the held tab stood as a ghost standalone tile until a later re-read (rec14).
    var isHeld: Bool = false
    /// `spaceIds` was COPIED from a tab sibling (backfill onto a background tab; the borrow onto a
    /// representative that backgrounded) — OUR annotation, not CGS evidence. Like `isHeld`, every rule that
    /// reads "holds a Space" as "genuinely on-screen" must see it: a brand-new active's claim rejected its
    /// group's ex-representative because of the Space WE lent it, orphaning it as a permanent stray tile (rec20).
    var spaceIsBorrowed: Bool = false
    /// The WindowServer says this window is ON SCREEN right now (its ordered-in bit). Genuine OS evidence,
    /// forwarded rather than masked. It is the one fact that separates a background TAB from a window that
    /// merely lost its Space membership — measured on macOS 26 against a real tab group: the background tab
    /// reads ordered-OUT, `spaceTypeMask` 0, no CGS Space; its selected sibling and an unrelated window both
    /// read ordered-IN with a Space. Defaults false ("not known to be on screen"), the reading that leaves
    /// every existing decision unchanged.
    var isOrderedIn = false
    /// MRU position (0 = most recently focused). The AUTHORITATIVE signal for which member of a group is its
    /// active tab: focusing a tab makes it active, by definition. `isTabbed` can't answer that — it's the
    /// thing tab detection derives, so trusting it to pick the visible is circular.
    var lastFocusOrder: Int = 0
    /// The Space this window most recently LEFT (a 1326 names it), nil once it joins one again. The only
    /// fact separating a tab that just backgrounded inside ANOTHER window from a brand-new tab of this one —
    /// see `settledOnAnotherWindowsSpace`.
    var lastLeftSpaceId: UInt64?
    /// **The handover edge** — the wid that took this window's place on the Space it just left (its 1326
    /// paired with that wid's 1325 on the same Space). Where `lastLeftSpaceId` names the SPACE, this names
    /// the WINDOW, which is what separates two windows SHARING a Space: stacked Terminal windows are
    /// identical on frame, app, title and Space, and the only asymmetry left is who handed over to whom.
    /// See `belongsToTheWindowThatReplacedIt`.
    var replacedByWid: CGWindowID?
    /// The other end of that edge: the wid THIS window replaced on the Space it just joined. A join that
    /// replaced someone is a tab SWITCH; a join that replaced nobody is a tab dragged OUT. See
    /// `dragOutVerdict`, which needed a frame comparison to guess at this and got it wrong whenever the tab
    /// was dropped back over its parent.
    var replacedWid: CGWindowID?
    /// How many tabs the window's own AXTabGroup last reported (0 = none read, or not tabbed). The ONE tab
    /// fact macOS states reliably: the AXTabGroup's presence means tabbed and its button count is exact.
    /// Only the per-tab TITLES are unreliable: an app may
    /// compose its window title from more than its tab label, which is what stock Terminal does and what
    /// left #5785's groups unformable. So the count is what confirms a geometry cluster when titles can't
    /// (`geometryGroups`), and what BOUNDS it: a fold wider than the count is over-claiming by construction.
    var tabCount = 0
    /// The `AXTabGroup` element this window named on its last read as the selected tab (see `TabGroupToken`).
    /// The only membership fact here the OS states outright: titles and frames are inferences ABOUT a group,
    /// this IS the group. nil for a window we have never read as a selected tab, which is most of them.
    var tabGroupToken: TabGroupToken?
}

/// A tab group inferred purely from geometry (no AX): the visible tab (holds a Space) plus the
/// background tabs (Space-less) that share its app + size.
struct GeometryGroup: Equatable {
    var visibleWid: CGWindowID
    var backgroundWids: [CGWindowID]
    var siblingWids: [CGWindowID] { [visibleWid] + backgroundWids }
}

/// The outcome of matching an active tab's AXTabGroup titles to tracked windows.
struct SiblingMatch: Equatable {
    /// the group's wids, active first then matched, in AX title order
    var siblingWids: [CGWindowID]
    /// the windows we matched as inactive tabs (subset of `siblingWids`, active excluded)
    var matchedWids: [CGWindowID]
    /// AXTabGroup titles with no tracked window — inactive tabs to brute-force-discover
    var untrackedTitles: [String]
    /// same-app windows no longer in this group whose stale tab state must be cleared
    var toUntabWids: [CGWindowID]
}

/// Pure decisions behind OS-tab detection, extracted from `TabGroup` so the brittle parts — the
/// geometry inference and the AX-title sibling matching (the documented "match tabs to windows by title"
/// limitation) — are unit-testable without the `Window`
/// graph. The `TabGroup` adapter owns the `Windows.list` reads/writes; this kernel only decides. See
/// `TabGroupResolverSpecs.md`.
///
/// **Two claim paths, one rule set.** A group can be claimed by TITLES (`matchSiblings`) or by GEOMETRY
/// (`resolveGroup`). They are separate code paths over the same facts, so a rule fixed on one is still
/// broken on the other. Every guard below that exists on both says so; when you add one, add it twice.
enum TabGroupResolver {
    /// **The fullscreen Space invariant**, which every Space-based decision below rests on: *a fullscreen Space
    /// holds exactly ONE window and its tabs.* Within a same-app, same-size cluster that means:
    /// - spanning **≤ 1** Space ⇒ it is one window ⇒ every other member is one of its tabs;
    /// - spanning **≥ 2** Spaces ⇒ these are separate fullscreen windows (a tab dragged out gets its own new
    ///   Space), and the ones off the visible's Space have left the group.
    ///
    /// **Precondition — a window's Space membership is evidence ONLY when it names exactly ONE Space.**
    /// - **None**: a tab is Space-less while backgrounded, and a brand-new tab is Space-less for a beat.
    /// - **Several**: it is mid Space-transition — switching between two fullscreen windows briefly reports
    ///   BOTH Spaces on every window (captured: `sp[4310, 4305]`) — or it is an on-all-Spaces window.
    ///
    /// Either way its Space says nothing, and silence must never be read as a verdict. Above all an unsettled
    /// *visible* makes every "compare to the visible's Space" test degenerate — everything looks disjoint from
    /// nothing — and the visible is unsettled exactly while mid-transition, i.e. when we know least. Four
    /// separate bugs were each a rule rediscovering this the hard way (the switcher showing the previous tab;
    /// a fold that matched nothing; a group unlinking its own tabs into a tile per tab; a second fullscreen
    /// window folded into the first and hidden). Hence it is stated once here, and each rule below says which
    /// side of it it needs.
    private static func settledSpace(_ window: TabWindow) -> UInt64? {
        window.spaceIds.count == 1 ? window.spaceIds.first : nil
    }

    /// The distinct Spaces a set of windows is SETTLED on; unsettled members contribute nothing (see above).
    private static func spacesSpanned(_ windows: [TabWindow]) -> Set<UInt64> {
        Set(windows.compactMap { settledSpace($0) })
    }

    /// **The rec14/rec20 rule, stated ONCE for both claim paths.** A window's Space is our own annotation, not
    /// CGS evidence, when it was LENT (`spaceIsBorrowed` — backfilled onto a background tab, or borrowed onto a
    /// representative that backgrounded mid-swap) or FORCED (`isHeld` — kept drawable through the discovery
    /// gap). Reading such a Space as "genuinely on-screen" is what stranded real group members as ghost tiles.
    /// Neither claim path reads `isHeld`/`spaceIsBorrowed` inline; both go through these three, so the rule
    /// cannot be fixed on one path and left broken on the other.
    private static func spaceIsOurAnnotation(_ window: TabWindow) -> Bool {
        window.isHeld || window.spaceIsBorrowed
    }

    /// Does this window hold a Space that is GENUINE on-screen evidence (has one, and it isn't our annotation)?
    private static func hasGenuineSpace(_ window: TabWindow) -> Bool {
        !window.spaceIds.isEmpty && !spaceIsOurAnnotation(window)
    }

    /// The single Space this window is genuinely, settledly on — `settledSpace` gated by the annotation rule,
    /// so a held/borrowed Space never passes as a settled home. nil when Space-less, unsettled, or annotated.
    private static func genuineSettledSpace(_ window: TabWindow) -> UInt64? {
        spaceIsOurAnnotation(window) ? nil : settledSpace(window)
    }

    /// Within one app, windows sharing an exact size are tabs of a single window; the visible tab keeps
    /// its Space while background tabs are Space-less (CGS lists no background tab on any Space). A
    /// SEPARATE real window is never Space-less, so it can't be mistaken for a background tab. Key on
    /// app + SIZE, not the full frame: a background tab's POSITION goes stale while it's ordered out (no
    /// geometry event), so a position key would never match it. Minimized / size-less windows are out.
    /// Result is sorted by `visibleWid` for deterministic output.
    /// `newlyDiscovered` is the wid of a window discovered in THIS pass, if any — a brand-new tab that just
    /// took over its group. It is the only reliable way to know which same-frame member is the new active:
    /// a brand-new tab can be momentarily Space-less AND un-linked, which is indistinguishable from an
    /// ungrouped background tab by facts alone (captured live: `fullscreenFinderAddTabNewTab`, where the new
    /// tab was Space-less while the OLD one was held with a borrowed Space, so the visible-pick chose the old
    /// one and the switcher showed the previous tab).
    static func geometryGroups(_ windows: [TabWindow], newlyDiscovered: CGWindowID? = nil) -> [GeometryGroup] {
        let candidates = windows.filter { !$0.isMinimized && $0.size != nil }
        guard candidates.count > 1 else { return [] }
        var groups = [GeometryGroup]()
        let clusters = Dictionary(grouping: candidates, by: { sizeKey($0) }).values.flatMap { framePartitions($0) }
        for cluster in clusters where cluster.count > 1 {
            let spaces = spacesSpanned(cluster)
            // EVERY fullscreen window is screen-sized, so one size-cluster can hold SEVERAL fullscreen windows
            // (plus all their tabs). The invariant is about each SPACE, not the cluster: resolve each Space on
            // its own — one window and its tabs. Without this partition the cluster spanned 2 Spaces, the fold
            // bailed, and a second fullscreen window's tabs each got their own tile.
            // A Space-less member goes to the Space it just LEFT. This used to be undecidable here — "we
            // can't tell which window it backgrounded from" — so such members were dropped from every
            // partition and left to a later pass. That silently cost the handover: opening a tab in one of
            // two fullscreen windows leaves the outgoing tab Space-less, and with it dropped, the incoming
            // tab formed no group, inherited no thumbnail from it, and the tile flashed the app ICON before
            // its own capture landed (rec27, reported as "screenshot → app icon → screenshot"). `lastLeftSpaceId`
            // is exactly the missing attribution: the 1326 named the Space.
            if cluster.contains(where: { $0.isFullscreen }) && spaces.count > 1 {
                for space in spaces.sorted() {
                    if let g = resolveGroup(cluster.filter {
                                                settledSpace($0) == space
                                                    || ($0.spaceIds.isEmpty && $0.lastLeftSpaceId == space)
                                            },
                                            newlyDiscovered: newlyDiscovered, foldEveryMember: true) {
                        groups.append(g)
                    }
                }
                continue
            }
            // Fold only when exactly ONE Space is settled — that names the one window. With none settled
            // nothing is attributable (mid Space-transition), so fall back to the plain Space-less rule and
            // leave existing links alone rather than folding separate windows together.
            if let g = resolveGroup(cluster, newlyDiscovered: newlyDiscovered,
                                    foldEveryMember: cluster.contains { $0.isFullscreen } && spaces.count == 1) {
                groups.append(g)
            }
        }
        return groups.sorted { $0.visibleWid < $1.visibleWid }
    }

    /// Split a same-app, same-SIZE cluster by POSITION, so two windows that merely share a size stay apart.
    /// Tabs of one window are their parent's frame, so they agree on it exactly; macOS cascades new windows by
    /// 29px, and without this split two Finder windows at the default 920×436 were one cluster and the first
    /// annexed every tab of the second the moment they went Space-less mid-burst — the second window lost all
    /// its members and its tile vanished (rec12).
    ///
    /// A cluster with ANY fullscreen member is left WHOLE: a fullscreen window's tabs can't share its frame
    /// (their position freezes at the pre-fullscreen origin), and a new tab's own `isFullscreen` flag LAGS
    /// discovery — so the flag is only trustworthy across the cluster, never per window, and splitting on
    /// position would strand the lagging tab in its own partition. Two fullscreen windows are separated by the
    /// per-Space partition instead: they hold different Spaces.
    ///
    /// A cluster the AX TAB COUNT fully accounts for is ALSO left whole — see `tabCountAccountsForEveryMember`.
    private static func framePartitions(_ cluster: [TabWindow]) -> [[TabWindow]] {
        guard !cluster.contains(where: { $0.isFullscreen }) else { return [cluster] }
        guard !tabCountAccountsForEveryMember(cluster) else { return [cluster] }
        return Dictionary(grouping: cluster) { (w: TabWindow) -> String in
            guard let p = w.position else { return "-" }
            return "\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
        }.values.map { $0 }
    }

    /// **"Tabs of one window share its frame" is FALSE after Merge All Windows** — the second half of the
    /// premise this whole file's position reasoning rests on, and the OS simply does not honour it. Window ▸
    /// Merge All Windows folds N windows into one tabbed window and never converges their frames: the merged
    /// window is a BRAND-NEW wid one cascade step past the last of them, and the absorbed windows keep the
    /// positions they had, frozen (no geometry event ever reaches an ordered-out tab). Measured live, Finder
    /// and Terminal alike (2026-07-30 QA — the capture is `terminalMerge4Tabs`):
    ///
    ///     +0:Terminal#65640(F) sp=[3] 757x543@942,277   ← the merged window
    ///     -1:Terminal#65637(p) sp=[]  757x543@913,248   ← the absorbed ones, frames frozen 29px apart
    ///     -2:Terminal#65632(p) sp=[]  757x543@884,219
    ///     -3:Terminal#65628(p) sp=[]  757x543@855,190
    ///
    /// So the position split put each tab in a partition of ONE, no cluster survived `count > 1`, and no merged
    /// group could form — ever, in any app, for as long as the window lived. The tabs stayed Space-less,
    /// un-`isTabbed` and therefore PHANTOM: with "separate window for each tab" the user saw one tile instead
    /// of four, and the three real tabs were exposed to the dead-window sweep.
    ///
    /// The cascade is also, exactly, the offset the split exists to catch (rec11/rec12: two Finder windows one
    /// 29px step apart, both at the default 920×436, every tab titled "lwouis", mutually claimable on every
    /// other fact we had). The two requirements genuinely collide on position, so this is settled with the fact
    /// that ISN'T position: the visible's own AXTabGroup COUNT, the half of the AX read that is never in doubt.
    /// When it equals the cluster size, AX has accounted for every member and there is no room left for a
    /// second window — which is the only thing position was protecting.
    ///
    /// **EXACT equality, never a bound.** One member more than the declared tabs means the cluster holds
    /// something that is not our tab, and across positions we can no longer tell which — the very situation
    /// rec11 was: AX reported 11 titles for 8 tracked wids (Finder destroys a backgrounded tab's window, so
    /// titles routinely outnumber wids), so `<=` would have waved that whole recording through and hidden a
    /// real window. Fewer members than tabs is the ordinary mid-discovery state and stays split too: nothing is
    /// lost by waiting, since an unclaimed background tab is hidden either way, and the next read re-decides.
    ///
    /// **And no member may be spoken for by another group**, which the count alone does not imply: a cluster's
    /// size can match one window's tab count while its members belong to TWO windows. The sizes of a tabbed
    /// window's members diverge as its tab bar resizes it, so a size cluster routinely holds a SUBSET of each of
    /// two windows and totals the tab count of one by coincidence. Generator seed 27 (window A with 3 tabs,
    /// window B with 2): the cluster {A's active, B's held ex-active} is two members against A's declared 2, and
    /// A's active — the most recently focused, so the "geometry never merges two groups" filter waived itself as
    /// a sanctioned takeover — claimed B's member. The membership union bridged in the rest and ONE group
    /// spanned both real windows, so B showed ZERO tiles.
    ///
    /// So every member must be either unlinked or in ONE group the cluster wholly contains. That is exactly
    /// what a merge leaves — the absorbed windows are plain ungrouped windows — and it stays true of the merged
    /// group afterwards, so the waiver doesn't withdraw itself on the next pass and re-split what it formed. A
    /// link reaching OUTSIDE the cluster names a window we cannot see here, and the sanctioned-takeover
    /// exception cannot be trusted across positions: it was written for members that share a frame, where the
    /// focused visible really is the group's new active tab.
    ///
    /// **And the count must be the ON-SCREEN member's**, not just any member's, because `tabCount` goes STALE
    /// and a background tab's is stale by construction. Only an ACTIVE tab reports an AXTabGroup at all, so
    /// only the member that is genuinely on screen has a count that describes THIS cluster — and the count is
    /// deliberately not retired while its window is still in a group (a nil read is transient, an active
    /// reports no AXTabGroup for a beat mid-switch, and retiring on it tore live groups apart). So a window
    /// that WAS a 3-tab active keeps `tabCount` 3 forever after a tab is dragged out of it.
    ///
    /// Measured live (2026-07-30): Window ▸ Move Tab to New Window, drag-out correctly confirmed, and
    /// then geometry put the torn-out window straight back — `group form g13 members=[72914, 72915, 72910]
    /// reason=geometry`, folding the window at (290,712) into the group at (1116,683) it had just left. The
    /// cluster had three members and 72915's stale 3 "accounted" for them; the genuine on-screen member 72914
    /// read 2. Note 72915 was NOT protected by holding a Space: its Space was OUR annotation by then (the
    /// borrow normalize lends a group's members), which is exactly why the on-screen test has to be
    /// `hasGenuineSpace` and why "some member's count" was the wrong quantifier rather than a near miss.
    ///
    /// Requiring exactly one such member is the same fact from the other side: a separate real window is never
    /// Space-less (`testTwoVisibleSameSizeNotGrouped`), so a second genuine holder is a second window. A merged
    /// group has exactly one — the merged window holds the Space, every absorbed tab is Space-less.
    ///
    /// Both guards are needed and neither subsumes the other: seed 27's genuine holder DOES declare the
    /// cluster's size, and only the link clause refuses it.
    ///
    /// **And no OTHER member may declare an AXTabGroup of its own from another position**, which is a third
    /// way for the count to be a coincidence rather than an account. Only an active tab reports an AXTabGroup,
    /// so a member that has one is a second tabbed window's active tab, and the two windows' tab counts are
    /// routinely equal — QA T-20 parks two Finder windows of the same size, 3 tabs each. The moment the top
    /// window switched a tab its outgoing active went Space-less and held, which left the bottom window as the
    /// cluster's only genuine holder: {bottom's active, bottom's one discovered tab, top's held ex-active} is
    /// 3 members against the bottom's declared 3, nothing was linked yet, and the waiver handed the top
    /// window's active straight to the bottom window's group. Every Finder window is titled "lwouis", so the
    /// title path then matched across the merged group too and one tile stood for both windows (measured
    /// 2026-09-10). A merge is untouched: the windows it absorbs were plain untabbed windows, so their count
    /// is 0. So is an ordinary tab swap — the held outgoing tab sits at its successor's position, which is the
    /// position this clause reads. And a member ALREADY LINKED into the cluster is untouched too, so the
    /// waiver still does not withdraw itself from the group it formed once its tabs start reporting counts of
    /// their own.
    private static func tabCountAccountsForEveryMember(_ cluster: [TabWindow]) -> Bool {
        let onScreen = cluster.filter { hasGenuineSpace($0) }
        guard onScreen.count == 1, onScreen[0].tabCount == cluster.count else { return false }
        guard !cluster.contains(where: { isAnotherWindowsActiveTab($0, onScreen[0]) }) else { return false }
        let wids = Set(cluster.map { $0.wid })
        var groups = Set<Set<CGWindowID>>()
        for member in cluster {
            guard let links = member.tabbedSiblingWids else { continue }
            guard Set(links).isSubset(of: wids) else { return false }
            groups.insert(Set(links))
        }
        return groups.count <= 1
    }

    /// Reports its own AXTabGroup, sits somewhere else, and belongs to no group here: a second tabbed
    /// window's active tab, whatever the count says. Unlinked is what keeps this from re-splitting a group
    /// the waiver already formed, and the position test is what keeps it off an ordinary swap's held tab.
    private static func isAnotherWindowsActiveTab(_ member: TabWindow, _ onScreen: TabWindow) -> Bool {
        guard member.wid != onScreen.wid, member.tabCount > 0, member.tabbedSiblingWids == nil,
              let mine = member.position, let theirs = onScreen.position else { return false }
        return !samePosition(mine, theirs)
    }

    /// The ONE definition of "same position" every claim path shares (rounded, exact). Tabs of one window
    /// are their parent's frame, so any offset means a different window — see `positionsCompatible` for the
    /// asymmetry that makes exact the safe side. Both claim paths (titles and geometry) and the hold-release
    /// test must agree on this, or a theft fixed on one path survives on the other.
    private static func samePosition(_ a: CGPoint, _ b: CGPoint) -> Bool {
        Int(a.x.rounded()) == Int(b.x.rounded()) && Int(a.y.rounded()) == Int(b.y.rounded())
    }

    /// Resolve ONE window's members into a group: pick the visible tab, treat the rest as its background tabs.
    /// `foldEveryMember` is the fullscreen invariant's "one Space ⇒ one window" side — every other member is a
    /// tab of it, even one still holding the Space because its 1326 hasn't landed. Off (a normal Space is
    /// shared by many windows), only Space-less members are background, so a same-size standalone isn't swept in.
    private static func resolveGroup(_ members: [TabWindow], newlyDiscovered: CGWindowID?,
                                     foldEveryMember: Bool) -> GeometryGroup? {
        guard members.count > 1 else { return nil }
        // The visible is the tab that just took over if this pass discovered one — even if still Space-less,
        // since a brand-new tab often is for a beat (only the caller knows it's new; by facts alone it looks
        // like an ungrouped background tab). Else the established visible: hysteresis, so we don't flip to a
        // background tab that merely also holds a backfilled Space (which flickered the group's thumbnail).
        // If no member is the visible tab, skip — the AX paths re-establish it.
        // A HELD or BORROWED-Space member never wins the pick while a genuine candidate exists: held means
        // "the outgoing tab, kept drawable through the swap" — the exact opposite of the new active — and a
        // held/borrowed Space is our annotation, not evidence of being on-screen (rec14/rec20). They stay
        // eligible as the LAST fallback so a mid-gap group whose only Space-holder is its held rep keeps its
        // established visible (hysteresis).
        let onScreen = members.filter { !$0.isTabbed && !$0.spaceIds.isEmpty }
        guard let visible = members.first(where: { $0.wid == newlyDiscovered && !$0.isTabbed })
                ?? onScreen.first(where: { $0.tabbedSiblingWids == nil && hasGenuineSpace($0) })
                ?? onScreen.first(where: { hasGenuineSpace($0) })
                ?? onScreen.first else { return nil }
        // A HELD or BORROWED-Space member counts as background despite the Space it shows — the shared
        // `hasGenuineSpace` rule, the same one `matchSiblings` reads on the title path.
        //
        // ...but a member the WindowServer still shows ON SCREEN is not anybody's background tab, whatever
        // its Space membership says. A real background tab is ordered OUT — the OS draws one tab of a tabbed
        // window, never two — so an ordered-IN member that merely reads Space-less is a real window whose
        // membership we lost, and folding it hides a window the user is looking at (#5954: four same-frame
        // Firefox windows, one entering fullscreen, three folded behind it). Space-lessness and this bit
        // disagree only when our Space data is wrong, so believe the WindowServer.
        var background = members.filter { !hasGenuineSpace($0) && !$0.isOrderedIn && $0.wid != visible.wid }
        // An UNSETTLED visible (2+ Spaces — mid-transition) may not fold anything. Folding says "every other
        // member is a tab of the window the visible belongs to", which is a claim ABOUT THE VISIBLE'S SPACE —
        // and an unsettled window has no Space that is evidence (the precondition at the top of this file).
        // A Space-LESS visible still folds: that is the brand-new tab case, and the fold takes its Space from
        // the members. Without this, entering fullscreen on a SECOND window — whose wid transiently holds
        // both its old and new Space — folded the FIRST fullscreen window's whole group, genuine active
        // included, into the newcomer: one group spanning two real windows, the rest hidden behind one tile
        // (rec26 live capture: a 14-member group; reproduced as
        // `testSecondFullscreenWindowNeverSwallowsTheFirstsGroup`). Note this is the MIRROR of the guard
        // below — that one stops an unsettled MEMBER being folded in, this one stops an unsettled VISIBLE
        // folding others; both follow from the same "silence is not a verdict" rule.
        if foldEveryMember && visible.spaceIds.count <= 1 {
            // Fold the remaining members as tabs of the one window on this fullscreen Space — but NOT a
            // member that is itself SETTLED on a DIFFERENT Space, nor one UNSETTLED (transitioning to its
            // own Space). The fullscreen invariant is "one Space, one window": a member Space-less (a
            // backgrounded tab) or settled on THIS Space is plausibly its tab; anything else is a SEPARATE
            // fullscreen window. `foldSpace` is the cluster's single settled Space (the caller only folds
            // when exactly one is settled — the visible itself may be a brand-new Space-less tab, so we take
            // it from the members, not the visible). Without this guard a second fullscreen window
            // mid-transition — transiently holding both its old and new Space (UNSETTLED, so contributing
            // nothing to `spacesSpanned`, so this single-Space branch runs) — was folded into the first as a
            // tab (generative simulator, seed 3: two fullscreen windows of one app merged on enter-fullscreen).
            let foldSpace = members.compactMap { settledSpace($0) }.first
            for m in members where m.wid != visible.wid && !background.contains(where: { $0.wid == m.wid })
                && (m.spaceIds.isEmpty || settledSpace(m) == foldSpace)
                && !m.isOrderedIn  // the same rule as above: an on-screen window is nobody's background tab
                && !isSplitViewPartner(m, visible: visible) {
                background.append(m)
            }
        }
        // Never claim a tab whose own window is demonstrably on ANOTHER Space. `isOrphanedTab` below makes
        // the same point for the CONFIRMATION gate, but that gate is bypassed whenever any member is
        // fullscreen — which is how a second fullscreen window annexed the first's tabs and, through the
        // membership union, its active too (rec26 live capture: a 14-member group across two real windows,
        // reproduced as `testSecondFullscreenWindowNeverSwallowsTheFirstsGroup`).
        background = background.filter { !settledOnAnotherWindowsSpace($0, among: members, visible: visible) }
        // ...nor a tab whose SUCCESSOR is standing right here. This is the same "it belongs to another
        // window" rule as the line above, but keyed on the handover rather than the Space — and it reaches
        // the case that one cannot, where the two windows SHARE a Space (see `belongsToTheWindowThatReplacedIt`).
        background = background.filter { !belongsToTheWindowThatReplacedIt($0, among: members, visible: visible) }
        // Never absorb a member of ANOTHER established group. Claiming a wid already linked to a group the
        // visible is not in means MERGING TWO GROUPS, and geometry is a guess that must not overrule the AX
        // or causal link that built them. This happens whenever the other window's members are all
        // transiently Space-less — a Spaces re-query issued before that window's new active was tracked
        // lists none of them — which is ordinary; its whole group then folded into an unrelated fullscreen
        // window (generator seed 94).
        //
        // EXCEPT when the visible is the cluster's most recently FOCUSED member: that is the sanctioned
        // takeover, a tab that just became active adopting the group it belongs to. Focus is already the
        // authoritative "which member is the active tab" signal (`groupRepresentative`), and it is what
        // separates the two cases. `newlyDiscovered` is too narrow a test — one of the two interleavings in
        // `testFullscreenNewTabRaceBothInterleavingsGroupTheOldActive` has it nil.
        let visibleJustFocused = !members.contains { $0.lastFocusOrder < visible.lastFocusOrder }
        if !visibleJustFocused {
            background = background.filter { m in
                // An UNGROUPED member is not covered by the link test below (it has no links to compare), and
                // waving it through handed a real window to an unrelated neighbour: switching a tab in the
                // front Finder window left it Space-less and held, the OTHER window's stale-by-luck tab count
                // waived the position split, and geometry folded the switching window in as a background tab.
                // It stopped being drawn and the summon 15ms later was one tile short (live 2026-08-02,
                // `testASwitchingWindowIsNotFoldedIntoTheNeighbourItOutranksInMru`).
                //
                // MRU is what separates it, the same authority the `visibleJustFocused` test itself rests on:
                // a member focused MORE recently than the visible cannot be a background tab of it. Gated on a
                // DIFFERENT position so the ordinary new-tab swap still folds — there the outgoing tab shares
                // its successor's frame, and it legitimately outranks a successor that has not been focused
                // yet (`discoveryLanded` bumps the newcomer's MRU only once the AX read lands).
                if m.lastFocusOrder < visible.lastFocusOrder, let mp = m.position, let vp = visible.position,
                   !samePosition(mp, vp) { return false }
                guard let links = m.tabbedSiblingWids, links.count > 1 else { return true }
                return links.contains(visible.wid)
            }
        }
        guard !background.isEmpty else { return nil }
        // Only geometry-group a CONFIRMED tab cluster. Geometry alone is not enough to CREATE a group:
        // separate windows of one app routinely share a default size (every Terminal window is the same size)
        // and go briefly Space-less during a Space transition or a flaky CGS read, which looked exactly like a
        // background tab and collapsed real windows into a phantom tab group (#5830). Confirmed when any of:
        //  - the visible was already AX-confirmed tabbed (`tabbedSiblingWids != nil`) — re-link a tab switch;
        //  - any member is fullscreen (its tabs expose no readable AXTabGroup, and a new active's own
        //    fullscreen flag lags discovery — so check the members, not just the visible);
        //  - a background candidate is ALREADY grouped AND its group has lost its visible (`isOrphanedTab`)
        //    — a NEW tab taking over an existing group.
        //  - the visible's own AXTabGroup says it HAS tabs (`tabCount > 1`). AX naming the siblings is what
        //    normally writes `tabbedSiblingWids`, and that naming is by TITLE, which fails outright for an
        //    app composing its window title from more than its tab label (stock Terminal, #5785), so that
        //    first clause could never open and the tabs churned as separate tiles forever. The COUNT is the
        //    part of the AX read that is never in doubt, so it confirms the cluster on its own. For an app
        //    whose titles DO match, `tabbedSiblingWids` is already non-nil and clause one already opened the
        //    gate, so this clause cannot change those apps' behaviour.
        // None can false-positive on #5830: a window going briefly Space-less there is a SEPARATE window,
        // never fullscreen-sized and never already carrying `tabbedSiblingWids`.
        //
        // KNOWN HOLE, and the fullscreen clause is where it lives: alone it confirms almost any fullscreen
        // cluster — every fullscreen window is screen-sized, so they all cluster together — so a tab that
        // merely backgrounded inside ONE fullscreen window (Space-less for a beat, indistinguishable from a
        // brand-new tab by current facts) can be handed to a DIFFERENT fullscreen window that holds its own
        // Space. Don't narrow the clause with `newlyDiscovered`: that breaks 13 corpus tests requiring a
        // fullscreen visible to group WITHOUT AX confirmation or a fresh discovery
        // (`testFullscreenVisibleGroupsWithoutAxConfirmation`, `testTwoFullscreenWindowsEachResolveToOneTile`).
        // The kernel genuinely cannot decide this from current facts — the distinguishing fact is HISTORY:
        // the candidate just left a DIFFERENT fullscreen Space, which only the reducer sees (the 1326 names
        // the Space). See `testFullscreenTabBackgroundingIsNotStolenByAnotherFullscreenWindow`.
        let confirmedTheOldWay = visible.tabbedSiblingWids != nil
                || background.contains(where: { isOrphanedTab($0, among: members, visible: visible) })
                || members.contains(where: { $0.isFullscreen })
        guard confirmedTheOldWay || visible.tabCount > 1 else { return nil }
        // BOUND a fold that ONLY the tab count confirmed. A window with N tabs has at most N-1 background
        // ones, so more candidates than that means this cluster holds something that is NOT our tab: a
        // separate same-frame window gone transiently Space-less, or a SECOND group of this app at the same
        // frame (Terminal stacks its windows). Which one is the intruder is undecidable here, and guessing
        // would HIDE a real window — the worst outcome available — so refuse the whole fold and let the
        // cluster stay separate tiles until AX or an event says more. Silence is not a verdict.
        //
        // Scoped to the tab-count clause deliberately. Applied to the OTHER confirmations it BREAKS them: the
        // model legitimately holds more candidates than the window has tabs while a tab switch that MINTS new
        // wids is in flight, because the retired ones aren't swept yet — the count is truth about the OS, not
        // about our in-flight bookkeeping (generator seed 163: a 3-tab window whose group still held the wid a
        // switch had just retired; the fold was refused and the incoming tile lost its inherited thumbnail,
        // flashing the app icon). Keeping the bound on the new clause alone also preserves the property that
        // made this change safe to begin with: where tab titles match window titles, `tabbedSiblingWids`
        // already confirmed the cluster, so nothing here can change that app's behaviour.
        if !confirmedTheOldWay, background.count > visible.tabCount - 1 { return nil }
        return GeometryGroup(visibleWid: visible.wid, backgroundWids: background.map { $0.wid })
    }

    /// **SPLIT VIEW: a second real window sharing one fullscreen Space.** The fullscreen invariant this file
    /// rests on — one Space, one window — has exactly one exception, and macOS builds it on purpose: two
    /// windows tiled side by side occupy a single fullscreen Space. Measured live (macOS 26, two TextEdit
    /// windows via Window ▸ Full-Screen Tile):
    ///
    ///     wid 12542  fullscreen=true  frame=(0,36 1022x1116)    spaces=[2267]
    ///     wid 36133  fullscreen=true  frame=(1034,0 1014x1152)  spaces=[2267]
    ///
    /// Both hold the Space, so neither is background by the Space-less rule — but the fold above deliberately
    /// absorbs a member SETTLED on the fold Space anyway, to catch the visible's outgoing tab whose 1326 has
    /// not landed. That is precisely what would swallow a split-view partner and hide a real window, whenever
    /// the two halves happen to share a size (two Finder windows, say; the pair measured above differ only
    /// because one had a toolbar showing).
    ///
    /// The ORIGIN separates them. A lagging outgoing tab is the visible's OWN window, so it carries the
    /// visible's frame; split halves sit side by side and cannot share an origin. So: a member that genuinely
    /// holds the Space and sits at a different origin is a separate window, not a tab. Positions must BOTH be
    /// known — silence is not a verdict here either, and a brand-new tab is frameless for a beat.
    private static func isSplitViewPartner(_ m: TabWindow, visible: TabWindow) -> Bool {
        guard hasGenuineSpace(m), let pm = m.position, let pv = visible.position else { return false }
        return !samePosition(pm, pv)
    }

    /// Is this candidate a tab of a window on a DIFFERENT Space than the active reading its own tab group?
    /// Only asks of an already-TABBED candidate, since an untabbed one is governed by the plausibility rules;
    /// and only when both sides actually name a Space — the active must be settled, and the candidate must
    /// either be settled itself or remember the Space it left. Silence decides nothing, as everywhere else.
    private static func belongsToAWindowOnAnotherSpace(_ candidate: TabWindow, activeOn active: TabWindow) -> Bool {
        guard candidate.isTabbed, let activeSpace = settledSpace(active) else { return false }
        if let own = genuineSettledSpace(candidate) {
            return own != activeSpace
        }
        guard let left = candidate.lastLeftSpaceId else { return false }
        return left != activeSpace
    }

    /// Does `candidate` already belong to a window that is DEMONSTRABLY ELSEWHERE — its group holding a
    /// member genuinely SETTLED on a Space the visible is not on? Two fullscreen Spaces mean two windows, so
    /// such a tab is not the visible's to claim.
    ///
    /// Every clause is doing work. The group-mate's Space must be GENUINE (a borrow or a hold is our own
    /// annotation, not CGS evidence) and SETTLED (one Space; silence is not a verdict). And the visible must
    /// hold at least one Space of its own: a brand-new tab is Space-less for a beat, and from nothing you can
    /// conclude nothing — that case is exactly `testFullscreenNewTabGroupsWithOldActiveOnSameSpace`, where
    /// the new tab must still claim the old active it is taking over from.
    private static func settledOnAnotherWindowsSpace(_ candidate: TabWindow, among members: [TabWindow],
                                                     visible: TabWindow) -> Bool {
        guard !visible.spaceIds.isEmpty else { return false }
        // It just LEFT a Space the visible isn't on ⇒ it backgrounded inside a different window. This is the
        // history clause: by current facts alone the candidate is merely Space-less, exactly like a brand-new
        // tab of the visible's window, and geometry handed one window's backgrounded tab to another
        // fullscreen window because of it (generator seed 6, and the shape of the live rec26 mega-group).
        if let left = candidate.lastLeftSpaceId, !visible.spaceIds.contains(left) { return true }
        guard let links = candidate.tabbedSiblingWids, links.count > 1 else { return false }
        return members.contains { m in
            m.wid != visible.wid && m.wid != candidate.wid && links.contains(m.wid)
                && (genuineSettledSpace(m).map { !visible.spaceIds.contains($0) } ?? false)
        }
    }

    /// Does `candidate` belong to a DIFFERENT window in this cluster, because that window's tab is the one
    /// that took its place? A backgrounded tab and the tab that replaced it are two tabs of ONE window, by
    /// construction — the OS put one on the Space as it took the other off. So a candidate naming a successor
    /// that is present here and is NOT the visible is not the visible's to claim.
    ///
    /// This is the guard `settledOnAnotherWindowsSpace` cannot be: that one reasons from Spaces, which
    /// identify a window only in fullscreen (one window per Space). Two windowed windows of one app SHARE a
    /// Space — Terminal even stacks them at the same frame, same title — and then every Space-based test is
    /// true of both windows at once. The handover names a wid, so it stays sharp exactly where the rest goes
    /// blind. `testBackgroundedTabIsNotStolenByAStackedWindowOfTheSameApp`.
    ///
    /// Requires the successor to be PRESENT in the cluster, deliberately. A successor we can't see says
    /// nothing about whether the visible is the candidate's window — the wid may have been retired by a
    /// later switch — and refusing the fold on absent evidence would strand real tabs, which is the
    /// expensive direction (a hidden window). Evidence present, or no verdict.
    private static func belongsToTheWindowThatReplacedIt(_ candidate: TabWindow, among members: [TabWindow],
                                                         visible: TabWindow) -> Bool {
        guard let successor = candidate.replacedByWid, successor != visible.wid else { return false }
        return members.contains { $0.wid == successor }
    }

    /// Is `candidate` a grouped tab whose group has LOST its visible — i.e. up for adoption by a new active
    /// tab? True when no OTHER tracked member of its group still holds a Space. That last clause is the
    /// load-bearing half, and skipping it is what let geometry steal a window's tab: a group whose own active
    /// tab is still on-screen is a live group, and geometry is a guess — it must never overrule AX, which
    /// linked that group in the first place. A tab merely backgrounding INSIDE window B is Space-less for a
    /// beat, and every Finder window shares the default 920×436, so an unrelated same-size window became its
    /// "visible" and annexed it (rec10: `geometryGroup visible#74625 sp[3628] background=[74628]` — a real
    /// window hidden, the selection derailed onto Chrome).
    ///
    /// Note the test is Space-holding, NOT `newlyDiscovered`: that flag is newly TRACKED, and at launch
    /// EVERYTHING is (the same trap as "the void"), so it would have left the theft live during launch
    /// discovery. A REAL takeover still passes — when a new tab backgrounds the old active, every member of
    /// the old group is Space-less, so the group is genuinely orphaned and gets absorbed atomically.
    private static func isOrphanedTab(_ candidate: TabWindow, among members: [TabWindow],
                                      visible: TabWindow) -> Bool {
        guard let links = candidate.tabbedSiblingWids, links.count > 1 else { return false }
        return !members.contains { $0.wid != visible.wid && links.contains($0.wid) && !$0.spaceIds.isEmpty }
    }

    /// A rounded app + size key — the coarse cluster, refined by `framePartitions`. Position is not here
    /// because the fullscreen exemption is only decidable across a whole cluster (a new tab's `isFullscreen`
    /// lags), which a per-window key can't express.
    private static func sizeKey(_ window: TabWindow) -> String {
        let s = window.size ?? .zero
        return "\(window.pid)-\(Int(s.width.rounded()))x\(Int(s.height.rounded()))"
    }

    /// True iff both windows have the same rounded size. Tabs of one window share their parent's frame, so a
    /// same-size same-app window is a tab candidate; a nil size (unknown) never matches.
    private static func sizesMatch(_ a: TabWindow, _ b: TabWindow) -> Bool {
        guard let sa = a.size, let sb = b.size else { return false }
        return Int(sa.width.rounded()) == Int(sb.width.rounded()) && Int(sa.height.rounded()) == Int(sb.height.rounded())
    }

    /// Match an active tab's AXTabGroup titles to tracked same-app windows. `sameAppWindows` may include
    /// the active tab itself (filtered out by wid). The active tab's own title is removed once from the
    /// title list (there may be duplicate titles); each remaining title is matched to the first
    /// compatible, not-yet-matched window that is PLAUSIBLY an inactive tab (already tabbed or Space-less —
    /// an on-screen window is never claimed). A window already tabbed into THIS group is then kept even if no
    /// title named it, so a duplicate/renamed title can't flap an inactive tab out of its group (#5830).
    /// Titles with no tracked window are returned as `untrackedTitles` (inactive tabs to discover); windows
    /// that were in this group but are no longer tabbed (became standalone) are returned as `toUntabWids`.
    static func matchSiblings(active: TabWindow, axTitles: [String], sameAppWindows: [TabWindow],
                              activeIsNewlyDiscovered: Bool = false) -> SiblingMatch {
        var remainingTitles = axTitles
        if let i = remainingTitles.firstIndex(of: active.title) { remainingTitles.remove(at: i) }
        let zeroSizedMergeWids = zeroSizedMergeClaim(active, remainingTitles, sameAppWindows)
        var matchedWids = [CGWindowID]()
        var matchedTitles = [String]()
        for title in remainingTitles {
            let candidates = sameAppWindows.filter { s in
                s.wid != active.wid && s.title == title
                    && !matchedWids.contains(s.wid)
                    // Only a window that is PLAUSIBLY an inactive tab can be claimed: already tabbed,
                    // Space-less (an inactive tab is on no Space; 1325/1326 keep that live), HELD, or holding
                    // a BORROWED Space. Held/borrowed mean the Space is OUR annotation, not CGS evidence — a
                    // held tab is mid-swap and normalize lends its group's representative a Space so the tile
                    // can't vanish — and reading it as "genuinely on-screen" twice made a real group member
                    // un-claimable and stranded it as a ghost tile (rec14: the held outgoing tab; rec20: an
                    // ex-representative orphaned with its lent Space). Both legs are size-gated, so a
                    // held/borrowed tab of a DIFFERENT same-position window (Terminal stacks its windows)
                    // isn't claimable across groups. A genuinely on-screen window is by definition NOT an
                    // inactive tab — without that protection, a NEW same-title window (Finder cmd-N,
                    // duplicate titles) was claimed to fill a title whose real tab has no window (Finder
                    // destroys a backgrounded tab's window), and vanished from the switcher.
                    // The size gate on that last leg is waived for a member the zero-sized merge claim
                    // already proved, because there the active is 0×0 by construction and NO real tab can
                    // ever match its size: Merge All Windows publishes the merged window unsized, normalize
                    // promotes an absorbed tab to presentable representative (un-tabbed, holding the Space
                    // it was lent), and the next AX read then found it neither Space-less nor size-matched
                    // and ejected it from its own group — it stood as a second Finder tile and then went
                    // phantom (live QA T-03, 2026-08-29). The exact AX count is what stands in for the
                    // geometry here, on this leg exactly as it already does for the position test below.
                    && (s.isTabbed || s.spaceIds.isEmpty
                        || (spaceIsOurAnnotation(s)
                            && (sizesMatch(active, s) || zeroSizedMergeWids.contains(s.wid))))
                    // ...and the same rule the geometry path applies, stated twice as this file requires: a
                    // candidate the WindowServer still shows ON SCREEN is a real window, never somebody's
                    // inactive tab, whatever its Space says (a background tab is ordered OUT — measured). An
                    // already-TABBED candidate is exempt: it is drawn as its own group's representative, so
                    // being on screen is exactly what it should be, and re-linking it is this path's job.
                    && (s.isTabbed || !s.isOrderedIn)
                    // A GENUINELY-FULLSCREEN candidate is never claimable: the fullscreen Space invariant
                    // says it is its own window (plus its own tabs) on its own Space — a windowed group's
                    // tab can never be a fullscreen window. Without this, switching Spaces TO a fullscreen
                    // window made it transiently Space-less (transition noise ⇒ plausible), its shared
                    // title matched, and `positionsCompatible`'s fullscreen waiver — which exists to claim
                    // a fullscreen window's frozen (non-fullscreen) TABS — let a windowed group annex the
                    // fullscreen WINDOW itself; geometry's membership union then bridged everything it was
                    // linked to into one mega-group, hiding real windows (rec24c: 10 members, 9 hidden).
                    // The second pass below needs the same gate, for its own reason (seed 6); don't drop
                    // either on the grounds that the size test already separates them.
                    && !s.isFullscreen
                    // ...and not a tab that BELONGS to a window elsewhere. An already-tabbed candidate passes
                    // the plausibility test above whatever its Space says, which is right for this window's
                    // own tabs (they carry a borrowed Space equal to the active's) and wrong for another
                    // window's: with duplicate titles, a FULLSCREEN active claimed a windowed window's tab,
                    // and the membership union then merged the two windows (generator seed 30). Reads the
                    // same `lastLeftSpaceId` history the geometry path reads in `settledOnAnotherWindowsSpace`.
                    && !belongsToAWindowOnAnotherSpace(s, activeOn: active)
                    && !belongsToAnotherVisibleGroup(s, active, sameAppWindows)
                    && (positionsCompatible(active, s) || zeroSizedMergeWids.contains(s.wid))
            }
            if let sibling = preferredExistingMember(candidates, active) {
                matchedWids.append(sibling.wid)
                matchedTitles.append(sibling.title)
            }
        }
        // Second pass, ONLY when THIS active is the freshly-discovered window (a new tab that just took over
        // its group): the previous active tab has just backgrounded, but its "removed from Space" event may
        // not have arrived yet, so it still shows a stale Space and the strict pass above skipped it — it
        // would flash as a 2nd tile for the beat until 1326 lands (the creation-race, 2026-07-14 capture).
        // Because the brand-new window is what carries the AXTabGroup here, any same-app, same-SIZE on-screen
        // sibling is that just-backgrounded tab: a genuinely separate new window reports its OWN tab group as
        // the active element and never reaches this path (that's the `testOnScreenWindowNeverClaimedAsTab`
        // case, which runs with `activeIsNewlyDiscovered == false`). Claiming them makes the group atomic
        // from its first render. Still title-gated, so two coexisting same-app groups (distinct titles) don't
        // bleed into each other; still bounded to the AX tab count (one claim per unmatched title).
        if activeIsNewlyDiscovered {
            var unfilledTitles = remainingTitles
            for t in matchedTitles { if let i = unfilledTitles.firstIndex(of: t) { unfilledTitles.remove(at: i) } }
            for title in unfilledTitles {
                let candidates = sameAppWindows.filter { s in
                    s.wid != active.wid && s.title == title && !matchedWids.contains(s.wid)
                        // Same fullscreen Space invariant as the first pass. The size gate is NOT a
                        // substitute for it: that argument assumes the ACTIVE is windowed, and it isn't when
                        // the new tab belongs to a FULLSCREEN window — then active and candidate are both
                        // screen-sized, the size gate passes, and this pass claimed a whole separate
                        // fullscreen window as a tab (generator seed 6).
                        && !s.isFullscreen
                        && !belongsToAnotherVisibleGroup(s, active, sameAppWindows)
                        && sizesMatch(active, s) && positionsCompatible(active, s)
                }
                if let sibling = preferredExistingMember(candidates, active) {
                    matchedWids.append(sibling.wid)
                    matchedTitles.append(sibling.title)
                }
            }
        }
        // Stability (#5830): a window already in THIS group and still tabbed stays in it even when the AX
        // titles don't name it. Terminal's tabs all read "~" and get renamed by cwd/command, so a title miss
        // must not eject an inactive tab from its own group (the "cause-B flap") — it would flash out as a
        // separate window and re-trigger discovery. Keyed on `tabbedSiblingWids` containing the active wid, so
        // a DIFFERENT group's tabs (same app) are left alone. A tab that truly left (drag-out) has its
        // membership removed by its own Space-join event, so it is not kept and falls through to `toUntabWids`.
        //
        // Also kept: an on-screen, un-tabbed member of this group that is MORE RECENTLY FOCUSED than the
        // reading active. Focus is authoritative for which member is the group's active tab — and AX reads
        // are queued, so a read can land right after the user switched to another member (rec18): treating
        // the reader as the active then ejected the REAL active from its own group (`toUntabWids`), stranding
        // it as a stray visible tile that the next stale read fought over, endlessly. A stale read keeps the
        // fresher member; the strict `<` means a genuinely-departed window (equal or older focus) still falls
        // through to `toUntabWids`.
        // Also kept, while the reading active has NO FRAME OF ITS OWN: every member of the handover group the
        // reducer just inherited. During a rapid Cmd+T burst the incoming window is 0×0, so normalize leaves
        // the prior active as the presentable representative (`isTabbed == false`) — which the title pass
        // cannot claim (on screen, un-tabbed) and the token pass has never read as a selected tab, so
        // ejecting it splits one window into two tiles until the incoming frame arrives (T-02).
        // Keyed on the active's own size, not on `activeIsNewlyDiscovered` alone: the discovery read and a
        // plain `axMainWindow` read can land in the same millisecond and only the first carries the flag, so
        // the second untabbed the representative and a Cmd+T burst drew a third Finder tile until the
        // geometry pass repaired it 385ms later (live QA T-12, 2026-08-31).
        // Windows the OS itself puts in this group: they named the SAME `AXTabGroup` element as the active
        // (`TabGroupToken`). Every other route here is an inference ABOUT a group — a title that might be
        // shared or composed differently (#5785), a frame that might coincide — while this one is the group,
        // stated by AppKit. So it needs no title and no geometry to agree, and it claims the tabs those two
        // routes cannot: Terminal composes tab titles unlike window titles, and after "Merge All Windows"
        // absorbed frames never converge.
        //
        // It is NOT allowed to skip the two gates that stop a claim HIDING a real window, because those are
        // about staleness rather than about evidence: a token is recorded when a window is read as the
        // selected tab and it outlives that instant. Outside a creation, then, a candidate must still look
        // like an inactive tab (Space-less, held/borrowed, or already tabbed) and must still not be on
        // screen. During a creation the claim is the sanctioned atomic one, same exemption the size-matched
        // second pass takes above and for the same reason: the outgoing tab's 1326 has not landed yet.
        // Fullscreen is excluded throughout — entering fullscreen REPLACES the element, so a fullscreen
        // window never shares a windowed group's token, and the invariant is worth stating twice.
        let tokenWids = sameAppWindows.filter { s in
            s.wid != active.wid && !matchedWids.contains(s.wid)
                && active.tabGroupToken != nil && s.tabGroupToken == active.tabGroupToken
                && !s.isFullscreen
                && (activeIsNewlyDiscovered
                    || ((s.isTabbed || s.spaceIds.isEmpty || spaceIsOurAnnotation(s)) && (s.isTabbed || !s.isOrderedIn)))
        }.map { $0.wid }
        matchedWids.append(contentsOf: tokenWids)
        // ...and the REST of the group each of them is already in. The token says this active joins THAT
        // group, and `form` is exact-set, so naming the one sibling the token happened to reach would EJECT
        // its other members — a real window's tile split off from the group it never left (generator seed 18,
        // where composed titles name nobody and only the two most recent tabs had ever been read as active).
        // Nothing here re-decides their membership: they are grouped already, and a member that genuinely
        // left is taken out by its own signal, never by this one's silence.
        let tokenGroupWids = sameAppWindows.filter { s in
            s.wid != active.wid && !matchedWids.contains(s.wid)
                && s.tabbedSiblingWids?.contains(where: { tokenWids.contains($0) }) == true
        }.map { $0.wid }
        matchedWids.append(contentsOf: tokenGroupWids)
        let keptWids = sameAppWindows.filter { s in
            s.wid != active.wid && !matchedWids.contains(s.wid)
                && s.tabbedSiblingWids?.contains(active.wid) == true
                && (s.isTabbed || activeIsNewlyDiscovered || !isPresentable(active)
                    || (!s.spaceIds.isEmpty && s.lastFocusOrder < active.lastFocusOrder))
        }.map { $0.wid }
        matchedWids.append(contentsOf: keptWids)
        var untrackedTitles = remainingTitles
        for title in matchedTitles {
            if let i = untrackedTitles.firstIndex(of: title) { untrackedTitles.remove(at: i) }
        }
        // each kept or token-matched sibling accounts for one AX title we couldn't name — don't re-discover a
        // tab we already hold, and don't let the same title be filled twice.
        for _ in keptWids + tokenWids + tokenGroupWids where !untrackedTitles.isEmpty { untrackedTitles.removeFirst() }
        // Un-tab only windows that WERE in this group but are neither matched nor kept — their `isTabbed` was
        // cleared (they became standalone). A different group's tabs never contain the active wid.
        let toUntabWids = sameAppWindows.filter { s in
            s.wid != active.wid && !matchedWids.contains(s.wid) && s.tabbedSiblingWids?.contains(active.wid) == true
        }.map { $0.wid }
        return SiblingMatch(siblingWids: [active.wid] + matchedWids, matchedWids: matchedWids,
            untrackedTitles: untrackedTitles, toUntabWids: toUntabWids)
    }

    /// Duplicate titles make the AX list a count rather than an identity. Spend those slots on members this
    /// active already owns before unattached candidates, or a partial read can eject the group's presentable
    /// representative and expose it as a second tile until the next geometry pass (T-01/T-02).
    private static func preferredExistingMember(_ candidates: [TabWindow], _ active: TabWindow) -> TabWindow? {
        candidates.first { $0.tabbedSiblingWids?.contains(active.wid) == true } ?? candidates.first
    }

    /// Merge All Windows can publish its new selected window at 0×0 while every absorbed tab keeps the frame
    /// of its former cascaded window. At that instant geometry cannot put the active in their size cluster.
    /// An exact AX count covering every ordered-out title candidate proves the fold until its frame arrives.
    private static func zeroSizedMergeClaim(_ active: TabWindow, _ titles: [String],
                                            _ windows: [TabWindow]) -> Set<CGWindowID> {
        guard let size = active.size, size.width == 0 || size.height == 0,
              active.tabCount == titles.count + 1, active.tabCount > 1 else { return [] }
        var candidates = windows.filter {
            $0.wid != active.wid && !$0.isFullscreen && (!$0.isOrderedIn || spaceIsOurAnnotation($0))
                && titles.contains($0.title) && !belongsToAnotherVisibleGroup($0, active, windows)
        }
        guard candidates.count == titles.count else { return [] }
        var result = Set<CGWindowID>()
        for title in titles {
            guard let i = candidates.firstIndex(where: { $0.title == title }) else { return [] }
            result.insert(candidates.remove(at: i).wid)
        }
        return result
    }

    private static func belongsToAnotherVisibleGroup(_ candidate: TabWindow, _ active: TabWindow,
                                                      _ windows: [TabWindow]) -> Bool {
        guard let members = candidate.tabbedSiblingWids, members.count > 1,
              !members.contains(active.wid) else { return false }
        return windows.contains {
            members.contains($0.wid) && !$0.isTabbed && ($0.isOrderedIn || hasGenuineSpace($0))
        }
    }

    /// Tabs of one window ARE the parent's frame, so a tab candidate must sit at the active tab's position
    /// EXACTLY. Any offset means a different window. When either position is unknown, or either is fullscreen
    /// (a fullscreen window's tabs can't share its frame, and an inactive tab's position goes stale when its
    /// parent fullscreens), fall back to a title-only match. An existing tab link is respected so a stale
    /// position can't split an already-grouped pair (e.g. after Merge All Windows, where tabs keep distinct
    /// pre-merge positions) — that bypass is what lets this test be exact rather than tolerant.
    ///
    /// **No position tolerance here, ever.** macOS CASCADES new windows by 29px, so any tolerance near that
    /// merges real windows: two Finder windows one cascade step apart, both at the default 920×436 and every
    /// tab titled "lwouis" (Finder names tabs after the folder), were mutually claimable on every fact we
    /// had. One window's active tab swallowed the other's tabs and the second window lost every member, one
    /// tile for two windows (rec11).
    ///
    /// Exact is also the SAFE side of an asymmetry: failing to claim a real tab is invisible (an unclaimed
    /// background tab is Space-less ⇒ phantom ⇒ hidden either way, and the group still shows its active tab,
    /// all the user ever sees), while wrongly claiming a real WINDOW hides it and derails the selection. When
    /// positions disagree, don't group.
    ///
    /// The link test looks one way only (does `b` list `a`?), which is sufficient, not sloppy:
    /// `tabbedSiblingWids` is projected from the group REGISTRY, where `siblingWids(of:)` returns the same
    /// member array for every member of a group, so `b` lists `a` exactly when `a` lists `b`. If links ever
    /// stop coming from one registry entry, that stops holding and the test must become symmetric.
    static func positionsCompatible(_ a: TabWindow, _ b: TabWindow) -> Bool {
        if b.tabbedSiblingWids?.contains(a.wid) == true { return true }
        guard let pa = a.position, let pb = b.position, !a.isFullscreen, !b.isFullscreen else { return true }
        return samePosition(pa, pb)
    }

    /// The member a group shows: its ACTIVE tab — which is, by definition, **the most recently FOCUSED
    /// member**. Focus is the one authoritative signal here (`lastFocusOrder`); every earlier heuristic
    /// (prefer the un-tabbed Space-holder, then the just-backgrounded visible, then focus) was approximating
    /// it through the derived `isTabbed` and the backfilled Spaces — circular, and read-order-sensitive
    /// exactly when several members look on-screen mid-switch (rec18/rec19). Every scenario in the corpus
    /// agrees with focus directly: the new tab is bumped at discovery; a switched-to tab is bumped on its
    /// Space-join; the just-backgrounded visible was focused most recently until its replacement lands; a
    /// wrongly-tabbed focused window recovers (`finderFocusedWindowWronglyTabbed`).
    ///
    /// Only a member that can be DRAWN may represent the group: the OS creates a new tab at 0×0 and sizes it
    /// ~640ms later, and handing it the group showed a tile of EMPTY PIXELS (rec11) — until it is sized, the
    /// outgoing tab (next most recent, still captured) keeps the tile. Falls back to the full set if NOTHING
    /// is presentable (a stale tile beats none).
    ///
    /// nil ONLY for an INCOHERENT group — members disagreeing on `tabbedSiblingWids` (a wid re-homed into a
    /// new group while the old group's members still list it); forcing one of those visible spuriously un-hid
    /// a background tab as a 2nd tile.
    static func groupRepresentative(_ members: [TabWindow]) -> CGWindowID? {
        let links = Set(members.map { Set($0.tabbedSiblingWids ?? []) })
        guard links.count == 1 else { return nil }
        let presentable = members.filter { isPresentable($0) }
        let candidates = presentable.isEmpty ? members : presentable
        return candidates.min { $0.lastFocusOrder < $1.lastFocusOrder }?.wid
    }

    /// Did the member that just joined a Space get DRAGGED OUT of its window (vs becoming its group's active
    /// tab)? Indistinguishable at event time — a dragged-out tab starts at the parent's frame — so the caller
    /// treats the join as a tab switch (a representative move; the old remove-and-rediscover here is what
    /// flickered the switcher on every switch, rec19) and re-checks this verdict until it decides:
    /// - nil — undecided: the joiner's frame isn't known/settled yet (a new window is 0×0 for a beat).
    /// - false — same frame as the PREVIOUS representative ⇒ a tab switch; stop checking.
    /// - true — the joiner settled at a DIFFERENT frame ⇒ it left the window; take it out of the group.
    /// Compared against the previous representative, NOT the other members: their stored frames can be stale
    /// (a background tab gets no geometry events, so a moved window leaves them frozen at the old frame),
    /// while the outgoing active was live on-screen at the moment of the join. Fullscreen is excluded —
    /// frames are unreliable there, and the fullscreen Space rule (`membersThatLeftGroup`) owns departures.
    static func dragOutVerdict(joiner: TabWindow, previousRepresentative: TabWindow,
                               pairingWindowElapsed: Bool = false) -> Bool? {
        if joiner.isFullscreen || previousRepresentative.isFullscreen { return false }
        // THE HANDOVER ANSWERS IT DIRECTLY, and the frames never could. A tab SWITCH is a join MATCHED by the
        // outgoing tab's leave on that Space; a drag-OUT is a join with no leave, because the parent's active
        // tab never went anywhere. Both legs must stay ahead of the frame test below, which can only guess:
        // a dragged-out tab starts at its parent's frame, so dropping one back over its parent reads as a
        // switch, and "same frame" also says stop checking. The window then stayed in the group, hidden.
        if let replaced = joiner.replacedWid { return replaced != previousRepresentative.wid }
        // The absence of a leave is only evidence once the pairing window has passed — before that the 1326
        // may simply be in flight (it is routinely the later of the two, `fullscreenTabSwitchEvents`). The
        // caller owns that clock: `dragOutCheck` re-fires on a timer and knows how long it has been.
        if pairingWindowElapsed, !previousRepresentative.spaceIds.isEmpty,
           joiner.spaceIds.contains(where: { previousRepresentative.spaceIds.contains($0) }) {
            return true
        }
        guard isPresentable(joiner), joiner.position != nil,
              previousRepresentative.size != nil, previousRepresentative.position != nil else { return nil }
        return !sameFrame(joiner, previousRepresentative)
    }

    /// Can this window be drawn as a tile? A window with no size, or a degenerate one, has no thumbnail to
    /// show. Two live sources, hence the check rather than trust: the OS genuinely publishes a new tab at 0×0
    /// before sizing it, and a failed AX read used to report 0×0 too (`AXValueGetValue`'s ignored return —
    /// fixed at the source in `AXUIElement.castSafely`, but a real 0×0 still arrives).
    private static func isPresentable(_ window: TabWindow) -> Bool {
        guard let size = window.size else { return false }
        return size.width > 0 && size.height > 0
    }

    /// Should a window that just left its LAST Space be held visible through the new-tab discovery gap?
    /// A tab backgrounding because a new tab took over goes Space-less → phantom → hidden, while the new tab
    /// isn't discovered for ~640ms (the OS creates it at 0×0 and sizes it later) — so the group would show
    /// ZERO tiles. Holding the old tab keeps exactly one tile across the swap. Gated on a REPLACEMENT
    /// SIGNAL, because that is what distinguishes "something is coming to take over" from a plain background
    /// (nothing is; it should just hide). Two signals qualify:
    /// - a recent `windowCreated` — a new tab being CREATED announces itself with an 811;
    /// - a recent UNTRACKED window joining the visible Space — Finder mints a brand-new wid per tab SWITCH
    ///   and emits NO create for it, only a 1325 onto the visible Space one beat before the outgoing tab's
    ///   1326 (rec24: without this leg the outgoing rep went phantom, the show-time Spaces re-query wiped
    ///   the whole group's borrowed Spaces, and the tile vanished ~800ms until the minted wid's discovery
    ///   re-claimed everything).
    /// The timer lives in the adapter; this is the decision.
    static func shouldHoldVisibleThroughDiscovery(isTabbed: Bool, becomesSpaceless: Bool,
                                                  hadRecentWindowCreate: Bool,
                                                  hadRecentUntrackedSpaceJoin: Bool = false) -> Bool {
        !isTabbed && becomesSpaceless && (hadRecentWindowCreate || hadRecentUntrackedSpaceJoin)
    }

    /// Should a held window be released? The hold exists for ONE reason (never show ZERO tiles for a window
    /// whose tabs are mid-swap) so it ends the moment something else can show: the incoming tab CLAIMED it
    /// (`isTabbed`, so the tab filter hides it regardless), or a replacement is ready to be drawn, or the
    /// safety cap is hit.
    ///
    /// **Every argument is observable state, deliberately.** Don't reintroduce a pending-discovery test
    /// (`!recentlyCreatedWindows.isEmpty`): that set is GLOBAL, so a Chrome window opening pinned a Finder
    /// tab, and it LEAKS — a burst outruns discovery, so each tab's window is created, added and removed
    /// without ever being discovered or focused, and Finder's destroy event never fires, so the flag survives
    /// forever. Once it never empties, no hold can release on its own for the rest of the session and every
    /// one runs the 20s cap, pinning a stale tab as a permanent second tile (rec13). Observable state can
    /// neither leak nor couple two apps.
    static func shouldReleaseHold(isTabbed: Bool, hasPresentableReplacement: Bool, attemptsExhausted: Bool) -> Bool {
        isTabbed || hasPresentableReplacement || attemptsExhausted
    }

    /// Is another window ready to take over the held tab's tile? A tab's replacement is the next tab of the SAME
    /// window: same app, on-screen (holds a Space), un-tabbed, drawable, and — the load-bearing part — at the
    /// held tab's own FRAME. Frame, not merely size: same-size windows of one app are the norm (macOS cascades
    /// them 29px apart), and releasing because a DIFFERENT window has a tile would hide the held tab while its
    /// own group still had nothing to show — the exact vanish the hold exists to prevent.
    ///
    /// This also gives the timing for free, with no delay to tune: the OS publishes a new tab at 0×0 and sizes
    /// it to the parent's frame ~640ms later, so "at my frame and drawable" IS "ready to be shown". An incoming
    /// fullscreen tab whose `isFullscreen` still lags simply isn't ready yet and the hold continues — the wanted
    /// answer, not a special case.
    static func hasPresentableReplacement(for held: TabWindow, among windows: [TabWindow]) -> Bool {
        windows.contains { w in
            w.wid != held.wid && w.pid == held.pid && !w.isTabbed && !w.spaceIds.isEmpty
                && isPresentable(w) && sameFrame(w, held)
                // ...and NOT a window settled on a Space the held tab isn't on. The frame test above is what
                // normally proves "same window": two tabs necessarily share a frame, while separate windows
                // of one app are cascaded 29px apart. That reasoning collapses in FULLSCREEN, where every
                // window is screen-sized at 0,0 — so an UNRELATED fullscreen window on ANOTHER Space passed
                // as the replacement, the hold released early, and the tile it was holding vanished. Live
                // capture rec27: bursting ⌘T in a fullscreen Finder window while a second fullscreen Finder
                // window sat on another Space; the user saw the tile go out and come back.
                && !isSettledElsewhere(w, than: held)
        }
    }

    /// `w` is settled on a Space the held tab demonstrably does not belong to.
    ///
    /// The held tab's reference Space is its own if it still has one, ELSE THE SPACE IT JUST LEFT. That
    /// fallback is the whole point: a held tab is by definition one whose 1326 just landed, so its
    /// `spaceIds` is empty precisely when this question is asked. Comparing against `spaceIds` alone made
    /// the guard a no-op in the only case it existed for, and the tile kept vanishing (rec27, caught by
    /// re-reading the capture rather than by another live run).
    private static func isSettledElsewhere(_ w: TabWindow, than held: TabWindow) -> Bool {
        guard let space = settledSpace(w) else { return false }        // silence is not a verdict
        if !held.spaceIds.isEmpty { return !held.spaceIds.contains(space) }
        guard let left = held.lastLeftSpaceId else { return false }
        return space != left
    }

    /// Same rounded size AND position — the frame two tabs of one window necessarily share.
    private static func sameFrame(_ a: TabWindow, _ b: TabWindow) -> Bool {
        guard sizesMatch(a, b), let pa = a.position, let pb = b.position else { return false }
        return samePosition(pa, pb)
    }

    /// Which members have LEFT this group and must be unlinked — separate windows still carrying a stale
    /// `tabbedSiblingWids`. The fullscreen Space invariant's "≥ 2 Spaces ⇒ separate windows" side: a member on
    /// a Space the visible isn't on is its own fullscreen window (a dragged-out tab gets a new Space). AX
    /// exposes no tab titles for a fullscreen window, so nothing else can retire that stale link.
    ///
    /// FULLSCREEN-only, and never generalized to plain windows: a real background tab's `spaceIds` can be
    /// non-empty AND disjoint from its visible's (captured — `terminalVisibleWithForeignSpaceTabs`: tabs
    /// reporting a foreign Space 4179 while their visible held 3628, yet genuinely tabs). Un-grouping on that
    /// exploded a live Terminal group into one tile per tab.
    static func membersThatLeftGroup(visible: TabWindow, members: [TabWindow]) -> [CGWindowID] {
        // Needs a visible that SETTLES on one Space — see the precondition on the invariant above. A member
        // that isn't settled is likewise no evidence that it left.
        guard visible.isFullscreen, let home = settledSpace(visible) else { return [] }
        return members.filter { m in
            m.wid != visible.wid && m.isFullscreen && settledSpace(m).map { $0 != home } ?? false
        }.map { $0.wid }
    }
}
