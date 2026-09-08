import XCTest

/// Model-based tests: each test is a named `TestScenario` (a sequence of `TestUserAction`s) that the
/// `TestScenarioSimulator` drives through the reducer — and FUZZES over event orderings, so one written
/// scenario exercises many async-read interleavings (the races where the churn lives). Asserts the
/// correctness property no raw-state test can: **N real windows ⇒ N tiles**. No recordings, no random
/// action generation, no "seeds" — a test IS its action sequence; the variation is the interleaving.
final class TestScenarioSimulatorTests: XCTestCase {

    /// Run `scenario` under every combination of the two fuzz axes — read-landing order × handover order —
    /// and fail with the first combination + diagnosis that breaks.
    private func assertCorrect(_ scenario: TestScenario, duplicateTitles: Bool = false,
                               reusesTabWindows: Bool = true, tabBarResizesWindow: Bool = false,
                               composedWindowTitles: Bool = false,
                               preexisting: [TestInteractionModel.PreexistingWindow] = [],
                               requireCompleteGroups: Bool = false,
                               file: StaticString = #filePath, line: UInt = #line) {
        if let (ordering, handover, late, failures) = TestScenarioSimulator.fuzzFailure(
                scenario, duplicateTitles: duplicateTitles, reusesTabWindows: reusesTabWindows,
                tabBarResizesWindow: tabBarResizesWindow, composedWindowTitles: composedWindowTitles,
                preexisting: preexisting, requireCompleteGroups: requireCompleteGroups) {
            XCTFail("scenario [\(scenario.map { $0.description }.joined(separator: ", "))]\n"
                + "  broke under ordering .\(ordering), handover .\(handover), lateRead .\(late):\n  "
                + failures.joined(separator: "\n  "), file: file, line: line)
        }
    }

    // MARK: - core detection (steady states)

    func testStandaloneWindowsEachShowOneTile() {
        assertCorrect([.newWindow(pid: 1), .newWindow(pid: 1), .newWindow(pid: 2), .show])
    }

    func testWindowedTabbedWindowShowsOneTile() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0), .show])
    }

    func testFullscreenTabbedWindowShowsOneTile() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                       .enterFullscreen(window: 0), .show])
    }

    /// **: leaving fullscreen with a second window of the same app open.** Both windows are the model's
    /// default 900x600, which is the reporter's setup (two Chrome windows at one size) and the ordinary one —
    /// windows of an app are the same size far more often than not. On the way out the fullscreen window is
    /// Space-less, ordered out and already wearing that shared size for ~500ms, so every fact geometry keys
    /// on says "background tab of the other window"; folding it there marks it `isTabbed` and nothing ever
    /// re-splits an established group, so the tile does not come back.
    func testLeavingFullscreenKeepsBothWindowsOfTheApp() {
        assertCorrect([.newWindow(pid: 1), .newWindow(pid: 1), .enterFullscreen(window: 0), .show,
                       .exitFullscreen(window: 0), .show])
    }

    /// The same exit with the OTHER window carrying tabs — the fold has a real group to swallow it into.
    func testLeavingFullscreenNextToATabbedWindowKeepsBothTiles() {
        assertCorrect([.newWindow(pid: 1), .newWindow(pid: 1), .openTab(window: 1),
                       .enterFullscreen(window: 0), .show, .exitFullscreen(window: 0), .show])
    }

    /// Enter and leave repeatedly: a fold that only survives one round trip still hides the window for good.
    func testRepeatedFullscreenRoundTripsKeepBothWindows() {
        var s: TestScenario = [.newWindow(pid: 1), .newWindow(pid: 1), .show]
        for _ in 0..<4 { s += [.enterFullscreen(window: 0), .show, .exitFullscreen(window: 0), .show] }
        assertCorrect(s)
    }

    func testProbeSwitchAwayFromStandaloneFullscreen() {
        assertCorrect([.newWindow(pid: 1), .newWindow(pid: 1), .enterFullscreen(window: 0), .show,
                       .switchToSpace(window: 1), .show])
    }

    // MARK: - the churn class (many switches — rec24f)

    func testManyWindowedTabSwitchesStayOneTile() {
        var s: TestScenario = [.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0), .show]
        for i in 0..<8 { s += [.switchTab(window: 0, tab: i % 3), .show] }
        assertCorrect(s)
    }

    func testManyFullscreenTabSwitchesStayOneTile() {
        var s: TestScenario = [.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                               .enterFullscreen(window: 0), .show]
        for i in 0..<8 { s += [.switchTab(window: 0, tab: i % 3), .show] }
        assertCorrect(s)
    }

    func testFullscreenTabbedWindowCoexistsWithWindowedWindows() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0),
                       .newWindow(pid: 1), .openTab(window: 1),
                       .enterFullscreen(window: 0), .show,
                       .switchTab(window: 0, tab: 0), .show])
    }

    // MARK: - real bugs the model found + we fixed (pinned; each fuzzed over all orderings)

    /// Superseded-incoming-tab promotion: switching TO a tab arms its focus promotion (untracked
    /// visible-Space join); opening another tab supersedes it before discovery, and the stale promotion made
    /// it the group representative over the real active. Fixed by draining `pendingFocusPromotion` when an
    /// untracked wid backgrounds (`WindowEventReducer`).
    func testSupersededIncomingTabDoesNotBecomeRepresentative() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .switchTab(window: 0, tab: 0),
                       .openTab(window: 0), .show])
    }

    /// A fullscreen tab handover is valid in either notification order. When the outgoing representative
    /// leaves first, its held group waits for the exact untracked wid that joins the same Space.
    func testFullscreenNewTabInheritsItsGroupWhenLeaveArrivesFirst() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                       .enterFullscreen(window: 0), .switchTab(window: 0, tab: 1),
                       .openTab(window: 0), .show], duplicateTitles: true)
    }

    /// Two SEPARATE fullscreen windows of one app merged while the second entered fullscreen (transiently
    /// two-Spaced → fed the single-Space fullscreen fold). Fixed: the fold only folds Space-less members or
    /// members settled on the cluster's single settled Space (`TabGroupResolver.resolveGroup`).
    func testTwoSeparateFullscreenWindowsDoNotMergeDuringTransition() {
        assertCorrect([.newWindow(pid: 1), .newWindow(pid: 2), .enterFullscreen(window: 0),
                       .newWindow(pid: 1), .enterFullscreen(window: 2), .show])
    }

    /// A windowed group ANNEXED a fullscreen window (rec24c). Switching Spaces TO the fullscreen window makes
    /// it transiently Space-less, so it reads as a plausible inactive tab; with Finder's duplicate titles its
    /// title then matched a windowed group's AXTabGroup read, and `positionsCompatible`'s fullscreen waiver
    /// (there to claim a fullscreen window's frozen NON-fullscreen tabs) let the windowed group claim the
    /// fullscreen WINDOW — geometry's membership union then bridged everything into one mega-group, hiding
    /// real windows behind one tile. Fix: `matchSiblings` never claims a genuinely-fullscreen candidate (the
    /// fullscreen Space invariant). The deferred Space-transition settle is what puts the title read inside
    /// the gap under `.reversed`.
    func testWindowedGroupNeverAnnexesAFullscreenWindowDuringASpaceSwitch() {
        assertCorrect([.newWindow(pid: 1), .enterFullscreen(window: 0),
                       .newWindow(pid: 1), .openTab(window: 1), .openTab(window: 1), .show,
                       .switchToSpace(window: 0), .show],
                      duplicateTitles: true)
    }

    /// Adopting an inactive tab WIPED the fullscreen active's Space (rec24e). Switching twice inside a
    /// fullscreen window leaves the first switched-to tab inactive AND never tracked; the brute-force AX pass
    /// then adopts it Space-less, and discovery announced it to geometry as `newlyDiscovered` — the contract
    /// for "the brand-new ACTIVE tab that just took over". Geometry duly elected the Space-less adopted tab
    /// as the group's visible and backfilled its empty Space onto every member, wiping the genuine active's
    /// fullscreen Space: the group lost its screen claim and every member went phantom (zero tiles). Fix: an
    /// adopted inactive tab passes `newlyDiscovered: nil` (`WindowEventReducer.discoveryLanded`).
    func testAdoptedInactiveTabDoesNotWipeTheFullscreenActivesSpace() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                       .enterFullscreen(window: 0), .show,
                       .switchTab(window: 0, tab: 0), .switchTab(window: 0, tab: 1), .show],
                      reusesTabWindows: false)
    }

    /// The minted-wid tab-switch VANISH (rec24). When the tab's window no longer exists, Finder mints a fresh
    /// wid with no create event — the incoming tab announces itself only by joining the visible Space
    /// UNTRACKED — and in the gap before its discovery the group is invisible to the show's authoritative
    /// Space re-query: its minted active isn't tracked, its background tabs are on no Space, its ex-rep just
    /// genuinely left. The re-query wiped every borrowed Space, the group lost its screen claim, and the tile
    /// disappeared for ~800ms. Fix: the untracked visible-Space join is the replacement signal, so the
    /// outgoing rep is HELD through the gap (`shouldHoldVisibleThroughDiscovery`'s
    /// `hadRecentUntrackedSpaceJoin`).
    ///
    /// Two details are load-bearing, and BOTH had to be learned from a live capture (rec26) before this could
    /// be pinned. The second app's window keeps the re-query's map non-empty, so the read is authoritative
    /// rather than a no-op. And the MRU sort puts the outgoing representative AHEAD of its background tabs:
    /// `applyWindowSpaces` backfills a Space-less window from its active sibling, so a member walked before
    /// the rep would still find a live Space and rescue the group — only a rep wiped FIRST makes every member
    /// inherit its emptiness.
    func testMintedTabSwitchDoesNotDropTheTileWhileDiscoveryIsInFlight() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                       .newWindow(pid: 2), .show,
                       .switchTab(window: 0, tab: 0), .show],
                      reusesTabWindows: false)
    }

    /// The fullscreen MEGA-MERGE (rec21). Fullscreening a tabbed window resizes only its active tab; the
    /// background tabs stay frozen at the old windowed frame, and reconcile stamps the active's fullscreen
    /// flag onto them so they aren't mistaken for stray windows. A second window's AXTabGroup read then tried
    /// to claim those frozen tabs by title (Finder's duplicate titles), and because they wore the fullscreen
    /// flag, `positionsCompatible`'s fullscreen waiver dropped the frame check — so a group formed ACROSS
    /// three frames, hiding real windows behind one tile. Fix: the mirrored flag is MASKED at the kernel
    /// boundary (`TrackedWindowState.tabWindow`), so grouping sees a frozen tab for what it is — a
    /// non-fullscreen window at its own frame — and both frame protections still apply.
    func testFullscreenMirroredTabsAreNeverClaimedAcrossFrames() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0),
                       .newWindow(pid: 1), .openTab(window: 1), .show,
                       .enterFullscreen(window: 0), .show],
                      duplicateTitles: true)
    }

    /// The tab-switch CHURN (rec19). When the tab's own window is reused, the switch arrives as a Space-join
    /// from an ALREADY-GROUPED wid — and it is nothing more than a representative move: membership doesn't
    /// change. Treating the join as "this window left its group" made the group dissolve and re-form ~800ms
    /// later when a queued AX titles read landed, and the open switcher oscillated through several layouts
    /// per switch. Fix: one atomic `setGroupRepresentative` (`WindowEventReducer`), with the drag-out verdict
    /// deciding asynchronously whether the tab really left. Two same-app groups at different frames, as in
    /// the recording, so a churning group can also bleed into its neighbour.
    func testReusedTabSwitchIsOneAtomicRepresentativeSwap() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                       .newWindow(pid: 1), .openTab(window: 1), .show,
                       .switchTab(window: 0, tab: 0), .show,
                       .switchTab(window: 0, tab: 1), .show,
                       .switchTab(window: 1, tab: 0), .show],
                      duplicateTitles: true)
    }

    /// A second fullscreen window SWALLOWED the first's whole group (rec26, live capture: 14 members across
    /// two real windows). Every fullscreen window is screen-sized, so they all land in ONE size cluster; the
    /// newcomer's wid is transiently on both its old and new Space (UNSETTLED, so it contributes no Space
    /// evidence), and geometry then read the first window's Space-less background tabs as ITS tabs. The
    /// membership union dragged in the rest of that group — including its genuine on-Space active — leaving
    /// one tile standing for two real windows. Accumulated stale wids from earlier tab switches make the
    /// cluster large, which is why the live group had fourteen members.
    ///
    /// Two fixes, both restating "silence is not a verdict" (`TabGroupResolver`): an UNSETTLED visible folds
    /// nothing (folding is a claim about the visible's Space, and it hasn't got one yet), and a candidate
    /// whose group holds a member genuinely SETTLED on a Space the visible is not on is never claimed —
    /// two fullscreen Spaces mean two windows.
    func testSecondFullscreenWindowNeverSwallowsTheFirstsGroup() {
        var s: TestScenario = [.newWindow(pid: 1), .openTab(window: 0), .openTab(window: 0),
                               .enterFullscreen(window: 0), .show]
        for i in 0..<4 { s += [.switchTab(window: 0, tab: i % 3), .show] }   // accumulate stale wids
        s += [.newWindow(pid: 1), .enterFullscreen(window: 1), .show]
        assertCorrect(s, duplicateTitles: true, reusesTabWindows: false)
    }

    // MARK: - cold start (AltTab launched into a desktop that already existed)

    /// Every other scenario in this file starts from nothing and watches every window from birth. That is the
    /// one condition under which a history-based detector cannot fail, because history covers everything —
    /// and it is not the condition AltTab actually launches in. These seed a world with `preexisting` and
    /// emit no event for it: the first `show` is the launch discovery, and the only facts available are the
    /// ones readable NOW (the AXTabGroup, the frames).
    ///
    /// They all assert `requireCompleteGroups`, and that is the point of them. The tile-count property is
    /// blind here: a background tab that never got grouped is Space-less, therefore phantom, therefore
    /// hidden, so a window whose tabs were never linked at all still shows exactly one tile and passes.
    /// Only asking whether the GROUP formed distinguishes "tab detection worked" from "the tabs happened to
    /// be invisible" — and "Group tabs: separate window for each tab" renders the difference.
    func testPreexistingStandaloneWindowsEachShowOneTile() {
        assertCorrect([.show, .show], preexisting: [.init(pid: 1), .init(pid: 1), .init(pid: 2)],
                      requireCompleteGroups: true)
    }

    func testPreexistingTabbedWindowIsGroupedAtLaunch() {
        assertCorrect([.show, .show], preexisting: [.init(pid: 1, tabs: 3)], requireCompleteGroups: true)
    }

    /// Finder names every tab after its folder, so a pre-existing group's titles collide — the claim the
    /// launch-time AXTabGroup read has to make with nothing else to go on.
    func testPreexistingTabbedWindowWithDuplicateTitlesIsGroupedAtLaunch() {
        assertCorrect([.show, .show], duplicateTitles: true, preexisting: [.init(pid: 1, tabs: 4)],
                      requireCompleteGroups: true)
    }

    /// Two tabbed windows of ONE app, all tabs sharing a title: the pair that has to stay apart with no
    /// history to separate them. They differ only by frame (macOS cascades windows), which is exactly the
    /// fact a cold start still has.
    func testPreexistingSameAppTabbedWindowsStayApartAtLaunch() {
        assertCorrect([.show, .show], duplicateTitles: true,
                      preexisting: [.init(pid: 1, tabs: 3), .init(pid: 1, tabs: 2)],
                      requireCompleteGroups: true)
    }

    /// A window already fullscreen at launch exposes no readable AXTabGroup, so geometry is the only thing
    /// left. It suffices while the background tabs wear the fullscreen frame — which they do as soon as the
    /// user has switched tabs once since fullscreening, since a tab freezes at the frame it last had while
    /// active.
    func testPreexistingFullscreenTabbedWindowIsGroupedAtLaunch() {
        assertCorrect([.show, .show], preexisting: [.init(pid: 1, tabs: 3, isFullscreen: true), .init(pid: 2)],
                      requireCompleteGroups: true)
    }

    /// KNOWN GAP, and it is GREEN on purpose: it asserts the tile count, which is correct, not
    /// `requireCompleteGroups`, which is not. See `TestScenarioSimulatorSpecs.md`.
    /// The same window, fullscreened and NOT switched since, so its background tabs are still frozen at the
    /// pre-fullscreen windowed frame. NEITHER source reaches them: AX exposes no tab group for a fullscreen
    /// window, and the frames disagree by design, so the tabs are in a different size cluster from their own
    /// active and `geometryGroups` never clusters them. They stay ungrouped — no event will ever arrive to
    /// say otherwise, because everything that would have said so happened before we were running.
    ///
    /// The default tile count still looks perfect, which is why this went unnoticed: an ungrouped background
    /// tab is Space-less ⇒ phantom ⇒ hidden, so the window shows exactly one tile. It is "Group tabs:
    /// separate window for each tab" that renders the defect — those tabs are simply missing from the
    /// switcher until the user switches to one.
    ///
    /// **The tab-COUNT fix does not work, so don't reach for it.** The shape looks right — a fullscreen active
    /// reporting N tabs with N-1 unclaimed Space-less same-app windows — but `tabCount` is written only from
    /// `tabGroupInfo`, which reads DIRECT children, and a cold-start fullscreen window has never had a
    /// windowed read, so its count is 0 for every app. Nor is the tab bar simply unreachable: it is reachable
    /// by hit-testing the separate NSToolbarFullScreenWindow, and descending into AXGroup children is not the
    /// way in (it works for Finder and Script Editor, not Terminal or TextEdit, and that app-dependent
    /// asymmetry lets a fullscreen active reach `matchSiblings`).
    ///
    /// So this stays ACCEPTED. The gap is "not listed in separate-tabs mode until first visit", and it
    /// self-heals on that visit. Closing it means implementing the hit-test chain, which needs the window on
    /// screen and costs one CGS call plus up to a dozen AX hit-tests per fullscreen window per read.
    /// The same window, fullscreened and NOT switched since, so its background tabs are still frozen at the
    /// pre-fullscreen windowed frame. Nothing groups them: AX reads no tab group for a fullscreen window (by
    /// design — see `AXUIElement.tabGroupInfo`) and the frames put them in a different size cluster.
    ///
    /// **This is ACCEPTED behaviour, not a defect**, which is why it asserts the tile count and not
    /// `requireCompleteGroups`. An un-grouped background tab is Space-less ⇒ phantom ⇒ hidden, so the window
    /// still shows exactly one tile and the default mode is correct. Only "separate window for each tab" can
    /// tell, and there the tab is missing until the user visits it once — at which point it joins the
    /// fullscreen Space (an event we DO see), gets discovered, and is resized to the fullscreen frame, so it
    /// folds into the cluster and stays grouped. The gap is "not listed until first visit", and it self-heals.
    func testPreexistingUnswitchedFullscreenTabsStillShowOneTile() {
        assertCorrect([.show, .show],
                      preexisting: [.init(pid: 1, tabs: 3, isFullscreen: true, tabsFrozenAtWindowedFrame: true),
                                    .init(pid: 2)])
    }

    /// #5785's remaining symptom, from drauzio's TABDIAG capture: opening the FIRST tab in a standalone
    /// window shows TWO Terminal tiles for one window. The tab bar grows the window, so the incoming tab
    /// reads 1017x610 while the outgoing keeps 1017x565 — same app, same position, same width, different
    /// height — and every clustering rule keys on size, so the pair never meets in one cluster and geometry
    /// cannot group them. It heals only when the user switches back and the stale tab gets a resize event.
    ///
    /// Green before this test existed because the model gave every window and every tab ONE size, which no
    /// real tabbed window ever has. See `TestInteractionModel.tabBarResizesWindow`.
    func testFirstTabInAStandaloneWindowIsOneTileDespiteTheTabBarResize() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .show],
                      tabBarResizesWindow: true, composedWindowTitles: true)
    }

    /// The same shape with titles that DO match: the title path names the sibling and the group forms
    /// despite the frames disagreeing. Isolates which of the two facts the fix has to handle, and pins that
    /// the tab-bar resize alone is survivable.
    func testFirstTabIsOneTileWhenTitlesStillMatch() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .show], tabBarResizesWindow: true)
    }

    // MARK: - the generator (random scenarios, shrunk to a minimal repro)

    /// A FIXED range of seeds, so this is an ordinary deterministic regression test rather than a flaky
    /// explorer: seed N always yields the same scenario. It exists because the scenarios above only cover
    /// races we thought of — this one covers the rest, and a far less faithful version of the model still
    /// found two shipped bugs this way. A failure prints the scenario already SHRUNK by delta-debug, usually
    /// to four or five actions you can paste straight into a new pinned test.
    ///
    /// When it does fail: rule out a model faithfulness gap FIRST. Of the first three findings, two were the
    /// model's fault (a `switchToSpace` onto the Space you are already on emitted a transition; a deferred
    /// Space settle re-added the wid captured when the transition STARTED rather than the tab active when it
    /// finished) and only the third was the app's.
    func testGeneratedScenariosStayCorrect() {
        if let report = TestScenarioGenerator.sweepFailure(seeds: 0..<150) { XCTFail(report) }
    }



    /// FIXED, and now a live regression guard — this used to be a red-by-design oracle.
    /// Pressing ⌘T inside one fullscreen window backgrounds its active tab, which goes Space-less for a beat.
    /// Every fullscreen window is screen-sized, so a SECOND fullscreen window sits in the same size cluster
    /// and — holding its own Space — is picked as the cluster's visible, adopting the first window's outgoing
    /// tab. `inferTabGroupsByGeometry`'s membership union can then bridge in the rest, which is the shape of
    /// the 14-member group seen live (rec26).
    ///
    /// It was unfixable while the kernel saw only CURRENT facts: the outgoing tab is then indistinguishable
    /// from a brand-new tab (both Space-less, same size, same app, no AX link yet), and tightening the
    /// fullscreen confirmation clause to require `newlyDiscovered` was tried and reverted, since 13 corpus
    /// tests need a fullscreen visible to group without it. The distinguishing fact is HISTORY — the tab just
    /// left a DIFFERENT fullscreen Space — and that design change was made: `lastLeftSpaceId` is carried into
    /// the kernel projection and `settledOnAnotherWindowsSpace` rejects the claim on it.
    ///
    /// Verified to bite (2026-07-27): disabling that clause fails this test, generator seed 6, and
    /// `testNewFullscreenTabInheritsTheTileFromTheTabItReplaced`.
    func testFullscreenTabBackgroundingIsNotStolenByAnotherFullscreenWindow() {
        assertCorrect([.newWindow(pid: 1), .newWindow(pid: 1), .enterFullscreen(window: 0),
                       .enterFullscreen(window: 1), .openTab(window: 1), .show],
                      duplicateTitles: true, reusesTabWindows: false)
    }

    /// The tile flashed the app ICON (rec27, reported after the vanish was fixed: "screenshot → app icon →
    /// screenshot"). Opening a tab inside one of TWO fullscreen windows of an app leaves the outgoing tab
    /// Space-less; `geometryGroups` partitions a multi-Space fullscreen cluster by Space and used to DROP
    /// Space-less members, since it could not tell which window they had backgrounded from. So the incoming
    /// tab formed no group, inherited no thumbnail from the tab it replaced, and drew the app icon until its
    /// own capture landed. `lastLeftSpaceId` supplies the attribution the partition was missing.
    func testNewFullscreenTabInheritsTheTileFromTheTabItReplaced() {
        assertCorrect([.newWindow(pid: 1), .enterFullscreen(window: 0),
                       .newWindow(pid: 2), .newWindow(pid: 1), .show,
                       .enterFullscreen(window: 2), .openTab(window: 2), .show],
                      duplicateTitles: true, reusesTabWindows: false)
    }

    /// A MINTED tab switch keeps the window's group (generator seed 7). When Finder mints a fresh wid for the
    /// incoming tab instead of reusing its window, nothing links it to the tabs it joins: fullscreen exposes
    /// no AXTabGroup, and its frozen siblings sit at the PRE-fullscreen size, so they aren't even in the same
    /// geometry cluster. The window therefore showed two tiles — the new active, and the orphaned old group.
    ///
    /// The link is causal, not geometric: an untracked wid joins the visible Space and the representative
    /// leaves it a beat later. The app already recognised that pair (it is what arms the hold); now the
    /// minted wid also INHERITS the group, exactly as a reused wid does via `setGroupRepresentative`. The
    /// drag-out verdict remains the escape hatch if the frames later say the tab was torn out.
    func testMintedTabSwitchInheritsTheGroupItTookOver() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .switchTab(window: 0, tab: 0),
                       .enterFullscreen(window: 0), .show],
                      reusesTabWindows: false)
    }

    /// The tile flashed the app ICON on a REUSED tab switch (generator seed 142; matches a live report of a
    /// flicker when focusing a fullscreen window and summoning the switcher). A reused wid becomes the
    /// group's representative immediately via the atomic swap on its Space-join — but that path did not hand
    /// it the outgoing tab's pixels, which only happened inside `reconcile`. Until its own capture landed the
    /// tile drew the app icon, since `TileView` does that whenever `thumbnail == nil`.
    func testReusedTabSwitchInheritsTheOutgoingTabsPixels() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .enterFullscreen(window: 0),
                       .newWindow(pid: 2), .show, .switchToSpace(window: 0),
                       .switchTab(window: 0, tab: 0), .show])
    }

    /// A minted tab switch whose incoming wid is SUPERSEDED before its discovery lands (generator seed 106).
    /// The superseded wid carried the group's membership (`pendingGroupInheritance`, armed when it displaced
    /// the outgoing tab), and draining it on supersede orphaned the whole pre-fullscreen generation as its own
    /// group: one real window, two groups, so the orphan's representative stood as a permanent SECOND TILE.
    /// It is HELD, which exempts it from the phantom rule, and only the 20s safety cap ended it live.
    func testSupersededMintedTabHandsItsGroupToTheWidThatSupersededIt() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .switchTab(window: 0, tab: 0),
                       .enterFullscreen(window: 0), .switchTab(window: 0, tab: 1), .show],
                      reusesTabWindows: false)
    }

    /// The same supersede, reached by OPENING a tab rather than switching (generator seed 125, duplicate
    /// titles). Here the orphaned generation still holds a LIVE background tab, so the second tile is a real
    /// tab of the window shown twice rather than a corpse.
    func testSupersededMintedTabDoesNotStrandALiveBackgroundTabInAnOrphanGroup() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .switchTab(window: 0, tab: 0),
                       .enterFullscreen(window: 0), .openTab(window: 0), .show],
                      duplicateTitles: true, reusesTabWindows: false)
    }

    /// The SAME membership drain, reached without any supersede at all (generator seed 106's reachable repro,
    /// found once the shrinker stopped minting scenarios no user can perform). Leaving a fullscreen window and
    /// coming back makes its still-undiscovered active tab drop its Space for the length of the animation, and
    /// draining its pending membership there stranded the rest of the window as an orphan group — one window,
    /// two tiles. Nothing replaced the tab, so its membership must simply stay with it until it is discovered.
    func testActiveTabKeepsItsPendingGroupAcrossASpaceTransition() {
        assertCorrect([.newWindow(pid: 1), .openTab(window: 0), .switchTab(window: 0, tab: 0),
                       .enterFullscreen(window: 0), .newWindow(pid: 1), .switchToSpace(window: 0), .show],
                      reusesTabWindows: false)
    }
}
