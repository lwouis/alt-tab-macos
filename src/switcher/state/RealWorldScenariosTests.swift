import XCTest

/// A durable corpus of REAL data captured live from the actual apps/APIs in #5830 (Terminal + Finder tabs,
/// CGS Spaces, WindowServer events on macOS 26), fed to the pure decision kernels. The point is to capture
/// the messy real-world facts ONCE — duplicate `~` titles, identical tab geometry, Space-less background
/// tabs, the removed-from-Space event storm — so we can keep changing the heuristics over time and re-run
/// against fixed ground truth, and never have to re-record from a live machine again.
///
/// `CapturedWindow` holds only the RAW facts each API handed us (nothing derived like `isTabbed`). Each test
/// projects it onto whatever record a kernel needs (`TabWindow` / `WindowState`), supplying the algorithm
/// state for the step under test. So when a kernel's inputs or logic change, the captures stay valid and
/// only the projections/expectations move. See `RealWorldScenariosSpecs.md` for provenance and how to add one.
final class RealWorldScenariosTests: XCTestCase {

    /// One window exactly as AX + CGS + WindowServer reported it at capture time.
    struct CapturedWindow {
        var pid: pid_t
        var wid: CGWindowID
        var title: String                   // AXTitle
        var subrole: String                 // AXSubrole
        var size: CGSize?                   // WindowServer bounds
        var position: CGPoint?
        var spaceIds: [UInt64]              // CGSCopySpacesForWindows — empty ⇒ Space-less (background tab)
        var isMinimized = false
        var isFullscreen = false
        /// `extractTabTitles()` over THIS window's AXTabGroup: the AXTabButton titles, or nil when < 2 (no
        /// group). Only the ACTIVE tab of a group reports these; a background tab reports nil.
        var axTabTitles: [String]? = nil

        func tabWindow(isTabbed: Bool = false, tabbedSiblingWids: [CGWindowID]? = nil) -> TabWindow {
            TabWindow(pid: pid, wid: wid, size: size, position: position, spaceIds: spaceIds, title: title,
                isTabbed: isTabbed, isFullscreen: isFullscreen, isMinimized: isMinimized,
                tabbedSiblingWids: tabbedSiblingWids)
        }

        func windowState(isTabbed: Bool = false) -> WindowState {
            WindowState(id: "wid-\(wid)", isPhantom: false, isWindowlessApp: false, isFullscreen: isFullscreen,
                isMinimized: isMinimized, isTabbed: isTabbed, isOnAllSpaces: false, spaceIds: spaceIds,
                spaceIndexes: [], lastFocusOrder: 0, creationOrder: 0, title: title)
        }
    }

    static let terminalApp = ApplicationState(pid: 92832, bundleIdentifier: "com.apple.Terminal",
        localizedName: "Terminal", isHidden: false)

    // MARK: - Corpus (raw captures — do NOT edit values without a fresh recording; see the Specs)

    /// Terminal, "Merge All Windows" over 4 windows (macOS 26, 2026-07-06). All tabs titled "~", identical
    /// size 757×583 at (683,101). The active tab (29328) holds Space 3 and its AXTabGroup lists all four "~";
    /// the three background tabs are Space-less and expose no AXTabGroup.
    static let terminalMerge4Tabs: [CapturedWindow] = {
        let sz = CGSize(width: 757, height: 583), pos = CGPoint(x: 683, y: 101)
        return [
            CapturedWindow(pid: 92832, wid: 29328, title: "~", subrole: "AXStandardWindow", size: sz,
                position: pos, spaceIds: [3], axTabTitles: ["~", "~", "~", "~"]),
            CapturedWindow(pid: 92832, wid: 29326, title: "~", subrole: "AXStandardWindow", size: sz, position: pos, spaceIds: []),
            CapturedWindow(pid: 92832, wid: 29321, title: "~", subrole: "AXStandardWindow", size: sz, position: pos, spaceIds: []),
            CapturedWindow(pid: 92832, wid: 29320, title: "~", subrole: "AXStandardWindow", size: sz, position: pos, spaceIds: []),
        ]
    }()

    /// Terminal mid-creation of a 9-tab group: AX reports 9 "~" from the active tab (29358) but only 6 windows
    /// are tracked yet, so 5 match and 3 titles stay untracked (→ brute-force discovery). Only the tracked
    /// windows are listed here (the untracked tabs are, by definition, not in our model yet).
    static let terminalActive9Titles = CapturedWindow(pid: 92832, wid: 29358, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3], axTabTitles: Array(repeating: "~", count: 9))
    static let terminal9TabsTracked: [CapturedWindow] = [29328, 29326, 29321, 29320, 29352].map {
        CapturedWindow(pid: 92832, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101), spaceIds: [])
    }

    /// Finder, a 4-tab window (2026-07-06). AXTabGroup titles = ["QRHYWK4QHQ", "lwouis", "lwouis", "lwouis"]
    /// (duplicates). Finder's inactive tabs are NOT separate windows (no CGWindowID), so only the active tab
    /// (29304) is ever tracked — the other three titles never resolve to a window.
    static let finderActive4Tabs = CapturedWindow(pid: 779, wid: 29304, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 100, y: 100),
        spaceIds: [1], axTabTitles: ["QRHYWK4QHQ", "lwouis", "lwouis", "lwouis"])

    /// Terminal with DEFAULT tabbing: 4 genuinely separate windows, each titled "Terminal"/"~", identical
    /// size 757×547 stacked at (683,101). Every window holds Space 1 and NONE exposes an AXTabGroup
    /// (`axTabTitles` nil). The "must never be grouped" ground truth — same app, same size, same position,
    /// but real separate windows (#5830 false-positive guard).
    static let terminalSeparate4Windows: [CapturedWindow] = {
        let sz = CGSize(width: 757, height: 547), pos = CGPoint(x: 683, y: 101)
        return [29104, 29105, 29110, 29112].map {
            CapturedWindow(pid: 92832, wid: $0, title: "Terminal", subrole: "AXStandardWindow",
                size: sz, position: pos, spaceIds: [1])
        }
    }()

    /// The WindowServer notification burst captured when Terminal windows left Space 3 all at once (the
    /// removed-from-Space storm that drove the #5830 reconcile churn). Raw (SkyLight id, wid) pairs in order.
    static let removedFromSpaceStorm: [(id: UInt32, wid: CGWindowID)] = [
        (807, 28160), (807, 28159), (807, 28165),   // windowResized
        (816, 28159), (816, 28160), (816, 28165),   // windowOrderedOut
        (1326, 28159), (1326, 28160), (1326, 28165), // windowRemovedFromSpace
    ]

    /// Terminal: the 3-tab group then FULLSCREENED (Cmd-Ctrl-F, 2026-07-06). The active tab (30170) moves to
    /// its own fullscreen Space 2 at the screen size 1440×864 @ (0,36); its background tabs keep STALE windowed
    /// geometry (757×543 @ (683,101), still Space-less) and AX exposes NO readable AXTabGroup for a fullscreen
    /// window (titles nil). The captured proof that size-keyed geometry can't group fullscreen tabs — the
    /// active's size diverges from the (frozen) background sizes.
    static let terminalFullscreenActive = CapturedWindow(pid: 30000, wid: 30170, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 1440, height: 864), position: CGPoint(x: 0, y: 36),
        spaceIds: [2], isFullscreen: true, axTabTitles: nil)
    static let terminalFullscreenBackgroundTabs: [CapturedWindow] = [30162, 30163, 30168].map {
        CapturedWindow(pid: 30000, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 757, height: 543), position: CGPoint(x: 683, y: 101), spaceIds: [])
    }

    /// Terminal: "Move Tab to New Window" on the active tab of a 4-tab group (the drag-out). The leaving tab
    /// (30238) becomes standalone — its size SHRINKS 757×543 → 757×527 (the tab bar is gone) and it moves to
    /// (14,130); the 3 remaining tabs keep 757×543 @ (683,101). The pre-drag group was
    /// [30238, 30236, 30231, 30230].
    static let dragOutLeavingWid: CGWindowID = 30238
    static let dragOutPriorSiblings: [CGWindowID] = [30238, 30236, 30231, 30230]
    static let dragOutStandaloneWindow = CapturedWindow(pid: 30001, wid: 30238, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 527), position: CGPoint(x: 14, y: 130), spaceIds: [1])
    static let dragOutRemainingGroup: [CapturedWindow] = [30236, 30231, 30230].map {
        CapturedWindow(pid: 30001, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 757, height: 543), position: CGPoint(x: 683, y: 101), spaceIds: [1])
    }

    /// A tabbed window MOVED to another Space (recorded from a Space move on macOS 26): the active tab LEAVES
    /// its old Space (1326) and JOINS the new one (1325), each event carrying (spaceId, wid) in its payload;
    /// the background tabs are already Space-less and follow. `wid=30170`, Space 3 → fullscreen Space 1791.
    static let tabbedWindowMovedBetweenSpaces: [(id: UInt32, space: UInt64, wid: CGWindowID)] = [
        (1326, 3, 30170),      // windowRemovedFromSpace — leaves Space 3
        (1325, 1791, 30170),   // windowAddedToSpace — joins Space 1791
    ]

    /// Mission Control begin/end, captured from the Dock's AX notification stream (`DockEvents`). These are
    /// the only reliable MC signals — MC itself moves no windows between Spaces (it's an overview), it just
    /// orders every window's thumbnail in and out. Kept as reference: `MissionControlState` has no pure-kernel
    /// consumer, so there's no assertion here, only the recorded ground truth. `AXExposeExit` is the clean
    /// "transition ended" hook (see reference_windowserver_notification_ids).
    static let missionControlAxCycle: [String] = ["AXExposeShowAllWindows", "AXExposeExit"]

    /// Finder with tabs "lwouis" (inactive, AXValue 0) + "git" (active, AXValue 1) and a separate non-tabbed
    /// window "Movies". Recorded by the maintainer during the tab-detection investigation (see
    /// `experimentations/TabbedWindowDetection.swift`): the active tab's AXTabGroup lists ["lwouis", "git"];
    /// "Movies" has no AXTabGroup. Distinct titles here (unlike Terminal's `~`), so matching is unambiguous.
    static let finderGitActive = CapturedWindow(pid: 779, wid: 4001, title: "git", subrole: "AXStandardWindow",
        size: CGSize(width: 900, height: 600), position: CGPoint(x: 200, y: 200), spaceIds: [1],
        axTabTitles: ["lwouis", "git"])
    static let finderLwouisInactiveTab = CapturedWindow(pid: 779, wid: 4002, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 900, height: 600), position: CGPoint(x: 200, y: 200), spaceIds: [])
    static let finderMoviesStandalone = CapturedWindow(pid: 779, wid: 4003, title: "Movies",
        subrole: "AXStandardWindow", size: CGSize(width: 500, height: 400), position: CGPoint(x: 50, y: 50), spaceIds: [1])

    // MARK: - Tab grouping (geometryGroups)

    func testMergedTabsGroupByGeometry() {
        // The merged group as geometry sees it: the active tab holds a Space and (AX having confirmed the
        // group) carries its `tabbedSiblingWids`; the 3 background tabs are Space-less ⇒ grouped under it.
        let active = Self.terminalMerge4Tabs[0].tabWindow(tabbedSiblingWids: [29328, 29326, 29321, 29320])
        let background = Self.terminalMerge4Tabs.dropFirst().map { $0.tabWindow(isTabbed: true) }
        XCTAssertEqual(TabGroupResolver.geometryGroups([active] + background),
            [GeometryGroup(visibleWid: 29328, backgroundWids: [29326, 29321, 29320])])
    }

    func testSeparateWindowsNeverGroup() {
        // Same app, same size, same position, but all hold a Space and none was AX-confirmed as a tab group.
        // Geometry must NOT collapse them (the #5830 false positive). Even if one momentarily read Space-less,
        // the visible has no `tabbedSiblingWids` / fullscreen, so the gate rejects it.
        let windows = Self.terminalSeparate4Windows.map { $0.tabWindow() }
        XCTAssertEqual(TabGroupResolver.geometryGroups(windows), [])
        // and the flaky-read variant: window 2 briefly Space-less → still not grouped (unconfirmed visible).
        var flaky = Self.terminalSeparate4Windows
        flaky[1].spaceIds = []
        XCTAssertEqual(TabGroupResolver.geometryGroups(flaky.map { $0.tabWindow() }), [])
    }

    // MARK: - Inactive-tab matching (matchSiblings)

    func testMergedTabsAllMatchByTitle() {
        let active = Self.terminalMerge4Tabs[0]
        let m = TabGroupResolver.matchSiblings(active: active.tabWindow(), axTitles: active.axTabTitles!,
            sameAppWindows: Self.terminalMerge4Tabs.map { $0.tabWindow() })
        XCTAssertEqual(m, SiblingMatch(siblingWids: [29328, 29326, 29321, 29320],
            matchedWids: [29326, 29321, 29320], untrackedTitles: [], toUntabWids: []))
    }

    func testNineTabsLeaveThreeUntracked() {
        // The churn window: 9 "~" titles, 5 tracked siblings ⇒ 5 matched, 3 stay untracked (→ discovery).
        // "sometimes 9" in the ticket == this raw title count.
        let active = Self.terminalActive9Titles
        let m = TabGroupResolver.matchSiblings(active: active.tabWindow(), axTitles: active.axTabTitles!,
            sameAppWindows: [active.tabWindow()] + Self.terminal9TabsTracked.map { $0.tabWindow() })
        XCTAssertEqual(m.matchedWids, [29328, 29326, 29321, 29320, 29352])
        XCTAssertEqual(m.untrackedTitles, ["~", "~", "~"])
    }

    func testFinderTabsAllUntracked() {
        // Only the active Finder tab is a real window; the 3 duplicate/other titles resolve to nothing.
        let active = Self.finderActive4Tabs
        let m = TabGroupResolver.matchSiblings(active: active.tabWindow(), axTitles: active.axTabTitles!,
            sameAppWindows: [active.tabWindow()])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [29304], matchedWids: [],
            untrackedTitles: ["QRHYWK4QHQ", "lwouis", "lwouis"], toUntabWids: []))
    }

    // MARK: - Phantom exemption for inactive tabs (PhantomWindowDetector)

    func testBackgroundTabPhantomFlipsWithTabDetection() {
        // A Space-less background tab BEFORE tab detection reads as phantom (empty spaceIds); once grouping
        // marks it `isTabbed`, the exemption clears it. This coupling is why a tab-detection regression makes
        // inactive tabs vanish in #5830.
        let bg = Self.terminalMerge4Tabs[1]
        XCTAssertTrue(PhantomWindowDetector.syncVerdict(bg.windowState(isTabbed: false), Self.terminalApp))
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(bg.windowState(isTabbed: true), Self.terminalApp))
    }

    // MARK: - Space-transition event routing (WsEventRouting)

    func testRemovedFromSpaceStormRouting() {
        // Every removed-from-Space (1326) in the storm routes to `.updateSpaceMembership`, which is what
        // re-triggers tab reconcile per event and churned the group in #5830. Pins the id→action map against
        // the real burst.
        let actions = Self.removedFromSpaceStorm.map { raw -> WsEventRouting.Action? in
            WsEventRouting.notification(raw.id).map { WsEventRouting.action(for: $0) }
        }
        XCTAssertEqual(actions[0], .updateGeometry)          // 807 windowResized
        XCTAssertEqual(actions[3], .refreshVisibility)       // 816 windowOrderedOut
        XCTAssertEqual(actions[6], .updateSpaceMembership)   // 1326 windowRemovedFromSpace
        XCTAssertTrue(Self.removedFromSpaceStorm.filter { $0.id == 1326 }
            .allSatisfy { WsEventRouting.action(for: WsEventRouting.notification($0.id)!) == .updateSpaceMembership })
    }

    func testTabbedWindowMovedBetweenSpacesRouting() {
        // Moving a tabbed window to another Space = leave (1326) + join (1325). Both route to
        // `.updateSpaceMembership` and carry (spaceId, wid) in the payload, so membership updates without a
        // follow-up CGS query. This is the event pair that fires reconcile so the group follows the move.
        for (id, _, _) in Self.tabbedWindowMovedBetweenSpaces {
            let n = WsEventRouting.notification(id)!
            XCTAssertEqual(WsEventRouting.action(for: n), .updateSpaceMembership)
            XCTAssertTrue(WsEventRouting.payloadCarriesSpaceId(n))
        }
    }

    func testMissionControlCycleIsAxDrivenNotSpaceMembership() {
        // MC's begin/end come from the Dock AX stream, not WindowServer; and the ids MC fires (818 Dock
        // windows, 1327/1328 space create/destroy) are NOT ones we route — MC moves no app window between
        // Spaces. Guards against someone wiring MC's transient ids into window handling.
        XCTAssertEqual(Self.missionControlAxCycle, ["AXExposeShowAllWindows", "AXExposeExit"])
        for id: UInt32 in [818, 1327, 1328] {
            XCTAssertNil(WsEventRouting.notification(id))
        }
    }

    // MARK: - Fullscreen tabs

    func testFullscreenTabsNotGroupedByGeometryAlone() {
        // Real proof of the fullscreen limitation: the active tab is 1440×864 (fullscreen) while its
        // background tabs are frozen at 757×543, so they land in different size buckets and geometry can't
        // re-group them. The live model keeps them grouped via the `tabbedSiblingWids` link established while
        // windowed + `mirrorActiveTabStateToInactiveTabs`, NOT via geometry — this pins why that link matters.
        let active = Self.terminalFullscreenActive.tabWindow(tabbedSiblingWids: [30170, 30162, 30163, 30168])
        let background = Self.terminalFullscreenBackgroundTabs.map { $0.tabWindow(isTabbed: true) }
        XCTAssertEqual(TabGroupResolver.geometryGroups([active] + background), [])
    }

    func testFullscreenTabPositionCompatibleViaExistingLink() {
        // Position/size both diverge under fullscreen, but an already-linked inactive tab must still count as
        // compatible (the `tabbedSiblingWids` link and the fullscreen fallback both win) so it isn't dropped.
        let active = Self.terminalFullscreenActive.tabWindow(tabbedSiblingWids: [30170, 30162, 30163, 30168])
        let linkedBg = Self.terminalFullscreenBackgroundTabs[0].tabWindow(isTabbed: true, tabbedSiblingWids: [30170, 30162, 30163, 30168])
        XCTAssertTrue(TabGroupResolver.positionsCompatible(active, linkedBg))
    }

    // MARK: - Drag a tab out of its group (Move Tab to New Window)

    func testDragOutShrinksTheGroup() {
        // The active tab left the 4-window group → 3 still-present survivors → shrink (not dissolve), keeping
        // them a group of the remaining 3.
        let d = TabGroupResolver.dissolution(siblingWids: Self.dragOutPriorSiblings, leaving: Self.dragOutLeavingWid,
            presentWids: [30236, 30231, 30230])
        XCTAssertEqual(d, GroupDissolution(remainingSiblingWids: [30236, 30231, 30230],
            applyToWids: [30236, 30231, 30230], dissolve: false))
    }

    func testDraggedOutWindowNotReAbsorbedByGeometry() {
        // After the drag-out the standalone window is a different size (757×527, tab bar gone) and holds a
        // Space, while the remaining group also all hold a Space (backfilled). Nothing is Space-less, and the
        // sizes differ → geometry must not re-collapse the escaped window back in.
        let escaped = Self.dragOutStandaloneWindow.tabWindow()
        let remaining = Self.dragOutRemainingGroup.map { $0.tabWindow(isTabbed: true) }
        XCTAssertEqual(TabGroupResolver.geometryGroups([escaped] + remaining), [])
    }

    // MARK: - Finder: distinct-title tabs + a same-app standalone window

    func testFinderStandaloneWindowNotSweptIntoGroup() {
        // "Movies" is a separate non-tabbed window of the same app; it must NOT be pulled into the git/lwouis
        // tab group. Only "lwouis" matches the AXTabGroup titles; "Movies" is left alone (no stale tab state).
        let m = TabGroupResolver.matchSiblings(active: Self.finderGitActive.tabWindow(),
            axTitles: Self.finderGitActive.axTabTitles!,
            sameAppWindows: [Self.finderGitActive.tabWindow(), Self.finderLwouisInactiveTab.tabWindow(),
                Self.finderMoviesStandalone.tabWindow()])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [4001, 4002], matchedWids: [4002],
            untrackedTitles: [], toUntabWids: []))
    }

    func testFinderNewWindowNotSwallowedByTabGroup() {
        // Recorded live 2026-07-09: Finder with a 2-tab group (both "lwouis") + cmd-N opens a NEW window,
        // also "lwouis", at Finder's cascaded position (~28px offset, within the 50px tolerance). Finder
        // DESTROYS a backgrounded tab's window (only the active tab is a real window), so the group's second
        // AXTabGroup title has no window — and the matcher claimed the NEW on-Space window to fill it, hiding
        // it from the switcher ("appeared then disappeared"). An on-Space, non-tabbed window must never be
        // claimed as an inactive tab; the title goes untracked (brute-force finds nothing → group shows as 1).
        let activeTab = CapturedWindow(pid: 779, wid: 42233, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 100, y: 100), spaceIds: [3],
            axTabTitles: ["lwouis", "lwouis"])
        let newWindow = CapturedWindow(pid: 779, wid: 42243, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 128, y: 128), spaceIds: [3])
        let m = TabGroupResolver.matchSiblings(active: activeTab.tabWindow(), axTitles: activeTab.axTabTitles!,
            sameAppWindows: [activeTab.tabWindow(), newWindow.tabWindow()])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [42233], matchedWids: [],
            untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testFinderInactiveTabIsPhantomUntilTabbed() {
        // "lwouis" is Space-less (inactive tab) → phantom before detection, exempt once `isTabbed`.
        let app = ApplicationState(pid: 779, bundleIdentifier: "com.apple.finder", localizedName: "Finder", isHidden: false)
        XCTAssertTrue(PhantomWindowDetector.syncVerdict(Self.finderLwouisInactiveTab.windowState(isTabbed: false), app))
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(Self.finderLwouisInactiveTab.windowState(isTabbed: true), app))
    }

    // MARK: - TextEdit: distinct-title tabs + moving a tab between two groups

    /// TextEdit, 6 documents in ONE tab group (2026-07-06). Titles are DISTINCT ("Untitled"…"Untitled 6"),
    /// unlike Terminal's `~`, so matching is unambiguous. Active tab 30430 ("Untitled 6") holds a Space; the
    /// rest are Space-less inactive tabs. Real wids/titles captured live.
    static let textEditGroup6Titles = ["Untitled", "Untitled 2", "Untitled 3", "Untitled 4", "Untitled 5", "Untitled 6"]
    static let textEditGroup6: [CapturedWindow] = {
        let sz = CGSize(width: 574, height: 480), pos = CGPoint(x: 141, y: 65)
        let ids: [(CGWindowID, String)] = [(30430, "Untitled 6"), (30412, "Untitled"), (30417, "Untitled 2"),
            (30424, "Untitled 3"), (30426, "Untitled 4"), (30428, "Untitled 5")]
        return ids.map { CapturedWindow(pid: 30300, wid: $0.0, title: $0.1, subrole: "AXStandardWindow",
            size: sz, position: pos, spaceIds: $0.0 == 30430 ? [1] : []) }
    }()

    func testDistinctTitleTabsAllMatchCleanly() {
        // Every inactive tab resolves to exactly one window by its unique title — no untracked, no churn.
        // The contrast case to `testNineTabsLeaveThreeUntracked` (dup `~`): distinct titles are the easy path.
        let active = Self.textEditGroup6[0]
        let m = TabGroupResolver.matchSiblings(active: active.tabWindow(), axTitles: Self.textEditGroup6Titles,
            sameAppWindows: Self.textEditGroup6.map { $0.tabWindow() })
        XCTAssertEqual(m.matchedWids, [30412, 30417, 30424, 30426, 30428])
        XCTAssertEqual(m.untrackedTitles, [])
    }

    // TWO coexisting tab groups of one app, recorded LIVE 2026-07-06: logging was armed and the user dragged
    // tabs between two real TextEdit groups by hand (and closed one window, "Untitled 8", mid-way). The log
    // captured both AXTabGroups: A = ["Untitled", "Untitled 2", "Untitled 3"], B = ["Untitled 7", "Untitled 9"],
    // alongside 3 standalone windows (U4/U5/U6). The moves + close mean no single tab's before/after is
    // isolated, but the durable invariant IS captured: each group's matchSiblings resolves ONLY its own tabs,
    // never the other group's nor the standalones. pid/wids/titles are real; each group's tabs are placed at
    // their shared frame (a settled group's tabs overlap exactly).
    static let realTextEditPid: pid_t = 4723
    static func teWindow(_ wid: CGWindowID, _ title: String, _ pos: CGPoint, active: Bool) -> CapturedWindow {
        CapturedWindow(pid: realTextEditPid, wid: wid, title: title, subrole: "AXStandardWindow",
            size: CGSize(width: 574, height: 480), position: pos, spaceIds: active ? [1] : [])
    }
    static let twoGroupsSameApp: [CapturedWindow] = {
        let aPos = CGPoint(x: 0, y: 60), bPos = CGPoint(x: 474, y: 232)
        return [
            teWindow(30543, "Untitled 3", aPos, active: true),   // group A active
            teWindow(30542, "Untitled 2", aPos, active: false),  // group A tab
            teWindow(30561, "Untitled 9", bPos, active: true),   // group B active
            teWindow(30537, "Untitled 7", bPos, active: false),  // group B tab
            teWindow(30539, "Untitled 4", CGPoint(x: 606, y: 328), active: true),  // standalone
            teWindow(30540, "Untitled 5", CGPoint(x: 788, y: 369), active: true),  // standalone
            teWindow(30541, "Untitled 6", CGPoint(x: 788, y: 395), active: true),  // standalone
        ]
    }()

    func testTwoCoexistingGroups_A_matchesOnlyItsOwnTabs() {
        // Group A's active tab, given EVERY TextEdit window, pulls in only "Untitled 2" (its tab) — never
        // group B's U7/U9 nor the U4/U5/U6 standalones. "Untitled" (U1) is an as-yet-undiscovered inactive tab.
        let m = TabGroupResolver.matchSiblings(active: Self.twoGroupsSameApp[0].tabWindow(),
            axTitles: ["Untitled", "Untitled 2", "Untitled 3"],
            sameAppWindows: Self.twoGroupsSameApp.map { $0.tabWindow() })
        XCTAssertEqual(m, SiblingMatch(siblingWids: [30543, 30542], matchedWids: [30542],
            untrackedTitles: ["Untitled"], toUntabWids: []))
    }

    func testTwoCoexistingGroups_B_matchesOnlyItsOwnTabs() {
        // Group B's active tab pulls in only "Untitled 7" — group A's tabs and the standalones stay out.
        let m = TabGroupResolver.matchSiblings(active: Self.twoGroupsSameApp[2].tabWindow(),
            axTitles: ["Untitled 7", "Untitled 9"],
            sameAppWindows: Self.twoGroupsSameApp.map { $0.tabWindow() })
        XCTAssertEqual(m, SiblingMatch(siblingWids: [30561, 30537], matchedWids: [30537],
            untrackedTitles: [], toUntabWids: []))
    }
}
