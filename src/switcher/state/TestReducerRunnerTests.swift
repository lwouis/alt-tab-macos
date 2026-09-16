import XCTest

/// Smoke tests for the replay harness itself: a clean end-to-end replay of the new-tab creation race
/// (create → 1326 → hold → discovery → atomic claim → hold release) produces no violations, and each
/// hand-corrupted state trips exactly the invariant built to catch it. The real recordings live in
/// `ReplayScenariosTests`.
final class TestReducerRunnerTests: XCTestCase {

    private func window(_ wid: CGWindowID, pid: pid_t = 500, title: String = "~",
                        size: CGSize? = CGSize(width: 757, height: 583),
                        position: CGPoint? = CGPoint(x: 683, y: 101),
                        spaceIds: [UInt64] = [], spaceIsBorrowed: Bool = false,
                        lastFocusOrder: Int = 0) -> TrackedWindow {
        TrackedWindow(id: "wid-\(wid)", wid: wid, pid: pid, title: title, size: size, position: position,
            spaceIds: spaceIds, spaceIndexes: [], isOnAllSpaces: false, spaceIsBorrowed: spaceIsBorrowed,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: false, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: lastFocusOrder,
            creationOrder: Int(wid), hasThumbnail: true)
    }

    private func state(windows: [TrackedWindow], frontmostPid: pid_t? = 500) -> TrackedWindowState {
        var s = TrackedWindowState()
        s.windows = windows
        s.apps[500] = TrackedApp(state: ApplicationState(pid: 500, bundleIdentifier: "com.apple.Terminal",
            localizedName: "Terminal", isHidden: false), isActive: true)
        s.visibleSpaces = [3]
        s.currentSpaceId = 3
        s.spaceIndexById = [3: 1]
        s.frontmostPid = frontmostPid
        return s
    }

    /// The creation race, replayed clean: the old active's 1326 lands before the new tab's discovery; the
    /// hold keeps its tile through the gap; the new tab's AX titles claim it atomically; the hold releases
    /// once the claim lands. Every step must satisfy every invariant.
    func testNewTabCreationRaceReplaysWithoutViolations() {
        let old = window(100, spaceIds: [3], lastFocusOrder: 0)
        let harness = TestReducerRunner(initial: state(windows: [old]))
        harness.run([
            .input(.windowCreated(wid: 101, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.1, inSpaceTransition: false)),
            .track(window(101, spaceIds: [3])),
            .input(.discoveryLanded(wid: 101, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [3], isOrderedIn: true, tabTitles: ["~", "~"], tabGroupToken: nil)),
            .input(.holdReleaseCheck(wid: 100, attempt: 0)),
        ])
        XCTAssertEqual(harness.violations, [])
        // the pair grouped atomically, the new tab represents, the old active is its hidden background tab
        XCTAssertEqual(harness.state.groups.siblingWids(of: 101)?.sorted(), [100, 101])
        XCTAssertFalse(harness.state.groups.isTabbed(101))
        XCTAssertTrue(harness.state.groups.isTabbed(100))
        // the hold released the moment the claim landed (isTabbed), not at the safety cap
        XCTAssertTrue(harness.state.held.isEmpty)
        // the new tab was promoted to the front of the MRU
        XCTAssertEqual(harness.state.window(101)?.lastFocusOrder, 0)
    }

    /// A tabbed member holding a GENUINE Space (not borrowed, not held, no creation in flight) is the
    /// claimed-real-window bug class (rec10's theft); the invariant must flag it.
    func testHarnessFlagsAClaimedOnSpaceWindow() {
        var s = state(windows: [window(1, spaceIds: [3], lastFocusOrder: 0),
                                window(2, spaceIds: [3], lastFocusOrder: 1)])
        s.formGroup([1, 2], representative: 1, reason: "test")
        let harness = TestReducerRunner(initial: s)
        XCTAssertTrue(harness.violations.contains { $0.contains("GENUINE Space") && $0.contains("wid-2") },
                      "violations were: \(harness.violations)")
    }

    /// A non-fullscreen group spanning two frames is the cross-frame theft (rec11/rec12); the invariant
    /// must flag it. (The borrowed marker keeps the on-Space check quiet, isolating the frame check.)
    func testHarnessFlagsAGroupSpanningDistinctFrames() {
        var s = state(windows: [window(1, spaceIds: [3], lastFocusOrder: 0),
                                window(2, position: CGPoint(x: 712, y: 130), spaceIds: [3],
                                       spaceIsBorrowed: true, lastFocusOrder: 1)])
        s.formGroup([1, 2], representative: 1, reason: "test")
        let harness = TestReducerRunner(initial: s)
        XCTAssertTrue(harness.violations.contains { $0.contains("distinct frames") },
                      "violations were: \(harness.violations)")
    }

    /// The focused window claimed as a background tab (rec18's ejection) must be flagged.
    func testHarnessFlagsAHiddenFocusedWindow() {
        var s = state(windows: [window(1, spaceIds: [], lastFocusOrder: 0),
                                window(2, spaceIds: [3], spaceIsBorrowed: false, lastFocusOrder: 1)])
        s.formGroup([1, 2], representative: 2, reason: "test")
        let harness = TestReducerRunner(initial: s)
        XCTAssertTrue(harness.violations.contains { $0.contains("focused window wid-1 is hidden") },
                      "violations were: \(harness.violations)")
    }

    /// A group whose representative is not the most recently focused presentable member (the rec19 churn
    /// shape) must be flagged.
    func testHarnessFlagsARepresentativeThatIgnoresFocus() {
        var s = state(windows: [window(1, spaceIds: [3], lastFocusOrder: 0),
                                window(2, spaceIds: [], lastFocusOrder: 1)])
        s.formGroup([1, 2], representative: 2, reason: "test")
        let harness = TestReducerRunner(initial: s)
        XCTAssertTrue(harness.violations.contains { $0.contains("focus says #1") },
                      "violations were: \(harness.violations)")
    }

    /// A Space-less, ungrouped, unheld window shown as a tile (rec20's orphaned ex-representative, after
    /// its borrow was cleared it must hide) — the phantom rule must hide it; a held one is exempt.
    func testHarnessSpacelessStrayIsHiddenAndHeldIsExempt() {
        let stray = window(1, spaceIds: [], lastFocusOrder: 0)
        var s = state(windows: [stray, window(2, spaceIds: [3], lastFocusOrder: 1)], frontmostPid: nil)
        // Space-less + ungrouped ⇒ phantom ⇒ hidden: no violation
        XCTAssertEqual(TestReducerRunner(initial: s).violations, [])
        // held ⇒ exempt from phantom ⇒ shown, still no violation (the hold is the sanctioned exemption)
        s.held = [1]
        XCTAssertEqual(TestReducerRunner(initial: s).violations, [])
    }

    /// Measured live (2026-08-02): "Move Tab to New Window", then the group re-forms around the two members that
    /// stayed. The exact-set form ungroups the window the user tore out, and ungrouping used to STRIP the
    /// Space the group had lent it. An empty `spaceIds` is the strong phantom signal — "CGS places this
    /// window nowhere" — so we asserted that about a window CGS had had on Space 3 the whole time, and its
    /// tile vanished for 515ms until the next `spacesSynced` re-read the truth.
    ///
    /// GROUND TRUTH: leaving a group drops no Space. The borrow MARKER stays, which is what rec20 actually
    /// needs (claim rules read it, so the ex-member never looks genuinely on-screen); only real evidence — a
    /// `spacesSynced` map miss, a 1325/1326 delta — may empty the Space, and that is also what retires a
    /// member that is genuinely gone.
    func testLeavingAGroupKeepsTheLentSpaceSoALiveWindowIsNotHidden() {
        var s = state(windows: [window(1, spaceIds: [3], lastFocusOrder: 2),
                                window(2, spaceIds: [3], spaceIsBorrowed: true, lastFocusOrder: 0),
                                window(3, spaceIds: [3], lastFocusOrder: 1)])
        s.formGroup([1, 2], representative: 2, reason: "test")
        s.formGroup([1, 3], representative: 1, reason: "test")   // exact-set: 2 is ungrouped
        let tornOut = s.window(2)!
        XCTAssertEqual(tornOut.spaceIds, [3],
                       "leaving a group must not assert 'CGS places this window nowhere' on its own")
        XCTAssertTrue(tornOut.spaceIsBorrowed,
                      "the Space stays OUR annotation, so every claim rule still sees through it")
        XCTAssertFalse(s.isPhantom(tornOut), "the window the user just tore out must keep its tile")
    }

    /// A tab minted by a switch, then FULLSCREENED before its discovery lands, must keep the fullscreen Space
    /// it was given — not be forced Space-less as a backgrounded tab.
    ///
    /// Both look the same to `pendingSpaceRemoval`, which remembers that an UNTRACKED wid left a Space:
    /// a backgrounding tab leaves its Space and stays nowhere, while a window going fullscreen leaves its old
    /// Space having just joined a new one. Remembering only the FACT and not the SPACE, discovery forced the
    /// brand-new fullscreen active Space-less, so it went phantom and its window showed no tile at all
    /// (generator seeds 7/11/15). The removal now carries its Space and only counts when the query agrees —
    /// nothing, or the same Space it left (which the per-window CGS query reports stale right after
    /// backgrounding).
    func testMintedTabThatGoesFullscreenBeforeDiscoveryKeepsItsSpace() {
        var s = TrackedWindowState()
        s.apps[1] = TrackedApp(state: ApplicationState(pid: 1, bundleIdentifier: "com.apple.finder",
            localizedName: "Finder", isHidden: false), isActive: true)
        s.visibleSpaces = [100]
        s.currentSpaceId = 100
        s.spaceIndexById = [1: 1, 100: 2]
        s.frontmostPid = 1
        let harness = TestReducerRunner(initial: s)
        harness.run([
            // the minted tab announces itself on the windowed Space, still untracked
            .input(.spaceMembershipChanged(wid: 5, spaceId: 1, added: true, now: 100.0, inSpaceTransition: false)),
            // the user fullscreens: it joins the fullscreen Space, then leaves the windowed one
            .input(.spaceMembershipChanged(wid: 5, spaceId: 100, added: true, now: 100.1, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 5, spaceId: 1, added: false, now: 100.2, inSpaceTransition: false)),
            // discovery finally lands, and CGS agrees it is on the fullscreen Space
            .track(TrackedWindow(id: "wid-5", wid: 5, pid: 1, title: "lwouis",
                size: CGSize(width: 1440, height: 900), position: .zero, spaceIds: [100], spaceIndexes: [],
                isOnAllSpaces: false, spaceIsBorrowed: false, isFullscreen: true, isFullscreenMirrored: false,
                isMinimized: false, isMainWindow: false, isWindowlessApp: false, cgsPhantomLatch: false,
                lastLeftSpaceId: nil, lastFocusOrder: 0, creationOrder: 5, hasThumbnail: true)),
            .input(.discoveryLanded(wid: 5, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [100], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(harness.state.window(5)?.spaceIds, [100])
        XCTAssertFalse(harness.state.isPhantom(harness.state.window(5)!))
    }

    /// rec27 (2026-07-18, `tabdiag_rec27_fullscreen_burst_flicker.log` @ 19:36:51): bursting ⌘T inside a
    /// FULLSCREEN Finder window made its tile disappear for ~2.5s. The burst's new tabs churn as UNTRACKED
    /// wids joining and leaving the fullscreen Space, so when the tracked active's own 1326 lands, AltTab
    /// holds it visible — correctly — and then released the hold ~200ms later because a SECOND fullscreen
    /// Finder window, sitting on another Space at the identical 1440×900@0,0 frame, passed as its
    /// "replacement". Nothing could be drawn for the window, so it went phantom and the tile vanished until
    /// a later discovery (91491) rebuilt it.
    ///
    /// Transcribed from the capture rather than re-run: the fix is judged here, offline.
    func testFullscreenBurstKeepsTheHeldTileWhileAnotherFullscreenWindowExists() {
        let pid: pid_t = 779
        func fullscreenWindow(_ wid: CGWindowID, space: UInt64, focus: Int) -> TrackedWindow {
            TrackedWindow(id: "wid-\(wid)", wid: wid, pid: pid, title: "lwouis",
                size: CGSize(width: 1440, height: 900), position: .zero, spaceIds: [space], spaceIndexes: [],
                isOnAllSpaces: false, spaceIsBorrowed: false, isFullscreen: true, isFullscreenMirrored: false,
                isMinimized: false, isMainWindow: false, isWindowlessApp: false, cgsPhantomLatch: false,
                lastLeftSpaceId: nil, lastFocusOrder: focus, creationOrder: Int(wid), hasThumbnail: true)
        }
        var s = TrackedWindowState()
        s.windows = [
            fullscreenWindow(91409, space: 5335, focus: 0),   // the fullscreen window being burst into
            fullscreenWindow(75934, space: 4594, focus: 1),    // a SEPARATE fullscreen window, same frame
        ]
        s.apps[pid] = TrackedApp(state: ApplicationState(pid: pid, bundleIdentifier: "com.apple.finder",
            localizedName: "Finder", isHidden: false), isActive: true)
        s.visibleSpaces = [5335]
        s.currentSpaceId = 5335
        s.spaceIndexById = [5335: 3, 4594: 2, 3628: 1]
        s.frontmostPid = pid
        let harness = TestReducerRunner(initial: s)
        harness.run([
            // 19:36:51.242 the burst's tabs churn as untracked wids on the fullscreen Space
            .input(.spaceMembershipChanged(wid: 91483, spaceId: 5335, added: true, now: 100.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 91484, spaceId: 5335, added: true, now: 100.001, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 91410, spaceId: 5335, added: false, now: 100.002, inSpaceTransition: false)),
            // 19:36:51.245 the tracked active backgrounds behind the newest tab ⇒ the hold arms
            .input(.spaceMembershipChanged(wid: 91409, spaceId: 5335, added: false, now: 100.003, inSpaceTransition: false)),
            // 19:36:51.499 the Spaces re-query confirms it is on no Space (CGS probed it: empty)
            .input(.spacesSynced(windowToSpaces: [75934: [4594]], queried: [91409, 75934],
                answered: [91409, 75934], placedByWindowServer: [], topologyChanged: false)),
            // ~19:36:51.6 the hold-release check fires while the burst is still going
            .input(.holdReleaseCheck(wid: 91409, attempt: 0)),
        ])
        XCTAssertEqual(harness.violations, [])
        // the tile is still standing: held, therefore not phantom, therefore drawn
        XCTAssertTrue(harness.state.held.contains(91409), "trace: \(harness.trace)")
        XCTAssertFalse(harness.state.isPhantom(harness.state.window(91409)!))
        // and the unrelated fullscreen window is untouched on its own Space
        XCTAssertEqual(harness.state.window(75934)?.spaceIds, [4594])
    }

    private func finderApp(_ s: inout TrackedWindowState, pid: pid_t = 779) {
        s.apps[pid] = TrackedApp(state: ApplicationState(pid: pid, bundleIdentifier: "com.apple.finder",
            localizedName: "Finder", isHidden: false), isActive: true)
        s.frontmostPid = pid
    }

    private func win(_ wid: CGWindowID, size: CGSize, position: CGPoint = .zero, spaceIds: [UInt64],
                     borrowed: Bool = false, fullscreen: Bool = false, leftSpace: UInt64? = nil,
                     focus: Int = 0, title: String = "lwouis") -> TrackedWindow {
        TrackedWindow(id: "wid-\(wid)", wid: wid, pid: 779, title: title, size: size, position: position,
            spaceIds: spaceIds, spaceIndexes: [], isOnAllSpaces: false, spaceIsBorrowed: borrowed,
            isFullscreen: fullscreen, isFullscreenMirrored: false, isMinimized: false, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: false, lastLeftSpaceId: leftSpace, lastFocusOrder: focus,
            creationOrder: Int(wid), hasThumbnail: true)
    }

    /// A representative that goes Space-less must not borrow a Space that CONTRADICTS the one it just left.
    /// Background tabs carry borrowed Spaces, and a tab left over from the window's pre-fullscreen life still
    /// carries the OLD windowed Space. Borrowing that back put a fullscreen group on a Space it had long
    /// left; its own tabs then read as "genuinely on-screen" and could no longer be claimed, so the window
    /// flashed two tiles. Requiring a GENUINE source instead is too strict — every tab of a windowed window
    /// has a borrowed Space, and refusing those makes the representative vanish mid-swap.
    func testRepresentativeDoesNotBorrowASpaceItJustLeft() {
        var s = TrackedWindowState()
        finderApp(&s)
        let fs = CGSize(width: 1440, height: 900)
        s.windows = [
            win(1, size: fs, spaceIds: [1], borrowed: true, fullscreen: true, focus: 1),   // stale pre-fullscreen borrow
            win(2, size: fs, spaceIds: [], fullscreen: true, leftSpace: 100, focus: 0),     // the rep, mid-swap
        ]
        s.visibleSpaces = [100]
        s.currentSpaceId = 100
        s.spaceIndexById = [1: 1, 100: 2]
        s.windows[1].spaceIds = [100]        // the rep still holds its fullscreen Space; the 1326 is next
        s.windows[1].lastLeftSpaceId = nil
        s.formGroup([2, 1], representative: 2, reason: "fixture")
        let harness = TestReducerRunner(initial: s)
        // the Space switch takes the fullscreen window off its Space for a beat
        harness.run([.input(.spaceMembershipChanged(wid: 2, spaceId: 100, added: false, now: 100.0,
                                                    inSpaceTransition: false))])
        XCTAssertNotEqual(harness.state.window(2)?.spaceIds, [1],
                          "borrowed the stale Space of the window's pre-fullscreen life: \(harness.trace)")
    }

    /// The minted-tab pairing must require the SAME Space. It is a time-based pair — an untracked wid joins,
    /// a representative leaves a beat later — so without matching the Space, a tab joining one window's
    /// fullscreen Space gets paired with an unrelated window's representative leaving the windowed Space, and
    /// the two windows are merged into one group.
    func testMintedTabPairingIgnoresARepresentativeLeavingAnotherSpace() {
        var s = TrackedWindowState()
        finderApp(&s)
        s.windows = [
            win(10, size: CGSize(width: 900, height: 600), spaceIds: [1], focus: 0),          // windowed window
            win(11, size: CGSize(width: 900, height: 600), spaceIds: [1], borrowed: true, focus: 1),
        ]
        s.visibleSpaces = [1, 100]
        s.currentSpaceId = 100
        s.spaceIndexById = [1: 1, 100: 2]
        s.formGroup([10, 11], representative: 10, reason: "fixture")
        let harness = TestReducerRunner(initial: s)
        harness.run([
            // an untracked tab joins the FULLSCREEN Space of some other window
            .input(.spaceMembershipChanged(wid: 99, spaceId: 100, added: true, now: 100.0, inSpaceTransition: false)),
            // the WINDOWED window's representative leaves ITS Space a beat later — unrelated
            .input(.spaceMembershipChanged(wid: 10, spaceId: 1, added: false, now: 100.01, inSpaceTransition: false)),
            .track(win(99, size: CGSize(width: 1440, height: 900), spaceIds: [100], fullscreen: true, focus: 0)),
            .input(.discoveryLanded(wid: 99, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [100], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.violations, [])
        XCTAssertNil(harness.state.groups.groupId(of: 99).flatMap { gid in
            harness.state.groups.membersByGroup[gid]?.contains(10) == true ? gid : nil
        }, "merged two windows via the time-based pairing: \(harness.trace)")
    }

    /// Reported live (2026-07-22): on a FULLSCREEN Finder window, switching the visible tab to "Movies"
    /// then immediately opening the switcher showed the PREVIOUS tab; closing and reopening fixed it. A
    /// fullscreen switch to a REUSED background wid reaches physical discovery with no promotion attached —
    /// no 808, no create, and (the wid untracked at its Space-join) no `pendingFocusPromotion` — so the
    /// switched-to tab is learned only via the show's AX scan, which `.track`s it at the BACK of the MRU.
    /// Geometry correctly
    /// elects it as the group's visible (`newlyDiscovered`), but `groupRepresentative` then picks by focus
    /// order, so a background sibling focused more recently won the tile until it was ordered out on close.
    /// Discovery must front the elected-visible newly-discovered tab so it represents its group at once.
    func testFullscreenTabSwitchToAReusedWidFrontsItAtDiscovery() {
        var s = TrackedWindowState()
        finderApp(&s)
        let fs = CGSize(width: 1440, height: 900)
        // The group's other tabs as they stand before the switch is discovered: Space-less background tabs
        // of the fullscreen window, both focused MORE RECENTLY than the tab about to be discovered. (They're
        // ungrouped + Space-less here → phantom-hidden, the state right after their old active backgrounded;
        // the currently-focused window is a separate on-screen window, so neither hidden tab is the front.)
        s.windows = [
            win(200, size: CGSize(width: 900, height: 600), spaceIds: [22], focus: 0),  // the current front
            win(39, size: fs, spaceIds: [], fullscreen: true, focus: 1),   // more recent than 134 → would wrongly win the tile
            win(141, size: fs, spaceIds: [], fullscreen: true, focus: 2),
        ]
        s.visibleSpaces = [22]
        s.currentSpaceId = 22
        s.spaceIndexById = [22: 1]
        let harness = TestReducerRunner(initial: s)
        // The AX scan discovers the switched-to "Movies" tab: tracked at the BACK of the MRU, on the
        // fullscreen Space, with NO preceding focus / create / Space-join event to have fronted it.
        harness.run([
            .track(TrackedWindow(id: "wid-134", wid: 134, pid: 779, title: "Movies", size: fs, position: .zero,
                spaceIds: [22], spaceIndexes: [], isOnAllSpaces: false, spaceIsBorrowed: false,
                isFullscreen: true, isFullscreenMirrored: false, isMinimized: false, isMainWindow: false,
                isWindowlessApp: false, cgsPhantomLatch: false, lastLeftSpaceId: nil, lastFocusOrder: 0,
                creationOrder: 134, hasThumbnail: true)),
            .input(.discoveryLanded(wid: 134, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [22], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
        // The switched-to tab represents its group — the switcher shows "Movies", not a background sibling.
        let gid = harness.state.groups.groupId(of: 134)
        XCTAssertNotNil(gid, "the fullscreen tabs grouped: \(harness.trace)")
        XCTAssertEqual(gid.flatMap { harness.state.groups.representativeByGroup[$0] }, 134,
                       "the newly-discovered active tab must represent, not the more-recently-focused sibling: \(harness.trace)")
        XCTAssertEqual(harness.state.groups.siblingWids(of: 134)?.sorted(), [39, 134, 141])
        XCTAssertEqual(harness.state.window(134)?.lastFocusOrder, 0, "the switched-to tab was fronted at discovery")
    }

    /// An AX read naming two or more tabs while matching NO window is not evidence that the reader left its
    /// group — it means the titles aren't comparable to window titles at all (#5785: an app composing the two
    /// differently, where even the prefix fallback misses), or that every sibling is still untracked. The read
    /// used to dissolve the group geometry had just formed; geometry re-formed it on the next WindowServer
    /// event, and the pair churned between one tile and two for as long as the window lived. Same rule as the
    /// The group token doing the job `recentPairingWindow` does by timing: two tabs whose AX titles name
    /// nobody (composed titles, #5785) and whose frames share no cluster (the tab bar resized one of them)
    /// still end up in one group, because each named the same `AXTabGroup` element while it was selected.
    /// The tell is that no pairing WINDOW is involved: the second read lands whenever it lands.
    func testTabsJoinOneGroupByTokenWhenTitlesAndFramesNameNobody() {
        var s = TrackedWindowState()
        finderApp(&s)
        s.windows = [
            win(20, size: CGSize(width: 1017, height: 610), spaceIds: [1], focus: 0, title: "Downloads"),
            win(21, size: CGSize(width: 1017, height: 565), spaceIds: [], focus: 1, title: "Documents"),
        ]
        s.visibleSpaces = [1]
        s.currentSpaceId = 1
        s.spaceIndexById = [1: 1]
        let harness = TestReducerRunner(initial: s)
        // 20 is the selected tab, and its read is what says WHICH element this group is
        harness.run([.input(.titleAndTabsRead(wid: 20, tabTitles: ["1. bash", "2. ssh"], tabGroupToken: 4242,
                                              reconcileTabs: true, changedSoFar: false))])
        XCTAssertNil(harness.state.groups.siblingWids(of: 20), "titles alone name nobody, as in #5785")
        // the user switches tabs: 21 comes on-screen, 20 backgrounds (the two halves the reducer otherwise
        // has to pair on a clock — here they only set the physical state, they decide nothing)
        harness.run([
            .input(.spaceMembershipChanged(wid: 21, spaceId: 1, added: true, now: 100.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 20, spaceId: 1, added: false, now: 100.4, inSpaceTransition: false)),
        ])
        // ...and 21's own read names the SAME element, long after any pairing window would have closed
        harness.run([.input(.titleAndTabsRead(wid: 21, tabTitles: ["1. bash", "2. ssh"], tabGroupToken: 4242,
                                              reconcileTabs: true, changedSoFar: false))])
        XCTAssertEqual(harness.state.groups.siblingWids(of: 21)?.sorted(), [20, 21],
            "the shared AXTabGroup element groups them where titles and frames cannot")
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
    }

    func testUnknownTabReadCannotOverwriteTheLastCompletedObservation() {
        var tracked = window(20, spaceIds: [3])
        tracked.tabGroupObservation = .group(titles: ["A", "B"], token: 42)
        tracked.tabCount = 2
        let harness = TestReducerRunner(initial: state(windows: [tracked]))
        harness.run([.input(.titleAndTabsRead(wid: 20, tabGroup: .unknown,
            reconcileTabs: true, changedSoFar: false))])
        XCTAssertEqual(harness.state.window(20)?.tabGroupObservation,
            .group(titles: ["A", "B"], token: 42))
        XCTAssertEqual(harness.state.window(20)?.tabCount, 2)
    }

    func testCompletedStandaloneObservationIsDistinctFromUnknown() {
        var tracked = window(20, spaceIds: [3])
        tracked.tabGroupObservation = .group(titles: ["A", "B"], token: 42)
        tracked.tabCount = 2
        let harness = TestReducerRunner(initial: state(windows: [tracked]))
        harness.run([.input(.titleAndTabsRead(wid: 20, tabGroup: .standalone,
            reconcileTabs: true, changedSoFar: false))])
        XCTAssertEqual(harness.state.window(20)?.tabGroupObservation, .standalone)
        XCTAssertEqual(harness.state.window(20)?.tabCount, 0)
    }

    private func activeTabTornIntoWindowState() -> TrackedWindowState {
        let size = CGSize(width: 920, height: 436)
        var escaped = window(20, title: "Escaped", size: size, position: CGPoint(x: 550, y: 520),
                             spaceIds: [3], lastFocusOrder: 0)
        var remaining = window(21, title: "Remaining", size: size, position: CGPoint(x: 507, y: 456),
                               spaceIds: [3], lastFocusOrder: 1)
        var background = window(22, title: "Background", size: size, position: CGPoint(x: 507, y: 456),
                                spaceIds: [3], spaceIsBorrowed: true, lastFocusOrder: 2)
        escaped.tabCount = 3
        remaining.tabCount = 3
        background.tabCount = 3
        escaped.isOrderedIn = true
        escaped.spaceMembershipObservation = .known([3])
        remaining.isOrderedIn = true
        remaining.spaceMembershipObservation = .known([3])
        let observation = TabGroupObservation.group(titles: ["Escaped", "Remaining", "Background"], token: 42)
        escaped.tabGroupObservation = observation
        remaining.tabGroupObservation = observation
        background.tabGroupObservation = observation
        var s = state(windows: [escaped, remaining, background])
        s.formGroup([20, 21, 22], representative: 20, reason: "fixture")
        // Until the split verdict, the second ordered-in member is the sanctioned drag-out transition.
        s.held.insert(21)
        return s
    }

    /// T-06 live shape: dragging the selected Finder tab out leaves TWO ordered-in windows on the same
    /// Space. The selected wid reports a completed standalone AX read, but the old nil policy retained its
    /// three-member group forever. Two settled, distinct frames confirm that this is not a transient tab
    /// switch, so the escaped window must regain its own tile.
    func testStandaloneActiveTabAtASecondPhysicalFrameLeavesItsOldGroup() {
        let harness = TestReducerRunner(initial: activeTabTornIntoWindowState())
        harness.run([
            .input(.titleAndTabsRead(wid: 20, tabGroup: .standalone,
                                     reconcileTabs: true, changedSoFar: false)),
            .input(.standaloneTabCheck(wid: 20, siblingWid: 21, attempt: 0)),
            .input(.standaloneTabCheck(wid: 20, siblingWid: 21, attempt: 1)),
        ])
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
        XCTAssertNil(harness.state.groups.groupId(of: 20), "the torn-out window needs its own tile")
        XCTAssertEqual(harness.state.groups.siblingWids(of: 21)?.sorted(), [21, 22])
        XCTAssertEqual(harness.state.window(20)?.tabCount, 0)
        XCTAssertTrue(harness.trace.contains { $0.contains("standalone split confirmed #20") })
    }

    /// The same tear-out, from the state a real one is actually in (captured live, T-06 2026-09-17). Two
    /// facts the fixture above did not have, each of which alone kept the group whole:
    /// - the escaped tab was DISPLACED before it was dragged out, so the read that followed the
    ///   displacement already recorded it standalone (only the selected tab exposes a tab bar), and the
    ///   read reporting the tear-out is therefore not a group→standalone edge;
    /// - it still wears `spaceIsBorrowed`, because every pass that keeps a group coherent re-applies that
    ///   annotation to the members, while CGS places the window on a Space in its own right.
    func testStandaloneAnswerSplitsEvenWhenTheWindowWasAlreadyRecordedStandalone() {
        var initial = activeTabTornIntoWindowState()
        if let i = initial.windowIndex(20) {
            initial.windows[i].tabGroupObservation = .standalone
            initial.windows[i].spaceIsBorrowed = true
        }
        let harness = TestReducerRunner(initial: initial)
        harness.run([
            .input(.titleAndTabsRead(wid: 20, tabGroup: .standalone,
                                     reconcileTabs: true, changedSoFar: false)),
            .input(.standaloneTabCheck(wid: 20, siblingWid: 21, attempt: 0)),
            .input(.standaloneTabCheck(wid: 20, siblingWid: 21, attempt: 1)),
        ])
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
        // The arming is the half the old gates suppressed, so it is asserted on its own: the two timer
        // inputs below are hand-fed and would split the group whether or not anything armed them.
        XCTAssertTrue(harness.trace.contains { $0.contains("standalone #20 peer=#21") })
        XCTAssertNil(harness.state.groups.groupId(of: 20), "the torn-out window needs its own tile")
        XCTAssertEqual(harness.state.groups.siblingWids(of: 21)?.sorted(), [21, 22])
        XCTAssertTrue(harness.trace.contains { $0.contains("standalone split confirmed #20") })
    }

    /// An INACTIVE tab answers standalone on every read and must never arm the split: it is ordered out,
    /// which is the physical fact that separates it from a window that escaped its group.
    func testStandaloneAnswerFromAnOrderedOutTabArmsNothing() {
        var initial = activeTabTornIntoWindowState()
        if let i = initial.windowIndex(20) { initial.windows[i].isOrderedIn = false }
        let harness = TestReducerRunner(initial: initial)
        harness.run([
            .input(.titleAndTabsRead(wid: 20, tabGroup: .standalone,
                                     reconcileTabs: true, changedSoFar: false)),
        ])
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
        XCTAssertEqual(harness.state.groups.siblingWids(of: 20)?.sorted(), [20, 21, 22])
        XCTAssertTrue(harness.trace.contains { $0.contains("standalone #20 peer=none") })
    }

    /// A tab switch can briefly answer standalone too. If AX names the group again before the physical
    /// confirmation fires, that newer answer wins and membership remains intact.
    func testTransientStandaloneAnswerCannotSplitARecoveredTabGroup() {
        let harness = TestReducerRunner(initial: activeTabTornIntoWindowState())
        harness.run([
            .input(.titleAndTabsRead(wid: 20, tabGroup: .standalone,
                                     reconcileTabs: true, changedSoFar: false)),
            .input(.standaloneTabCheck(wid: 20, siblingWid: 21, attempt: 0)),
            .input(.titleAndTabsRead(wid: 20,
                                     tabGroup: .group(titles: ["Escaped", "Remaining", "Background"], token: 42),
                                     reconcileTabs: true, changedSoFar: false)),
            .input(.standaloneTabCheck(wid: 20, siblingWid: 21, attempt: 1)),
        ])
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
        XCTAssertEqual(harness.state.groups.siblingWids(of: 20)?.sorted(), [20, 21, 22])
        XCTAssertFalse(harness.trace.contains { $0.contains("standalone split confirmed") })
    }

    /// nil-titles path: a group shrinks only on a POSITIVE signal.
    func testTitlesThatNameNothingKeepTheGroup() {
        var s = TrackedWindowState()
        finderApp(&s)
        let sz = CGSize(width: 1017, height: 610)
        s.windows = [
            win(20, size: sz, spaceIds: [1], focus: 0, title: "Downloads — -zsh — 140×35"),
            win(21, size: sz, spaceIds: [], focus: 1, title: "Documents — -zsh — 140×35"),
        ]
        s.visibleSpaces = [1]
        s.currentSpaceId = 1
        s.spaceIndexById = [1: 1]
        s.formGroup([20, 21], representative: 20, reason: "fixture")
        let harness = TestReducerRunner(initial: s)
        harness.run([.input(.titleAndTabsRead(wid: 20, tabTitles: ["nothing", "matches"], tabGroupToken: nil, reconcileTabs: true,
                                              changedSoFar: false))])
        XCTAssertEqual(harness.state.groups.siblingWids(of: 20)?.sorted(), [20, 21],
            "a read that named nothing must not dissolve the group")
        XCTAssertEqual(harness.state.groups.representativeByGroup.values.sorted(), [20])
    }

    /// A title read that CHANGES group membership must leave the state at a reconcile fixed point. The
    /// discovery path reconciled after `updateTabState` and this one did not, so derived per-member facts —
    /// above all the fullscreen mirror, copied from each group's active tab — stayed stale: a tab that had
    /// left a fullscreen group kept wearing that group's fullscreen flag until some unrelated later pass.
    func testTitleReadThatChangesMembershipLeavesAFixedPoint() {
        var s = TrackedWindowState()
        finderApp(&s)
        let windowed = CGSize(width: 900, height: 600)
        s.windows = [
            win(20, size: windowed, spaceIds: [1], focus: 0),                                  // windowed active
            win(30, size: CGSize(width: 1440, height: 900), spaceIds: [100], fullscreen: true, focus: 1),
            win(21, size: windowed, spaceIds: [100], borrowed: true, fullscreen: true, focus: 2), // frozen tab of 30
        ]
        s.visibleSpaces = [1]
        s.currentSpaceId = 1
        s.spaceIndexById = [1: 1, 100: 2]
        s.windows[2].isFullscreenMirrored = true      // its fullscreen flag is MIRRORED from 30, not its own
        s.formGroup([30, 21], representative: 30, reason: "fixture")
        let harness = TestReducerRunner(initial: s)
        // the windowed active's AX read claims 21 as ITS tab, moving it out of the fullscreen group
        harness.run([.input(.titleAndTabsRead(wid: 20, tabTitles: ["lwouis", "lwouis"], tabGroupToken: nil, reconcileTabs: true,
                                              changedSoFar: false))])
        XCTAssertEqual(harness.violations, [], "convergence: \(harness.trace)")
        // and it no longer wears the fullscreen flag it inherited from the group it left
        if harness.state.groups.siblingWids(of: 21)?.contains(20) == true {
            XCTAssertFalse(harness.state.window(21)!.isFullscreen, "stale mirror survived the move")
        }
    }

    /// #5785, the stuck switcher: two alt-tabs in a row into the SAME app, 219ms apart (log2). The first is a
    /// cross-app activation, the second a switch inside the app that is already frontmost — which produces no
    /// activation at all, so AltTab naming its own target is the only thing that says the user moved. Since
    /// re-focusing an already-focused window emits nothing either, a second switch that goes unheard is never
    /// corrected, and every later alt-tab lands on the window the user is already in.
    func testTwoAltTabsIntoTheSameAppBothMoveTheOrder() {
        let chromeA = window(100, spaceIds: [3], lastFocusOrder: 1)
        let chromeB = window(101, spaceIds: [3], lastFocusOrder: 2)
        let other = window(200, pid: 700, spaceIds: [3], lastFocusOrder: 0)   // the app we alt-tab away from
        var s = state(windows: [chromeA, chromeB, other], frontmostPid: 700)
        s.apps[700] = TrackedApp(state: ApplicationState(pid: 700, bundleIdentifier: "com.tencent.xinWeChat",
            localizedName: "WeChat", isHidden: false), isActive: true)
        let harness = TestReducerRunner(initial: s)
        harness.run([
            // alt-tab 1: AltTab focuses Chrome's window A, so its activation carries the known target
            .setFrontmost(pid: 500),
            .input(.appActivated(pid: 500, now: 10.0, altTabTargetWid: 100)),
            .input(.attentionCommitted(wid: 100, observed: 100, at: 10.0)),
            // alt-tab 2, a beat later: AltTab focuses window B inside the app that is already frontmost, so
            // our own switch names it. No activation follows, and the 808 it produces is not attention.
            .input(.attentionCommitted(wid: 101, observed: 101, at: 10.219)),
        ])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(harness.state.window(101)?.lastFocusOrder, 0, "the second alt-tab's focus was heard")
        XCTAssertEqual(harness.state.window(100)?.lastFocusOrder, 1)
    }

    /// #5785: an app that HIDES its window instead of closing it (WeChat to the tray) keeps the CGWindow, so
    /// reopening re-shows the SAME wid — no create event, no 808, just an order-in of a wid we had removed.
    /// Discovery then takes ~80ms, and a user alt-tabbing inside that gap used to strand the window at the
    /// very back of the MRU, behind even the windowless placeholders (Weixin on the last tile). It must land
    /// where its order-in earns: behind the window focused during the gap, ahead of everything older.
    func testReshownWindowLandsBehindWhatWasFocusedDuringItsDiscoveryGap() {
        let chrome = window(100, spaceIds: [3], lastFocusOrder: 0)
        let older = window(101, spaceIds: [3], lastFocusOrder: 1)
        var s = state(windows: [chrome, older], frontmostPid: 600)
        s.apps[600] = TrackedApp(state: ApplicationState(pid: 600, bundleIdentifier: "com.tencent.xinWeChat",
            localizedName: "WeChat", isHidden: false), isActive: true)
        let harness = TestReducerRunner(initial: s)
        harness.run([
            // WeChat is frontmost and re-shows its hidden window: untracked wid, so only a discovery is armed
            .input(.windowOrderedIn(wid: 150, now: 10.0, inSpaceTransition: false)),
            // the user alt-tabs to Chrome before that discovery lands
            .setFrontmost(pid: 500),
            .input(.attentionCommitted(wid: 100, observed: 100, at: 10.1)),
            .track(window(150, pid: 600, spaceIds: [3])),
            .input(.discoveryLanded(wid: 150, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [3], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(harness.state.window(100)?.lastFocusOrder, 0, "the window focused during the gap keeps the front")
        // The re-shown window claims nothing of its own: an order-in is not attention, so it keeps the rank
        // it had. Where it lands relative to the older windows is decided the next time its app speaks.
        XCTAssertNotNil(harness.state.window(150))
    }

    /// The same order-in, but the window turns out to belong to an app that was NOT frontmost when it
    /// appeared. An untracked order-in is circumstantial — it only means focus for the frontmost app's own
    /// window — and the pid can only be checked once discovery names it. No promotion.
    func testReshownWindowOfAnAppThatWasNotFrontmostIsNotPromoted() {
        let chrome = window(100, spaceIds: [3], lastFocusOrder: 0)
        var s = state(windows: [chrome], frontmostPid: 500)
        s.apps[600] = TrackedApp(state: ApplicationState(pid: 600, bundleIdentifier: "com.tencent.xinWeChat",
            localizedName: "WeChat", isHidden: false), isActive: false)
        let harness = TestReducerRunner(initial: s)
        harness.run([
            .input(.windowOrderedIn(wid: 150, now: 10.0, inSpaceTransition: false)),
            .track(window(150, pid: 600, spaceIds: [3])),
            .input(.discoveryLanded(wid: 150, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [3], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(harness.state.window(100)?.lastFocusOrder, 0)
        XCTAssertEqual(harness.state.window(150)?.lastFocusOrder, 1, "appended, not promoted")
    }


    /// RECORDED 2026-07-29, macOS 26, #5849 follow-up (SamadiPour): two Chrome windows with another app's
    /// window between them in the MRU. Fullscreen the front Chrome window, then leave fullscreen, and the
    /// OTHER Chrome window has taken the middle slot — "Chrome(1)/Other/Chrome(2)" became
    /// "Chrome(1)/Chrome(2)/Other". Nobody focused it; the desktop Space simply came back on screen and every
    /// window on it was ordered in, which the raise inference read as a Cmd+`. Only the fullscreened window's
    /// own siblings jump, because the app-is-active guard spares the other app.
    ///
    /// The timestamps are the capture's, and the one that matters is the LAST: the Space notification lands
    /// 519ms AFTER the order-ins, so `inSpaceTransition` was false throughout the re-show and could never have
    /// been the gate. Kept as a replay of the real capture: the inference that produced the bug is gone
    /// (nothing physical may move the order), so this can no longer fail for its original reason, and it is
    /// here to say that the recorded sequence still lands where the user left it.
    func testLeavingFullscreenDoesNotRefrontTheAppsOtherWindows() {
        let wentFullscreen = window(37901, spaceIds: [4], lastFocusOrder: 0)
        let otherApp = window(44617, pid: 700, spaceIds: [4], lastFocusOrder: 1)
        let sibling = window(51081, spaceIds: [4], lastFocusOrder: 2)
        var s = state(windows: [wentFullscreen, otherApp, sibling])
        s.apps[700] = TrackedApp(state: ApplicationState(pid: 700, bundleIdentifier: "com.anthropic.claudefordesktop",
            localizedName: "Claude", isHidden: false), isActive: false)
        let harness = TestReducerRunner(initial: s)
        harness.run([
            // entering fullscreen takes the desktop Space off screen; these 816s beat the Space notification
            .input(.windowOrderedIn(wid: 37901, now: 22.015, inSpaceTransition: false)),
            .input(.windowOrderedOut(wid: 37901, inSpaceTransition: false)),
            .input(.windowOrderedOut(wid: 44617, inSpaceTransition: false)),
            .input(.windowOrderedOut(wid: 51081, inSpaceTransition: false)),
            // leaving it brings them back, still ahead of the Space notification
            .input(.windowOrderedIn(wid: 37901, now: 26.196, inSpaceTransition: false)),
            .input(.windowOrderedIn(wid: 44617, now: 26.206, inSpaceTransition: false)),
            .input(.windowOrderedIn(wid: 51081, now: 26.206, inSpaceTransition: false)),
            .input(.windowFocused(wid: 37901, now: 26.216)),
        ])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(harness.state.window(37901)?.lastFocusOrder, 0, "the window we fullscreened keeps the front")
        XCTAssertEqual(harness.state.window(44617)?.lastFocusOrder, 1, "the other app's window was not overtaken")
        XCTAssertEqual(harness.state.window(51081)?.lastFocusOrder, 2, "the untouched sibling stayed where it was")
    }


    // MARK: - the handover edge (`recordHandover`)
    //
    // The kernel guards that read `replacedByWid` / `replacedWid` are decoration unless the edge is actually
    // written from the event stream, so these pin the recording rather than the decision. The two halves of a
    // handover — the outgoing tab's 1326 and the incoming tab's 1325 on the same Space — are separate
    // WindowServer datagrams whose order nothing pins, so BOTH arrival orders are tested. That is the same
    // thing `TestScenarioSimulator.HandoverOrder` fuzzes end-to-end.

    private func handoverState() -> TrackedWindowState {
        state(windows: [window(100, spaceIds: [3], lastFocusOrder: 0), window(101, spaceIds: [], lastFocusOrder: 1)])
    }

    func testHandoverIsRecordedWhenTheLeaveLandsFirst() {
        let harness = TestReducerRunner(initial: handoverState())
        harness.run([
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 101, spaceId: 3, added: true, now: 10.01, inSpaceTransition: false)),
        ])
        XCTAssertEqual(harness.state.window(100)?.replacedByWid, 101)
        XCTAssertEqual(harness.state.window(101)?.replacedWid, 100)
    }

    /// The same handover, delivered the other way round — the join first, its paired leave lagging. This is
    /// the order the live captures happen to show (`fullscreenTabSwitchEvents`), and the pairing must not
    /// depend on it.
    func testHandoverIsRecordedWhenTheJoinLandsFirst() {
        let harness = TestReducerRunner(initial: handoverState())
        harness.run([
            .input(.spaceMembershipChanged(wid: 101, spaceId: 3, added: true, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.01, inSpaceTransition: false)),
        ])
        XCTAssertEqual(harness.state.window(100)?.replacedByWid, 101)
        XCTAssertEqual(harness.state.window(101)?.replacedWid, 100)
    }

    /// Time-pairing alone crosses wires between apps — one app's tab backgrounding while another's window
    /// arrives on the same Space is a coincidence, not a handover. The pid is known here, so it is checked
    /// here, rather than left for a consumer to catch later.
    func testHandoverIsNotRecordedAcrossApps() {
        var s = handoverState()
        s.windows.append(window(200, pid: 700, spaceIds: []))
        s.apps[700] = TrackedApp(state: ApplicationState(pid: 700, bundleIdentifier: "com.other",
            localizedName: "Other", isHidden: false), isActive: false)
        let harness = TestReducerRunner(initial: s)
        harness.run([
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 200, spaceId: 3, added: true, now: 10.01, inSpaceTransition: false)),
        ])
        XCTAssertNil(harness.state.window(100)?.replacedByWid)
        XCTAssertNil(harness.state.window(200)?.replacedWid)
    }

    /// A Space SWITCH emits joins and leaves for many unrelated windows at once, and any pairing among them
    /// is invented. Muted for the same reason discovery is.
    func testHandoverIsNotRecordedDuringASpaceTransition() {
        let harness = TestReducerRunner(initial: handoverState())
        harness.run([
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.0, inSpaceTransition: true)),
            .input(.spaceMembershipChanged(wid: 101, spaceId: 3, added: true, now: 10.01, inSpaceTransition: true)),
        ])
        XCTAssertNil(harness.state.window(100)?.replacedByWid)
        XCTAssertNil(harness.state.window(101)?.replacedWid)
    }

    /// Two events far enough apart are not one event. The window is `recentPairingWindow`, shared with every
    /// other pairing in the reducer.
    func testHandoverIsNotRecordedOutsideThePairingWindow() {
        let harness = TestReducerRunner(initial: handoverState())
        harness.run([
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 101, spaceId: 3, added: true, now: 12.0, inSpaceTransition: false)),
        ])
        XCTAssertNil(harness.state.window(100)?.replacedByWid)
        XCTAssertNil(harness.state.window(101)?.replacedWid)
    }

    /// **The MINTED switch.** Finder mints a brand-new wid per tab switch with no create event, so the
    /// incoming half of the handover is a wid we have never seen — and it is the case with the least other
    /// evidence, since a minted tab shares no size cluster with the frozen siblings it belongs to and
    /// fullscreen exposes no AXTabGroup to re-read. The edge is held (`pendingHandoverEdge`) and applied when
    /// the wid is discovered.
    func testHandoverToAnUntrackedWidIsAppliedAtItsDiscovery() {
        let harness = TestReducerRunner(initial: state(windows: [window(100, spaceIds: [3], lastFocusOrder: 0)]))
        harness.run([
            .input(.spaceMembershipChanged(wid: 900, spaceId: 3, added: true, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.01, inSpaceTransition: false)),
            .track(window(900, spaceIds: [3])),
            .input(.discoveryLanded(wid: 900, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [3], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.state.window(100)?.replacedByWid, 900)
        XCTAssertEqual(harness.state.window(900)?.replacedWid, 100)
    }

    /// Entering fullscreen changes the visible Space before the topology callback catches up. The exact
    /// handover still names the minted successor, so group inheritance must not depend on the stale snapshot.
    func testFullscreenHandoverInheritsItsGroupWhileVisibleSpacesAreStale() {
        var s = state(windows: [window(100, spaceIds: [30], lastFocusOrder: 0),
                                window(101, spaceIds: [], lastFocusOrder: 1)])
        s.formGroup([100, 101], representative: 100, reason: "test")
        s.visibleSpaces = [3]
        let harness = TestReducerRunner(initial: s)
        harness.run([
            .input(.windowCreated(wid: 900, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 900, spaceId: 30, added: true, now: 10.01,
                                           inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 30, added: false, now: 10.02,
                                           inSpaceTransition: false)),
        ])
        XCTAssertEqual(harness.state.carried.pendingGroupInheritance[900]?.sorted(), [100, 101])
    }

    /// A minted tab arrives wearing the frame it had as a BACKGROUND tab, and nothing will correct it: the
    /// order-in that moved it onto its parent's frame fires before we ever subscribe to that wid, and a
    /// background tab gets no geometry events. So the group formation has to ask the WindowServer, exactly as
    /// the tracked half of the same handover does on `joinedSpace`. Measured live (2026-08-29): clicking a
    /// background window's tab fronted that window, and its new active tab still sat at the OTHER window's
    /// cascade position — a frame every geometry rule then reasons from.
    func testMintedTabSwitchRefreshesTheIncomingFrameFromTheWindowServer() {
        var s = state(windows: [window(100, spaceIds: [30], lastFocusOrder: 0),
                                window(101, spaceIds: [], lastFocusOrder: 1)])
        s.formGroup([100, 101], representative: 100, reason: "test")
        s.visibleSpaces = [3]
        let harness = TestReducerRunner(initial: s)
        harness.run([
            .input(.windowCreated(wid: 900, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 900, spaceId: 30, added: true, now: 10.01,
                                           inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 30, added: false, now: 10.02,
                                           inSpaceTransition: false)),
            .track(window(900, spaceIds: [30])),
            .input(.discoveryLanded(wid: 900, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [30], isOrderedIn: true, tabTitles: nil,
                                    tabGroupToken: nil)),
        ])
        XCTAssertEqual(harness.state.groups.siblingWids(of: 900)?.sorted(), [100, 101, 900])
        let asked = harness.pendingRequests.contains {
            if case .queryWindowServerState(let wids, _) = $0 { return wids.contains(900) && wids.contains(100) }
            return false
        }
        XCTAssertTrue(asked, "the minted tab's frame was never re-read from the WindowServer")
    }

    /// The pid check `recordHandover` does inline for two tracked windows has to happen at CONSUMPTION when
    /// one side was untracked — that is the first moment the pid exists. A coincidence between two apps must
    /// not survive the wait.
    func testPendingHandoverIsDroppedWhenTheDiscoveredWidBelongsToAnotherApp() {
        var s = state(windows: [window(100, spaceIds: [3], lastFocusOrder: 0)])
        s.apps[700] = TrackedApp(state: ApplicationState(pid: 700, bundleIdentifier: "com.other",
            localizedName: "Other", isHidden: false), isActive: false)
        let harness = TestReducerRunner(initial: s)
        harness.run([
            .input(.spaceMembershipChanged(wid: 900, spaceId: 3, added: true, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.01, inSpaceTransition: false)),
            .track(window(900, pid: 700, spaceIds: [3])),
            .input(.discoveryLanded(wid: 900, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [3], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertNil(harness.state.window(100)?.replacedByWid)
        XCTAssertNil(harness.state.window(900)?.replacedWid)
    }

    /// A mint that is SUPERSEDED before discovery ever reaches it (a second switch, or a tab opened on top)
    /// never becomes a window, so the edge naming it must die with it rather than wait forever — the same
    /// drain the creation flag and the focus promotion get.
    func testPendingHandoverIsDrainedWhenTheMintIsSuperseded() {
        let harness = TestReducerRunner(initial: state(windows: [window(100, spaceIds: [3], lastFocusOrder: 0)]))
        harness.run([
            .input(.spaceMembershipChanged(wid: 900, spaceId: 3, added: true, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.01, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 900, spaceId: 3, added: false, now: 10.2, inSpaceTransition: false)),
        ])
        XCTAssertNil(harness.state.carried.pendingHandoverEdge[900])
    }

    /// The OTHER way a mint never becomes a window: discovery reaches it and admission rejects it
    /// (for example, an auxiliary panel). A rejected wid is the one case
    /// where we know for certain no window is coming — `accepted: false` is that verdict — so it is the
    /// cheapest possible drain, and without it the entry waits for a 804 that "lags a real close by seconds,
    /// or never fires" for apps that retain the CGWindow. That is the rec13 leak shape: the reducer already
    /// drains `pendingSpaceRemoval` on this exact path for exactly this reason.
    ///
    /// It matters beyond tidiness because `applyPendingHandoverEdge` is not time-bounded at CONSUMPTION: it
    /// is paired within `recentPairingWindow` but applied whenever its wid is finally discovered, so a
    /// resurrected wid could wear a stale `replacedWid`, which `dragOutVerdict` reads as a settled verdict.
    func testPendingHandoverIsDrainedWhenTheMintIsRejectedByAdmission() {
        let harness = TestReducerRunner(initial: state(windows: [window(100, spaceIds: [3], lastFocusOrder: 0)]))
        harness.run([
            .input(.spaceMembershipChanged(wid: 900, spaceId: 3, added: true, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.01, inSpaceTransition: false)),
            .input(.discoveryLanded(wid: 900, accepted: false, newlyTracked: false, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil)),
        ])
        XCTAssertNil(harness.state.carried.pendingHandoverEdge[900])
        XCTAssertNil(harness.state.carried.pendingGroupInheritance[900])
    }

    /// **The handover names a representative; it must not shrink the group.** When the app's AXTabGroup
    /// titles land in the same `discoveryLanded` as the mint, they group the incoming tab with every tab of
    /// the window — and `formGroup` is exact-set, so re-forming from the inherited pair evicted the rest.
    /// Measured live (2026-09-04): a tab opened while the cold scan was still running turned one 4-tab Finder
    /// window into two tiles, because `axTitles` formed [900, 100, 101, 102] and the handover immediately
    /// split it back into [900, 100].
    func testMintedTabSwitchKeepsTheTabsTheTitlesAlreadyGrouped() {
        var s = state(windows: [window(100, title: "t", spaceIds: [30], lastFocusOrder: 0),
                                window(101, title: "t", spaceIds: [], lastFocusOrder: 1),
                                window(102, title: "t", spaceIds: [], lastFocusOrder: 2)])
        s.formGroup([100, 101], representative: 100, reason: "test")
        s.visibleSpaces = [3]
        let harness = TestReducerRunner(initial: s)
        harness.run([
            .input(.windowCreated(wid: 900, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 900, spaceId: 30, added: true, now: 10.01,
                                           inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 30, added: false, now: 10.02,
                                           inSpaceTransition: false)),
            .track(window(900, title: "t", spaceIds: [30])),
            .input(.discoveryLanded(wid: 900, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                    queriedSpaceIds: [30], isOrderedIn: true,
                                    tabTitles: ["t", "t", "t", "t"], tabGroupToken: 5031)),
        ])
        XCTAssertEqual(harness.state.groups.siblingWids(of: 900)?.sorted(), [100, 101, 102, 900])
        // Asserted on the trace, not just the settled state: a later geometry pass re-forms the full group
        // whenever the evicted tab happens to share the frame, which is what hid this in the model while the
        // live switcher still drew two tiles.
        XCTAssertFalse(harness.trace.contains {
            $0.contains("group form") && $0.contains("reason=mintedTabSwitch") && !$0.contains("102")
        }, "the handover re-formed the group as an exact set and dropped #102, which the AXTabGroup titles "
            + "had just put in it: \(harness.trace)")
    }

    /// The edge is about the CURRENT state, so it expires when either end moves again: a window that rejoins
    /// a Space is no longer the one that was replaced.
    func testHandoverIsClearedWhenTheReplacedWindowComesBack() {
        let harness = TestReducerRunner(initial: handoverState())
        harness.run([
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: false, now: 10.0, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 101, spaceId: 3, added: true, now: 10.01, inSpaceTransition: false)),
            .input(.spaceMembershipChanged(wid: 100, spaceId: 3, added: true, now: 20.0, inSpaceTransition: false)),
        ])
        XCTAssertNil(harness.state.window(100)?.replacedByWid)
    }

    // MARK: - the z-order seed (the very first summon)

    private func mru(_ harness: TestReducerRunner) -> [CGWindowID] {
        harness.state.windows.sorted { $0.lastFocusOrder < $1.lastFocusOrder }.compactMap { $0.wid }
    }

    /// With no focus history at all, screen stacking IS the order: AltTab launched into a desktop it did not
    /// watch being built, and top-most first is the best guess available on that first summon.
    func testZOrderSeedsWindowsWithNoFocusHistory() {
        let harness = TestReducerRunner(initial: state(windows: [
            window(100, spaceIds: [3], lastFocusOrder: 0),
            window(101, spaceIds: [3], lastFocusOrder: 1),
            window(102, spaceIds: [3], lastFocusOrder: 2)]))
        harness.run([.input(.zOrderRead(widsTopFirst: [102, 100, 101]))])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(mru(harness), [102, 100, 101])
    }

    /// ...but a window we WATCHED being focused keeps its place. A real focus is knowledge; stacking is a
    /// guess. Live capture (2026-08-02): the just-focused Terminal tab had backgrounded into its own
    /// window, so the visible-Space query could not see it, and the seed sent it from tile 0 to tile 3 —
    /// ~20ms into the first summon, after the initial pick had been resolved against the old order, so the
    /// highlight came to rest on a window the user never chose.
    func testZOrderNeverDemotesAWindowThatWasActuallyFocused() {
        var focused = window(100, spaceIds: [3], lastFocusOrder: 0)
        focused.focusedAt = 10.0
        let harness = TestReducerRunner(initial: state(windows: [
            focused,
            window(101, spaceIds: [3], lastFocusOrder: 1),
            window(102, spaceIds: [3], lastFocusOrder: 2)]))
        harness.run([.input(.zOrderRead(widsTopFirst: [101, 102]))])   // 100 is off-screen, hence absent
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(mru(harness), [100, 101, 102])
    }

    /// **A reorder nobody is told about is a reorder the user watches happen.** The seed writes the stacking
    /// order into `lastFocusOrder` and then asks `recomputeFocusRanks` what moved — but by then the write has
    /// already landed, so on a cold model (every `focusedAt` still 0) the re-derivation finds its own answer
    /// in place and reports nothing changed. The reducer then emits no log and, worse, no `.refreshUi`: the
    /// order really did change and the open switcher keeps drawing the old one.
    ///
    /// Live evidence, 2026-08-25: an app's process reordered the MRU front onto a Finder window with no
    /// `zOrder seed reordered` line anywhere in its debug log — the change was visible only in telemetry.
    /// Three investigations dead-ended on that silence.
    func testZOrderReportsWhatItMovedOnAColdModel() {
        let harness = TestReducerRunner(initial: state(windows: [
            window(100, spaceIds: [3], lastFocusOrder: 0),
            window(101, spaceIds: [3], lastFocusOrder: 1),
            window(102, spaceIds: [3], lastFocusOrder: 2)]))
        harness.run([.input(.zOrderRead(widsTopFirst: [102, 100, 101]))])
        XCTAssertEqual(mru(harness), [102, 100, 101])
        XCTAssertEqual(harness.refreshes.flatMap { $0.wids }.sorted(), [100, 101, 102])
        XCTAssertTrue(harness.trace.contains { $0.contains("zOrder seed reordered") }, "\(harness.trace)")
    }

    /// The other side of it: a seed that genuinely changes nothing must stay silent, or every first summon
    /// repaints for no reason.
    func testZOrderThatChangesNothingSaysNothing() {
        let harness = TestReducerRunner(initial: state(windows: [
            window(100, spaceIds: [3], lastFocusOrder: 0),
            window(101, spaceIds: [3], lastFocusOrder: 1),
            window(102, spaceIds: [3], lastFocusOrder: 2)]))
        harness.run([.input(.zOrderRead(widsTopFirst: [100, 101, 102]))])
        XCTAssertEqual(mru(harness), [100, 101, 102])
        XCTAssertEqual(harness.refreshes.flatMap { $0.wids }, [])
        XCTAssertFalse(harness.trace.contains { $0.contains("zOrder seed reordered") })
    }

    /// A window the query cannot see — a background tab, another Space, minimized — is not being ranked by
    /// it. Those keep their relative order, behind the ones it did see.
    func testZOrderPutsWindowsItCannotSeeBehindTheStackedOnes() {
        let harness = TestReducerRunner(initial: state(windows: [
            window(100, spaceIds: [], lastFocusOrder: 0),
            window(101, spaceIds: [], lastFocusOrder: 1),
            window(102, spaceIds: [3], lastFocusOrder: 2)]))
        harness.run([.input(.zOrderRead(widsTopFirst: [102]))])
        XCTAssertEqual(mru(harness), [102, 100, 101])
    }

    // MARK: - switching to a tab we adopted but never grouped

    /// Clicking a background tab fronts it even when we never managed to GROUP it.
    ///
    /// Finder's tabs share one title and keep a stale frame while they are backgrounded, so the AX-title
    /// match names nothing and geometry sees two different positions: the tab sits tracked, Space-less and
    /// ordered-out, linked to nobody. The switch is then a Space-join for a window `isTabbed` says nothing
    /// about, which is why the gate used to write no focus at all — and the group that formed a beat later,
    /// once the tab was on-screen and readable, re-elected the tab the user had just LEFT as the one it
    /// draws. The switcher showed the wrong tab, and stayed wrong.
    func testSwitchingToAnAdoptedButUngroupedTabFrontsIt() {
        var active = window(549, spaceIds: [3], lastFocusOrder: 0)
        active.isOrderedIn = true
        let adopted = window(544, lastFocusOrder: 1)          // no Space, not ordered in, in no group
        let harness = TestReducerRunner(initial: state(windows: [active, adopted]))
        harness.run([.input(.spaceMembershipChanged(wid: 544, spaceId: 3, added: true, now: 100.0,
                                                    inSpaceTransition: false))])
        XCTAssertEqual(harness.violations, [])
        XCTAssertEqual(mru(harness), [544, 549])
        // and that is what decides the tile once the group finally forms
        let members = [harness.state.window(549)!, harness.state.window(544)!].map { harness.state.tabWindow($0) }
        XCTAssertEqual(TabGroupResolver.groupRepresentative(members), 544)
    }

    /// The same shape with the app in the BACKGROUND is not a tab switch the user made, and must not front
    /// anything: a window quietly rejoining a Space is not attention.
    func testAnUngroupedTabJoiningASpaceOfAnInactiveAppDoesNotFront() {
        var s = state(windows: [window(549, spaceIds: [3], lastFocusOrder: 0), window(544, lastFocusOrder: 1)])
        s.apps[500]?.isActive = false
        s.frontmostPid = nil
        let harness = TestReducerRunner(initial: s)
        harness.run([.input(.spaceMembershipChanged(wid: 544, spaceId: 3, added: true, now: 100.0,
                                                    inSpaceTransition: false))])
        XCTAssertEqual(mru(harness), [549, 544])
    }
}
