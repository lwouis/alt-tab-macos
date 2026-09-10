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

        /// `tabCount` is DERIVED from the capture by default, because that is the live relationship: the
        /// reducer records the button count of the same AXTabGroup read that produced `axTabTitles`. A test
        /// overrides it only to model a count read at a different instant than the titles.
        func tabWindow(isTabbed: Bool = false, tabbedSiblingWids: [CGWindowID]? = nil,
                       tabCount: Int? = nil) -> TabWindow {
            TabWindow(pid: pid, wid: wid, size: size, position: position, spaceIds: spaceIds, title: title,
                isTabbed: isTabbed, isFullscreen: isFullscreen, isMinimized: isMinimized,
                tabbedSiblingWids: tabbedSiblingWids, tabCount: tabCount ?? axTabTitles?.count ?? 0)
        }

        func windowState(isTabbed: Bool = false) -> WindowState {
            WindowState(id: "wid-\(wid)", isPhantom: false, isWindowlessApp: false, isFullscreen: isFullscreen,
                isMinimized: isMinimized, isTabbed: isTabbed, isOnAllSpaces: false, spaceIds: spaceIds,
                spaceIndexes: [], lastFocusOrder: 0, creationOrder: 0, title: title)
        }

        /// Project this capture into the replay harness's model record (`ReplayScenariosTests`), so replay
        /// fixtures and kernel tests share ONE transcription of the recorded raw facts. As with
        /// `tabWindow(isTabbed:tabbedSiblingWids:)`, the capture supplies only what the OS reported; the
        /// MODEL-state facts a fixture must add — synthetic markers, MRU order — are parameters
        /// (`spaceIds` overrides the raw value when the model held a backfilled/borrowed Space at the
        /// fixture's starting instant).
        func modelWindow(spaceIds: [UInt64]? = nil, spaceIsBorrowed: Bool = false,
                         isFullscreenMirrored: Bool = false, lastFocusOrder: Int = 0,
                         hasThumbnail: Bool = true) -> TrackedWindow {
            TrackedWindow(id: "wid-\(wid)", wid: wid, pid: pid, title: title, size: size, position: position,
                spaceIds: spaceIds ?? self.spaceIds, spaceIndexes: [], isOnAllSpaces: false,
                spaceIsBorrowed: spaceIsBorrowed, isFullscreen: isFullscreen,
                isFullscreenMirrored: isFullscreenMirrored, isMinimized: isMinimized, isMainWindow: false,
                isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: lastFocusOrder,
                creationOrder: Int(wid), hasThumbnail: hasThumbnail)
        }
    }

    static let terminalApp = ApplicationState(pid: 92832, bundleIdentifier: "com.apple.Terminal",
        localizedName: "Terminal", isHidden: false)

    // MARK: - Corpus (raw captures — do NOT edit values without a fresh recording; see the Specs)

    /// Terminal, "Merge All Windows" over 4 windows (macOS 26, 2026-07-06). All tabs titled "~", identical
    /// size 757×583. The active tab (29328) holds Space 3 and its AXTabGroup lists all four "~"; the three
    /// background tabs are Space-less and expose no AXTabGroup.
    ///
    /// **POSITIONS CORRECTED 2026-07-30** (live QA). This capture recorded all four tabs at ONE
    /// position (683,101), which is not what the OS produces: the merge does NOT converge the tabs' frames.
    /// The pre-merge windows keep their cascade positions and the merged window is a BRAND-NEW wid one cascade
    /// step further on, so the group spans four distinct positions 29px apart and only the SIZE is shared:
    ///
    ///     +0:Terminal#65640(F) sp=[3] 757x543@942,277 '~'   ← the merged window, newly created
    ///     -1:Terminal#65637(p) sp=[]  757x543@913,248 '~'   ← the pre-merge windows, frames frozen
    ///     -2:Terminal#65632(p) sp=[]  757x543@884,219 '~'
    ///     -3:Terminal#65628(p) sp=[]  757x543@855,190 '~'
    ///
    /// Recorded verbatim from that run, mapped onto this capture's wids in the same MRU order (Finder's merge is
    /// identical in shape: 920×436, 29px cascade). The single position is what made every kernel test
    /// here pass while both live merges formed NO group at all — the cascade is exactly what `framePartitions`
    /// splits on, so the four tabs were four partitions of one.
    static let terminalMerge4Tabs: [CapturedWindow] = {
        let sz = CGSize(width: 757, height: 583)
        return [
            CapturedWindow(pid: 92832, wid: 29328, title: "~", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 942, y: 277), spaceIds: [3], axTabTitles: ["~", "~", "~", "~"]),
            CapturedWindow(pid: 92832, wid: 29326, title: "~", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 913, y: 248), spaceIds: []),
            CapturedWindow(pid: 92832, wid: 29321, title: "~", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 884, y: 219), spaceIds: []),
            CapturedWindow(pid: 92832, wid: 29320, title: "~", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 855, y: 190), spaceIds: []),
        ]
    }()

    /// Two Finder windows of the SAME size parked apart, 3 tabs each, and the top one switching a tab
    /// (macOS 26, live QA T-20 2026-09-10). The switch takes the top window's active Space-less for the
    /// handover, which leaves the BOTTOM window as the cluster's only genuine Space holder:
    ///
    ///     +0:Finder#166416    g=nil sp=[3] 1000x440@80,600   ← the bottom window's active, declares 3 tabs
    ///     -1:Finder#166420    g=nil sp=[]  1000x440@80,80    ← the TOP window's ex-active, mid-switch
    ///     -2:Finder#166413    g=nil sp=[]  1000x440@80,600   ← a real inactive tab of the bottom window
    ///
    /// Three members against the bottom window's declared 3, nothing linked yet: the count "accounts for"
    /// the cluster by coincidence and waives the position split that is the only thing keeping the two
    /// windows apart. Live, `group form g1 rep=#166416 members=[166416, 166420, 166413] reason=geometry`,
    /// after which the title path (every Finder window is titled "lwouis") bridged the rest and ONE tile
    /// stood for both windows.
    static let finderTabSwitchInASecondSameSizeWindow: [CapturedWindow] = {
        let sz = CGSize(width: 1000, height: 440)
        return [
            CapturedWindow(pid: 11119, wid: 166416, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 80, y: 600), spaceIds: [3], axTabTitles: ["lwouis", "lwouis", "lwouis"]),
            CapturedWindow(pid: 11119, wid: 166420, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 80, y: 80), spaceIds: [], axTabTitles: ["lwouis", "lwouis", "lwouis"]),
            CapturedWindow(pid: 11119, wid: 166413, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 80, y: 600), spaceIds: []),
        ]
    }()

    /// Finder, Window ▸ Move Tab to New Window (macOS 26, live QA 2026-07-30). The tab was torn out into
    /// its own window at (290,712) and the drag-out was correctly confirmed — then geometry folded it straight
    /// back into the group it had just left:
    ///
    ///     +0:Finder#72914(FR) g=13 sp=[3] 920x436@1116,683   ← the group's active
    ///     -1:Finder#72915(t)  g=13 sp=[3] 920x436@290,712    ← the DRAGGED-OUT window, re-claimed
    ///     -2:Finder#72910(t)  g=13 sp=[3] 920x436@1116,683   ← a real inactive tab (borrowed Space)
    ///
    /// The vehicle is a STALE `tabCount`: 72915 read 3 tabs while it WAS the 3-tab active, and the count isn't
    /// retired while its window is still in a group (a nil read is transient, so retiring on it tore live
    /// groups apart). It then made a 3-member cluster look fully accounted for. What separates it from a merged
    /// group is that it GENUINELY holds a Space — a separate real window always does, and a merged group's
    /// absorbed tabs never do.
    static let finderTabDraggedOutStillClaimsThreeTabs: [CapturedWindow] = {
        let sz = CGSize(width: 920, height: 436)
        return [
            CapturedWindow(pid: 779, wid: 72914, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 1116, y: 683), spaceIds: [3]),
            CapturedWindow(pid: 779, wid: 72915, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 290, y: 712), spaceIds: [3], axTabTitles: ["lwouis", "lwouis", "lwouis"]),
            CapturedWindow(pid: 779, wid: 72910, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 1116, y: 683), spaceIds: [3]),
        ]
    }()

    /// Live 2026-08-02: two Finder windows, the front one (129409) mid tab-switch. Its 1326 has landed, so it
    /// is Space-less and HELD through the discovery gap, and its successor (129411, same frame) has not been
    /// discovered yet. The other window (129425) is untouched and browsing three tabs of its own, one of which
    /// (129421) is a brute-force-adopted inactive tab that kept its own frozen frame.
    ///
    /// Every Finder window is 1000x440, so all three land in one size cluster, and 129425's tab count (3)
    /// happens to equal the cluster's size — the coincidence that waives the position split.
    /// **rec28 (2026-08-26): a background tab reporting the frame of the WRONG window.** Two Finder
    /// windows, three tabs each, parked 520pt apart, every window 1000x440 and titled "lwouis" — so one size
    /// cluster, and POSITION is the only fact separating the two windows.
    ///
    /// Window A is parked at (80,80), window B at (80,600). Two kinds of wrong frame appear, and only one is
    /// benign: A's background tabs sit at (109,109), the cascade offset they had before the park, frozen
    /// because no geometry event reaches an ordered-out tab — stale, but still A's own history. B's
    /// background tabs report **(80,80)**, which is A's origin and was never B's. The position split is
    /// therefore handed a partition holding members of both windows, and the membership union bridges the
    /// rest in: one group of six under a representative declaring three tabs, five windows undrawn.
    ///
    /// Reproduced 4 runs in 8, always this shape. The two ACTIVES are what make it decidable: each declares
    /// its own 3-tab `AXTabGroup`, so the group that swallowed both is arithmetically impossible.
    static let finderTabLyingAboutItsWindowActiveA = CapturedWindow(
        pid: 1357, wid: 70958, title: "lwouis", subrole: "AXStandardWindow",
        size: CGSize(width: 1000, height: 440), position: CGPoint(x: 80, y: 80), spaceIds: [3],
        axTabTitles: ["lwouis", "lwouis", "lwouis"])
    /// A's own tabs, frozen at the pre-park cascade offset. Wrong, but consistent with A.
    static let finderTabLyingAboutItsWindowTabsA: [CapturedWindow] = [
        CapturedWindow(pid: 1357, wid: 70953, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 1000, height: 440), position: CGPoint(x: 109, y: 109), spaceIds: []),
        CapturedWindow(pid: 1357, wid: 70956, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 1000, height: 440), position: CGPoint(x: 109, y: 109), spaceIds: []),
    ]
    static let finderTabLyingAboutItsWindowActiveB = CapturedWindow(
        pid: 1357, wid: 70951, title: "lwouis", subrole: "AXStandardWindow",
        size: CGSize(width: 1000, height: 440), position: CGPoint(x: 80, y: 600), spaceIds: [3],
        axTabTitles: ["lwouis", "lwouis", "lwouis"])
    /// **The lie.** B's background tabs, reporting A's origin — a position that was never theirs.
    static let finderTabLyingAboutItsWindowTabsB: [CapturedWindow] = [
        CapturedWindow(pid: 1357, wid: 70944, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 1000, height: 440), position: CGPoint(x: 80, y: 80), spaceIds: []),
        CapturedWindow(pid: 1357, wid: 70949, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 1000, height: 440), position: CGPoint(x: 80, y: 80), spaceIds: []),
    ]

    static let finderTabSwitchBesideAnotherWindow: [CapturedWindow] = {
        let sz = CGSize(width: 1000, height: 440)
        return [
            CapturedWindow(pid: 1333, wid: 129425, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 157, y: 609), spaceIds: [3], axTabTitles: ["git", "lwouis", "Desktop"]),
            CapturedWindow(pid: 1333, wid: 129409, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 138, y: 138), spaceIds: [3]),
            CapturedWindow(pid: 1333, wid: 129421, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: CGPoint(x: 167, y: 167), spaceIds: []),
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
    /// window "Movies". Recorded by the maintainer during the tab-detection investigation: the active tab's
    /// AXTabGroup lists ["lwouis", "git"];
    /// "Movies" has no AXTabGroup. Distinct titles here (unlike Terminal's `~`), so matching is unambiguous.
    static let finderGitActive = CapturedWindow(pid: 779, wid: 4001, title: "git", subrole: "AXStandardWindow",
        size: CGSize(width: 900, height: 600), position: CGPoint(x: 200, y: 200), spaceIds: [1],
        axTabTitles: ["lwouis", "git"])
    static let finderLwouisInactiveTab = CapturedWindow(pid: 779, wid: 4002, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 900, height: 600), position: CGPoint(x: 200, y: 200), spaceIds: [])
    static let finderMoviesStandalone = CapturedWindow(pid: 779, wid: 4003, title: "Movies",
        subrole: "AXStandardWindow", size: CGSize(width: 500, height: 400), position: CGPoint(x: 50, y: 50), spaceIds: [1])

    /// FULLSCREEN Finder, tabs dragged out one at a time (2026-07-15, macOS 26, `--tab-diag` capture). macOS
    /// puts each extracted tab in its OWN new fullscreen Space, so the result is 3 SEPARATE fullscreen windows
    /// on 3 different Spaces — but each still carried the ORIGINAL group's `tabbedSiblingWids`, because AX
    /// exposes no tab titles for a fullscreen window (nothing can reconcile the stale link away). Ground truth:
    /// all three must show. Recorded live: wid, spaceIds, isFullscreen, and the stale shared link. The exact
    /// frame was NOT in the capture (the tile dump logs no size/position) — they're fullscreen on one screen so
    /// their sizes are necessarily equal, which is all the size-keyed clustering depends on.
    static let fullscreenFinderDragOutStaleGroup: [CGWindowID] = [72477, 72050, 72101]
    static let fullscreenFinderDragOutWindows: [CapturedWindow] = {
        let sz = CGSize(width: 1440, height: 900), pos = CGPoint(x: 0, y: 0)
        return zip([72477, 72050, 72101] as [CGWindowID], [4204, 4179, 4200] as [UInt64]).map { wid, space in
            CapturedWindow(pid: 779, wid: wid, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: pos, spaceIds: [space], isFullscreen: true, axTabTitles: nil)
        }
    }()

    /// Terminal tab group whose BACKGROUND TABS report a foreign, stale Space (2026-07-15 `--tab-diag`
    /// capture, taken while the user sat on a fullscreen Finder Space). The visible tab (71126) holds the
    /// normal Space 3628, yet five of its real background tabs report Space 4179 — a Space that isn't the
    /// visible's at all (it was one of Finder's fullscreen Spaces). They ARE genuinely tabs of 71126's group
    /// (a second switcher show collapsed them back to one tile). The ground truth that a background tab's
    /// `spaceIds` can be non-empty AND disjoint from its visible's — so "holds a Space the visible doesn't ⇒
    /// not a tab" is FALSE for normal windows, and un-grouping on it wrongly exploded the group into 6 tiles.
    /// Contrast `fullscreenFinderDragOutWindows`, where the same shape DOES mean separate windows — the
    /// difference is fullscreen (two fullscreen windows can never share a Space).
    static let terminalVisibleWithForeignSpaceTabs = CapturedWindow(pid: 92832, wid: 71126, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3628], axTabTitles: nil)
    static let terminalForeignSpaceBackgroundTabs: [CapturedWindow] = [71681, 71677, 71669, 71194, 71667].map {
        CapturedWindow(pid: 92832, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101), spaceIds: [4179])
    }

    /// Terminal, a LIVE 2-tab group where the ACTIVE tab transiently reported NO AXTabGroup (2026-07-14
    /// `--tab-diag`, non-fullscreen). Logged: `updateState active#66886 titles=["~","~"] matched=[66881]`
    /// (group established), then 3s later `updateState active#66886 nilTitles` while both tabs still existed.
    /// A nil read is routine during tab churn — even from the show-time AX review — so it must NEVER be taken
    /// as "the group dissolved". Both tabs held Space 3628 (the background tab's Space is backfilled).
    static let terminalLiveGroupActive = CapturedWindow(pid: 92832, wid: 66886, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3628], axTabTitles: nil)  // <- the transient nil read
    static let terminalLiveGroupBackgroundTab = CapturedWindow(pid: 92832, wid: 66881, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3628])

    /// The aftermath of that wrongful dissolution (same capture, 0.2s later): a NEW tab (66889) reports 4 "~"
    /// but its former siblings were just un-tabbed and still hold their STALE Space 3628 — so they are neither
    /// `isTabbed` nor Space-less and the strict matcher can claim none of them:
    /// `active#66889 titles=["~","~","~","~"] matched=[] untracked=["~","~","~"]` → 3 separate Terminal tiles.
    /// The ground truth that un-tabbing is effectively IRREVERSIBLE (a dissolved group can't be rebuilt from
    /// these facts) — which is exactly why a nil read must not dissolve.
    static let terminalAfterDissolutionActive = CapturedWindow(pid: 92832, wid: 66889, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3628], axTabTitles: ["~", "~", "~", "~"])
    static let terminalAfterDissolutionOrphans: [CapturedWindow] = [66886, 66881].map {
        CapturedWindow(pid: 92832, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101), spaceIds: [3628])
    }

    /// The NEW-TAB CREATION RACE (2026-07-14 `--tab-diag`, non-fullscreen). Cmd-T: the new tab (67088) is
    /// discovered and is the group's active, but the PREVIOUS active (67085) still holds Space 3628 — its
    /// "removed from Space" (1326) hasn't landed — so it is neither `isTabbed` nor Space-less. Logged tile
    /// dump: `+0:Terminal#67088sp[3628] +1:Terminal#67085sp[3628] -2:Terminal#67081(t) -3:Terminal#67075(t)`
    /// — TWO shown Terminal tiles. Ground truth: one tile; 67085 is a backgrounding tab, not a separate window.
    static let terminalNewTabActive = CapturedWindow(pid: 92832, wid: 67088, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3628], axTabTitles: ["~", "~", "~", "~"])
    static let terminalNewTabStaleOldActive = CapturedWindow(pid: 92832, wid: 67085, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101),
        spaceIds: [3628])  // stale: its 1326 hasn't arrived yet
    static let terminalNewTabSettledTabs: [CapturedWindow] = [67081, 67075].map {
        CapturedWindow(pid: 92832, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 757, height: 583), position: CGPoint(x: 683, y: 101), spaceIds: [3628])
    }

    /// **#5785 — the tab title is NOT the window title.** Stock Terminal (macOS 26, captured 2026-07-26 by
    /// restoring the reporter's profile settings: `ShowDimensionsInTitle` + `ShowActiveProcessInTitle` on,
    /// which is the macOS DEFAULT). The window title carries components the TAB title has no setting for at
    /// all, so the two strings can never be equal:
    ///
    ///     WINDOW "~/Documents — -zsh ▸ -zsh — 80×23"     TAB "~/Documents"
    ///
    /// Every title-keyed decision failed at once. Logged from the live app before the fix:
    /// `updateState active#28963 titles=["~", "~/Downloads", "~/Documents"] matched=[] untracked=[all three]`
    /// — so `siblingWids.count == 1`, the group was dissolved as `axTitlesSolo` on every AX read while
    /// geometry re-formed it on every WindowServer event, and only 1 of the 3 Terminal windows survived in
    /// the model. This capture is the ground truth that the title signal can be TOTALLY absent, not merely
    /// noisy: the reporter's tabs are real tabs of one window, and no title comparison can discover that.
    /// Geometry from the same recipe's `--detailed-list`; `spaceIds` for the active from the TABDIAG
    /// `geometryGroup visible#28963 sp[4]` line, and the background tab is Space-less as CGS reports it.
    static let composedTitleActiveTab = CapturedWindow(pid: 69883, wid: 28963,
        title: "~/Documents — -zsh ▸ -zsh — 80×23", subrole: "AXStandardWindow",
        size: CGSize(width: 757, height: 543), position: CGPoint(x: 38, y: 39), spaceIds: [4],
        axTabTitles: ["~", "~/Downloads", "~/Documents"])
    static let composedTitleBackgroundTab = CapturedWindow(pid: 69883, wid: 28961,
        title: "~/Downloads — -zsh ▸ -zsh — 80×23", subrole: "AXStandardWindow",
        size: CGSize(width: 757, height: 543), position: CGPoint(x: 38, y: 39), spaceIds: [])

    /// The SAME defect on the REPORTER's machine, from their own #5785 logs (2026-07-25, macOS 26.5, their
    /// Terminal at 140×35). Recorded here is ONLY what their logs actually contain: the wids, the composed
    /// window titles, the size from the accept line, the active's Space from its 1325 and the background
    /// tab's Space-lessness from its 1326. Their AXTabGroup titles were NEVER captured — the `--tab-diag`
    /// flag never took effect, since `open --args` drops its arguments when the app is already running — so
    /// `axTabTitles` stays nil rather than being reconstructed from the window titles, and POSITION is nil
    /// because their logs record size but never position. Tests must supply what the capture lacks and say
    /// where that comes from.
    ///
    /// The ground truth these two are tabs of ONE window is the Space-swap signature in the log, not an AX
    /// read: `windowAddedToSpace space=1 wid=13885` / `windowRemovedFromSpace space=1 wid=13612` in the same
    /// millisecond. Their log also shows each tab discovered as its own window
    /// (`discovered a new window:(pid:47566 … wid:13885)`), one every ~250ms during a Cmd-T burst.
    static let reporterComposedTitleActiveTab = CapturedWindow(pid: 47566, wid: 13885,
        title: "Terminal — mkdir ◂ -zsh — 140×35", subrole: "AXStandardWindow",
        size: CGSize(width: 1017, height: 610), position: nil, spaceIds: [1])
    static let reporterComposedTitleBackgroundTab = CapturedWindow(pid: 47566, wid: 13612,
        title: "Downloads — -zsh — 140×35", subrole: "AXStandardWindow",
        size: CGSize(width: 1017, height: 610), position: nil, spaceIds: [])

    /// FULLSCREEN Terminal, a new tab created inside the fullscreen window (2026-07-15 `--tab-diag`). AX
    /// exposes NO tab titles for a fullscreen window (`axTabTitles` nil), so the count-driven claim is inert.
    /// Logged: `discovered new#70294 app=Terminal axTitles=[] siblings=[...] sp[4059]`, and the tile dump
    /// `+0:Terminal#70294sp[4059] +1:Terminal#70291sp[4059]` — the new tab AND the previous active BOTH hold
    /// the one fullscreen Space 4059 (the old one's 1326 lags), while older tabs are Space-less. Ground truth:
    /// one tile. Unlike a windowed group, all fullscreen tabs share the fullscreen frame, so sizes match.
    static let fullscreenTerminalNewTab = CapturedWindow(pid: 92832, wid: 70294, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 1440, height: 864), position: CGPoint(x: 0, y: 36),
        spaceIds: [4059], isFullscreen: false, axTabTitles: nil)  // its OWN fullscreen flag lags discovery
    static let fullscreenTerminalOldActive = CapturedWindow(pid: 92832, wid: 70291, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 1440, height: 864), position: CGPoint(x: 0, y: 36),
        spaceIds: [4059], isFullscreen: true)
    static let fullscreenTerminalSettledTabs: [CapturedWindow] = [70288, 70220].map {
        CapturedWindow(pid: 92832, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 1440, height: 864), position: CGPoint(x: 0, y: 36), spaceIds: [], isFullscreen: true)
    }

    /// A FULLSCREEN tab SWITCH, raw events (2026-07-15 `--tab-diag`). Switching to a background tab emits NO
    /// `windowAddedToSpace` for a TRACKED wid — across every fullscreen recording there was not one. The
    /// incoming tab arrives as an UNTRACKED wid (fullscreen background tabs drop out of tracking) and is
    /// re-DISCOVERED, while the outgoing active gets its 1326. So its physical stream has no promotion for
    /// the new object: no 808, no create, no add-for-a-tracked-window — it must be fronted explicitly
    /// or it lands at the back of the MRU (the tile appearing "on the right", then jumping left).
    static let fullscreenTabSwitchEvents: [(id: UInt32, space: UInt64, wid: CGWindowID)] = [
        (1325, 4059, 70211),   // windowAddedToSpace — the INCOMING tab, untracked at this point
        (1325, 4059, 70212),
        (1326, 4059, 70217),   // windowRemovedFromSpace — the outgoing active
    ]

    // MARK: - Tab grouping (geometryGroups)

    func testMergedTabsGroupByGeometry() {
        // The merged group as geometry sees it: the active tab holds a Space and (AX having confirmed the
        // group) carries its `tabbedSiblingWids`; the 3 background tabs are Space-less ⇒ grouped under it.
        let active = Self.terminalMerge4Tabs[0].tabWindow(tabbedSiblingWids: [29328, 29326, 29321, 29320])
        let background = Self.terminalMerge4Tabs.dropFirst().map { $0.tabWindow(isTabbed: true) }
        XCTAssertEqual(TabGroupResolver.geometryGroups([active] + background),
            [GeometryGroup(visibleWid: 29328, backgroundWids: [29326, 29321, 29320])])
    }

    func testMergedTabsFormAGroupFromNothingButTheTabCount() {
        // The state a merge ACTUALLY leaves (live QA 2026-07-30, Finder + Terminal): no window
        // carries a link, because the title path can't make one — every tab is titled "~" and they sit at
        // four DIFFERENT cascade positions, so `positionsCompatible` rejects each candidate. Geometry was the
        // only path left and it never even formed a cluster: `framePartitions` split the four tabs into four
        // partitions of one. So AltTab held 4 windows, 0 groups, and hid 3 of them as phantoms — with "Group
        // tabs: separate window for each tab" the user saw 1 tile instead of 4.
        //
        // The visible's own AXTabGroup says "4 tabs" and there are exactly 4 same-size candidates. That
        // accounts for every member with no room for an intruder, which is the one thing position was
        // protecting against, so the cascade must not veto the cluster.
        let windows = Self.terminalMerge4Tabs.map { $0.tabWindow() }
        XCTAssertEqual(TabGroupResolver.geometryGroups(windows),
            [GeometryGroup(visibleWid: 29328, backgroundWids: [29326, 29321, 29320])])
    }

    func testASecondWindowsActiveTabIsNotSweptInByACountItAlsoDeclares() {
        // The count waiver has to survive a cluster that holds another window's ACTIVE tab: 166420 declares
        // an AXTabGroup of its own from a different position, so the bottom window's 3 cannot be an account
        // of all three members however well it adds up.
        let windows = Self.finderTabSwitchInASecondSameSizeWindow.map { $0.tabWindow() }
        XCTAssertEqual(TabGroupResolver.geometryGroups(windows),
            [GeometryGroup(visibleWid: 166416, backgroundWids: [166413])])
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

    func testADraggedOutWindowIsNotFoldedBackByAStaleTabCount() {
        // Live 2026-07-30, transcribed from `group form g13 members=[72914, 72915, 72910] reason=geometry
        // | geometryGroup Finder visible#72914 sp[3] background=[72915, 72910]`: the tab was torn out into its
        // own window, the drag-out was correctly confirmed, and then geometry put it straight back.
        //
        // The position split had been waived because 72915's STALE `tabCount` (3, from when it was the 3-tab
        // active) matched the 3-member cluster — while the genuine on-screen member, 72914, read 2. Note what
        // does NOT save 72915: it shows `sp[3]` but that Space is OUR annotation by then (normalize lends a
        // group's members one), so it is a background candidate like any other. Only the on-screen member's
        // count describes the cluster, because only an active tab reports an AXTabGroup at all.
        // The AX read in that same dispatch had ALREADY re-formed the real group (`group form g12
        // rep=#72914 members=[72914, 72910] reason=axTitles`) before geometry ran — so the visible is
        // AX-confirmed, which is precisely the case that skips the tab-count BOUND (seed 163). Without this
        // fact the bound refuses the fold on its own and the test cannot bite.
        let realGroup: [CGWindowID] = [72914, 72910]
        var active = Self.finderTabDraggedOutStillClaimsThreeTabs[0]
            .tabWindow(tabbedSiblingWids: realGroup, tabCount: 2)
        active.lastFocusOrder = 0
        var draggedOut = Self.finderTabDraggedOutStillClaimsThreeTabs[1].tabWindow()   // tabCount 3, stale
        draggedOut.spaceIsBorrowed = true
        draggedOut.lastFocusOrder = 1
        var realTab = Self.finderTabDraggedOutStillClaimsThreeTabs[2]
            .tabWindow(isTabbed: true, tabbedSiblingWids: realGroup)
        realTab.spaceIsBorrowed = true                                                 // backfilled by normalize
        realTab.lastFocusOrder = 2
        for group in TabGroupResolver.geometryGroups([active, draggedOut, realTab]) {
            XCTAssertFalse(group.siblingWids.contains(72915),
                           "#72915 was dragged OUT to (290,712) — the group at (1116,683) must not re-claim it")
        }
    }

    /// **rec28, at the reducer: the membership union turns one wrong claim into a merged window.**
    ///
    /// The kernel test above shows geometry claiming B's two lying tabs into A's group — three members,
    /// which is within A's declared tab count and so survives every size check. The damage is done by the
    /// UNION in `discoveryLanded`: having claimed a member of B's group, geometry pulls in that member's
    /// whole existing membership, and B's active comes with it. Six windows, one group, five undrawn — the
    /// live shape, `group form g5 rep=#70958 members=[70958, 70949, 70956, 70953, 70951, 70944]`.
    ///
    /// The union itself is right for the case it was written for: geometry's candidate set excludes
    /// minimized and size-less windows, so a member it cannot see must not be read as having left. What it
    /// may not do is treat a window geometry just took FROM ANOTHER GROUP as a reason to annex that group.
    func testGeometryDoesNotAnnexAnotherWindowsGroupThroughOneClaimedTab() {
        var s = TrackedWindowState()
        let captured = [Self.finderTabLyingAboutItsWindowActiveA, Self.finderTabLyingAboutItsWindowActiveB]
            + Self.finderTabLyingAboutItsWindowTabsA + Self.finderTabLyingAboutItsWindowTabsB
        s.windows = captured.enumerated().map { i, c in
            TrackedWindow(id: "wid-\(c.wid)", wid: c.wid, pid: c.pid, title: c.title, size: c.size,
                position: c.position, spaceIds: c.spaceIds, spaceIndexes: [], isOnAllSpaces: false,
                spaceIsBorrowed: false, isFullscreen: false, isFullscreenMirrored: false, isMinimized: false,
                isMainWindow: false, isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: i,
                creationOrder: Int(c.wid), hasThumbnail: true)
        }
        s.apps[1357] = TrackedApp(state: ApplicationState(pid: 1357, bundleIdentifier: "com.apple.finder",
            localizedName: "Finder", isHidden: false), isActive: true)
        s.frontmostPid = 1357
        s.visibleSpaces = [3]
        s.currentSpaceId = 3
        s.spaceIndexById = [3: 1]
        // what the AX-titles path had already worked out, correctly, before geometry ran (live: g2 and g4)
        _ = s.formGroup([Self.finderTabLyingAboutItsWindowActiveA.wid]
            + Self.finderTabLyingAboutItsWindowTabsA.map { $0.wid },
            representative: Self.finderTabLyingAboutItsWindowActiveA.wid, reason: "axTitles")
        _ = s.formGroup([Self.finderTabLyingAboutItsWindowActiveB.wid]
            + Self.finderTabLyingAboutItsWindowTabsB.map { $0.wid },
            representative: Self.finderTabLyingAboutItsWindowActiveB.wid, reason: "axTitles")
        XCTAssertEqual(Set(s.windows.compactMap { $0.wid.flatMap { s.groups.groupId(of: $0) } }).count, 2,
                       "precondition: the titles path built two groups")
        // the geometry pass, as the live capture triggered it
        _ = WindowEventReducer.reduce(&s, .windowServerStateRead(s.windows.compactMap { w in
            guard let wid = w.wid, let position = w.position, let size = w.size else { return nil }
            return WsWindowSnapshot(wid: wid, position: position, size: size, isFullscreen: false,
                isVisible: !w.spaceIds.isEmpty)
        }))
        let groupSizes = Dictionary(grouping: s.windows.compactMap { w -> Int? in
            w.wid.flatMap { s.groups.groupId(of: $0) }
        }, by: { $0 }).mapValues { $0.count }
        XCTAssertTrue(groupSizes.values.allSatisfy { $0 <= 3 },
                      "a group grew past either window's declared 3 tabs: \(groupSizes)")
        let aGroup = s.groups.groupId(of: Self.finderTabLyingAboutItsWindowActiveA.wid)
        let bGroup = s.groups.groupId(of: Self.finderTabLyingAboutItsWindowActiveB.wid)
        XCTAssertNotEqual(aGroup, bGroup,
                          "both windows' active tabs share a group, so one window is not drawn")
    }

    /// **rec28: two Finder windows must not fold into one group when a background tab lies about its
    /// frame.** Live 2026-08-26 (4 reds in 8 runs). Both actives declare their own 3-tab AXTabGroup,
    /// so no group may hold more than three of these six windows — six under one representative is two
    /// windows merged, and five tiles the user cannot reach.
    ///
    /// The lie is B's background tabs reporting A's origin. Position is the only fact separating two
    /// same-size windows, so the split cannot be rescued by tolerance: the frame belongs to another window.
    func testAWindowIsNotAnnexedByATabLyingAboutItsFrame() {
        let windows = [Self.finderTabLyingAboutItsWindowActiveA.tabWindow(),
                       Self.finderTabLyingAboutItsWindowActiveB.tabWindow()]
            + Self.finderTabLyingAboutItsWindowTabsA.map { $0.tabWindow() }
            + Self.finderTabLyingAboutItsWindowTabsB.map { $0.tabWindow() }
        let groups = TabGroupResolver.geometryGroups(windows)
        for group in groups {
            let size = Set([group.visibleWid] + group.siblingWids).count
            XCTAssertLessThanOrEqual(size, 3,
                "group visible#\(group.visibleWid) holds \(size) of the six windows; each active declares "
                    + "3 tabs, so this spans two windows: \(group.siblingWids)")
        }
        // and specifically: the two ACTIVES may never share a group, whoever else moved
        let actives: Set<CGWindowID> = [Self.finderTabLyingAboutItsWindowActiveA.wid,
                                        Self.finderTabLyingAboutItsWindowActiveB.wid]
        for group in groups {
            let members = Set([group.visibleWid] + group.siblingWids)
            XCTAssertNotEqual(members.intersection(actives).count, 2,
                "both windows' active tabs landed in one group, so one window is not drawn")
        }
    }

    func testASwitchingWindowIsNotFoldedIntoTheNeighbourItOutranksInMru() {
        // Live 2026-08-02, transcribed from `group form g1 rep=#129425 members=[129425, 129409, 129421]
        // reason=geometry | geometryGroup Finder visible#129425 sp[3] background=[129409, 129421]`: switching a
        // tab in the FRONT Finder window folded the OTHER Finder window's whole cluster over it. 129409 stopped
        // being drawn, so the summon 15ms later offered 4 tiles instead of 5 and the default pick landed on
        // Claude rather than the other Finder window (the user's report; the selection kernel was right, it was
        // handed a list with a window missing).
        //
        // What waives the position split is 129425's tab count (3) matching the three-member cluster — the
        // third tab is untracked, and 129409 filled its slot. What must refuse the fold is MRU: 129409 was
        // focused LAST (`mru bump #129409 from=0`, 3s earlier), so it outranks the very window it is being
        // called a background tab of. A group's active tab is its most recently focused member by definition.
        //
        // The neighbour's own group must still form: 129421 is genuinely 129425's inactive tab.
        var switching = Self.finderTabSwitchBesideAnotherWindow[1].tabWindow()
        switching.isHeld = true                                       // held through the discovery gap
        switching.lastFocusOrder = 0
        var neighbour = Self.finderTabSwitchBesideAnotherWindow[0].tabWindow()
        neighbour.lastFocusOrder = 1
        var neighbourTab = Self.finderTabSwitchBesideAnotherWindow[2].tabWindow()
        neighbourTab.lastFocusOrder = 2
        let groups = TabGroupResolver.geometryGroups([neighbour, switching, neighbourTab])
        for group in groups {
            XCTAssertFalse(group.siblingWids.contains(129409),
                           "#129409 is switching a tab at (138,138) and outranks #129425 in MRU — the window "
                               + "at (157,609) must not claim it as a background tab")
        }
        XCTAssertEqual(groups.map { Set($0.siblingWids) }, [Set([129425, 129421])],
                       "#129421 is #129425's real inactive tab, so its group must still form")
    }

    func testMergedTabsMatchByTitleOnlyOnceGeometryHasLinkedThem() {
        // The title path CANNOT bootstrap a merged group, and must not be taught to: the tabs sit at four
        // distinct cascade positions (see the capture) and every one is titled "~", so waiving the position
        // test here is exactly rec11 — two cascaded windows whose tabs all share a title, mutually claimable
        // on every other fact. So the first read names nobody and reports the three titles untracked.
        let active = Self.terminalMerge4Tabs[0]
        let m = TabGroupResolver.matchSiblings(active: active.tabWindow(), axTitles: active.axTabTitles!,
            sameAppWindows: Self.terminalMerge4Tabs.map { $0.tabWindow() })
        XCTAssertEqual(m, SiblingMatch(siblingWids: [29328], matchedWids: [],
            untrackedTitles: ["~", "~", "~"], toUntabWids: []))
        // Geometry forms the group (`testMergedTabsFormAGroupFromNothingButTheTabCount`), which writes the
        // link — and `positionsCompatible`'s link bypass then makes this path agree, so the group is stable
        // rather than re-decided against the stale cascade on every subsequent read.
        let group: [CGWindowID] = [29328, 29326, 29321, 29320]
        let linked = TabGroupResolver.matchSiblings(active: active.tabWindow(tabbedSiblingWids: group),
            axTitles: active.axTabTitles!,
            sameAppWindows: Self.terminalMerge4Tabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) })
        XCTAssertEqual(linked, SiblingMatch(siblingWids: group, matchedWids: [29326, 29321, 29320],
            untrackedTitles: [], toUntabWids: []))
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
        XCTAssertTrue(PhantomWindowDetector.syncVerdict(bg.windowState(isTabbed: false), Self.terminalApp,
            isOrderedIn: false, alpha: 1))
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(bg.windowState(isTabbed: true), Self.terminalApp,
            isOrderedIn: false, alpha: 1))
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

    /// FULLSCREEN Finder, adding a tab (2026-07-15 `--tab-diag`, the first capture with frames). Decisive log:
    ///   `removed tracked#72050 sp[4267]` → `hold-visible #72050 (recent create)`
    ///   `geometryGroup visible#72050 background=[73147]`   ← INVERTED: the OLD tab chosen as the visible
    ///   `discovered new#73147 axTitles=[] isTabbed=true siblings=[72050, 73147]`
    ///   …14s later: `geometryGroup visible#73147 background=[72050]`   ← flips the other way
    /// Observed by the maintainer: the switcher showed the PREVIOUS tab, then settled on TWO tiles that
    /// persisted across shows. GROUND TRUTH: one tile, showing the NEW tab (73147).
    ///
    /// Why it inverted: the old tab had just been backgrounded (1326) and was held visible with a BORROWED
    /// Space, while the brand-new tab was momentarily Space-less — so the visible-pick, which only considers
    /// Space-holding members and prefers "no link yet", saw the held old tab as the only candidate. Two
    /// heuristics (hold + Space borrow) fed a false input to a third (visible-pick). The frames prove they are
    /// one group: both 2048×1152@0,0 fullscreen on Space 4267. `72045` is a sibling still frozen at the
    /// pre-fullscreen size (920×436), which is why size-clustering leaves it out entirely.
    static let fullscreenFinderAddTabNewTab = CapturedWindow(pid: 779, wid: 73147, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 2048, height: 1152), position: CGPoint(x: 0, y: 0),
        spaceIds: [], isFullscreen: true, axTabTitles: nil)          // brand-new: no link, momentarily Space-less
    static let fullscreenFinderAddTabHeldOldActive = CapturedWindow(pid: 779, wid: 72050, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 2048, height: 1152), position: CGPoint(x: 0, y: 0),
        spaceIds: [4267], isFullscreen: true, axTabTitles: nil)      // backgrounded, held, Space borrowed back
    static let fullscreenFinderAddTabFrozenSibling = CapturedWindow(pid: 779, wid: 72045, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 249, y: 205),
        spaceIds: [], isFullscreen: true, axTabTitles: nil)          // frozen at the pre-fullscreen size

    /// FULLSCREEN Finder, switching tabs (2026-07-15 `--tab-diag`). The group was correctly linked —
    /// `geometryGroup visible#72050 background=[73147, 73201]` — and then the visible itself backgrounded:
    ///   `removed tracked#72050 sp[4267]` → `hold-visible #72050 (recent create)`
    /// 0.2s later the switcher showed THREE Finder tiles, all 2048×1152@0,0 fullscreen on Space 4267, none
    /// tabbed — and it persisted. GROUND TRUTH: one tile; these are three tabs of ONE fullscreen window.
    ///
    /// The state that breaks it: the group's visible is momentarily Space-less (it just backgrounded and is
    /// held), while its background tabs still carry the backfilled Space. Any rule phrased as "holds a Space
    /// the visible doesn't" degenerates here — against an EMPTY visible Space every member looks disjoint, so
    /// all of them get treated as having left, are UNLINKED, and the group can never re-form.
    static let fullscreenFinderSwitchHeldVisible = CapturedWindow(pid: 779, wid: 72050, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 2048, height: 1152), position: CGPoint(x: 0, y: 0),
        spaceIds: [], isFullscreen: true, axTabTitles: nil)   // just backgrounded + held ⇒ no Space of its own
    static let fullscreenFinderSwitchBackgroundTabs: [CapturedWindow] = [73147, 73201].map {
        CapturedWindow(pid: 779, wid: $0, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 2048, height: 1152), position: CGPoint(x: 0, y: 0), spaceIds: [4267],
            isFullscreen: true)
    }

    /// TWO fullscreen Finder windows, each with tabs (2026-07-15 `--tab-diag`). Every fullscreen window is
    /// SCREEN-sized, so all four windows land in ONE size cluster (2048×1152@0,0) spanning TWO Spaces:
    ///   `+0:Finder#72050(f) sp[4267]  *+1:Finder#73377(f) sp[4282]  +2:Finder#73381(fh) sp[4282]
    ///    -3:Finder#72045(tf) sp[4267]`
    /// Observed: THREE tiles for TWO windows — Space 4267 resolved (72050 visible, 72045 tabbed) but Space
    /// 4282's two tabs both showed. GROUND TRUTH: two tiles, one per fullscreen window.
    /// The fullscreen invariant is about each SPACE, not the cluster: asking "does the CLUSTER span ≤1 Space"
    /// bailed here (it spans 2), so nothing folded. Each Space must be resolved on its own.
    static let twoFullscreenFinderWindowsWithTabs: [CapturedWindow] = {
        let sz = CGSize(width: 2048, height: 1152), pos = CGPoint(x: 0, y: 0)
        return [(CGWindowID(72050), UInt64(4267)), (72045, 4267), (73377, 4282), (73381, 4282)].map { wid, space in
            CapturedWindow(pid: 779, wid: wid, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: pos, spaceIds: [space], isFullscreen: true, axTabTitles: nil)
        }
    }()

    /// Switching BETWEEN two fullscreen Finder windows (2026-07-15 `--tab-diag`). Mid-transition EVERY window
    /// of the app reports BOTH fullscreen Spaces at once:
    ///   `+0:Finder#73888(f) sp[4310, 4305]   -1:Finder#73841(tf) sp[4310, 4305]`
    ///   `-2:Finder#73977(tf) sp[4310, 4305]  -3:Finder#73940(tf) sp[4310, 4305]`
    /// Observed: `73977` — the OTHER fullscreen window — was folded into `73888`'s group and hidden, so the
    /// switcher's default pick fell past both Finder tiles onto Claude. 0.14s later the Spaces settled
    /// (`73888 sp[4305]`, `73977 sp[4310]`) and it un-hid, but the selection stayed stuck on Claude.
    /// GROUND TRUTH: while every member reports two Spaces nothing is attributable — form NO new group and
    /// leave existing links alone; never fold two separate fullscreen windows together.
    static let twoFullscreenFinderWindowsMidSpaceSwitch: [CapturedWindow] = {
        let sz = CGSize(width: 2048, height: 1152), pos = CGPoint(x: 0, y: 0)
        return [CGWindowID(73888), 73841, 73977, 73940].map {
            CapturedWindow(pid: 779, wid: $0, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: pos, spaceIds: [4310, 4305], isFullscreen: true, axTabTitles: nil)
        }
    }()

    /// TWO separate Finder windows that SHARE a tab title, both discovered at launch (2026-07-15 `--tab-diag`).
    /// `73888` is a 2-tab window (`["lwouis", "Applications"]`); `73977` is a DIFFERENT window that is the
    /// active tab of its OWN 3-tab group (`["Movies", "lwouis", "lwouis"]`, read moments later) and is titled
    /// "lwouis". Logged:
    ///   `updateState active#73888 NEW titles=["lwouis", "Applications"] matched=[73977]`
    ///   `show ... -1:Finder#73977(t)920x436@220,176sp[3] ...`   ← a REAL window, tabbed and hidden
    /// GROUND TRUTH: `73977` is its own window and must never be claimed by `73888`.
    ///
    /// This is "the void": a real window wrongly hidden, so the switcher's default selection was computed
    /// without it and landed elsewhere; it reappeared once its own AX read ran, leaving the selection stale.
    /// The on-screen claim only makes sense for a tab the user JUST CREATED taking over its group — at launch
    /// every window is newly TRACKED, and letting the claim fire there had windows swallow each other.
    static let finderTwoWindowsSharingATabTitleActive = CapturedWindow(pid: 779, wid: 73888, title: "Applications",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 220, y: 176),
        spaceIds: [3], axTabTitles: ["lwouis", "Applications"])
    static let finderTwoWindowsSharingATabTitleOther = CapturedWindow(pid: 779, wid: 73977, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 220, y: 176),
        spaceIds: [3], axTabTitles: ["Movies", "lwouis", "lwouis"])

    /// Switching back and forth between Finder windows (2026-07-15 `--tab-diag`, rec9). The MRU log shows
    /// `mru bump #74626` — it is the most recently focused window — yet the tile dump shows it TABBED:
    ///   `-0:Finder#74626(t)920x436@191,147sp[3628]  +1:Finder#74625  *+2:Finder#74628`
    /// so it was hidden, and the default selection landed on the 2nd visible of a model missing it.
    ///
    /// GROUND TRUTH: **the focused window can never be a background tab** — focusing a tab makes it its
    /// group's ACTIVE tab, by definition. Enforced in `groupRepresentative` (when a coherent group has no
    /// visible member, the FOCUSED member recovers it — `TabWindow.lastFocusOrder` carries the signal) and
    /// pinned by `testCoherentGroupThatLostItsVisibleRecoversViaTheFocusedMember`.
    static let finderFocusedWindowWronglyTabbed: [(wid: CGWindowID, lastFocusOrder: Int, isTabbed: Bool)] = [
        (74626, 0, true),   // ← most recently focused, yet tabbed+hidden: the contradiction
        (74625, 1, false),
        (74628, 2, false),
        (74820, 3, true),
    ]

    /// Several Finder windows whose tab groups SHARE tab titles (2026-07-15 `--tab-diag`, rec10). Two windows
    /// are each the active tab of their own group, and both groups contain a tab titled "lwouis":
    ///   `updateState active#74624 titles=["Movies","lwouis","lwouis"]  matched=[] untracked=["lwouis","lwouis"]`
    ///   `updateState active#74626 titles=["lwouis","Downloads","lwouis"] matched=[74820] untab=[74628]`
    /// and the resulting links CONTRADICT each other — 74820 is claimed by two groups at once:
    ///   `updateState active#74625 nilTitles keptGroup siblings=[74625, 74820]`
    ///   `updateState active#74820 nilTitles keptGroup siblings=[74628, 74820, 74626]`
    /// then geometry compounds it via 74625's stale link: `geometryGroup visible#74625 background=[74628]`,
    /// swallowing a window that belongs to the OTHER Finder window (same size, momentarily Space-less).
    ///
    /// Positions are the giveaway: 74628 and 74820 sit at (191,147) — one window's tabs — while 74625 is at
    /// (523,501), a SEPARATE window. GROUND TRUTH: each window belongs to AT MOST ONE group.
    ///
    /// This is the documented limitation biting hard: macOS exposes no tab→window mapping, so title is the
    /// only key, and `matchSiblings` resolves each group INDEPENDENTLY — so two
    /// groups can claim the same window behind each other's backs and no single call can see the conflict.
    static let finderDuplicateTabTitlesActiveA = CapturedWindow(pid: 779, wid: 74624, title: "Movies",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 324, y: 480),
        spaceIds: [3], axTabTitles: ["Movies", "lwouis", "lwouis"])
    static let finderDuplicateTabTitlesActiveB = CapturedWindow(pid: 779, wid: 74626, title: "Downloads",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 191, y: 147),
        spaceIds: [3628], axTabTitles: ["lwouis", "Downloads", "lwouis"])
    /// B's real tabs, at B's frame (191,147).
    static let finderDuplicateTabTitlesTabsOfB: [CapturedWindow] = [74820, 74628].map {
        CapturedWindow(pid: 779, wid: $0, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 191, y: 147), spaceIds: [])
    }
    /// A SEPARATE Finder window that merely shares the title — at its own frame (523,501). Must join nothing.
    static let finderDuplicateTabTitlesStandalone = CapturedWindow(pid: 779, wid: 74625, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 523, y: 501),
        spaceIds: [3628])

    // MARK: - The cross-cutting invariant
    //
    // Every theft this corpus records — rec8, rec10, rec11, rec12 — was ONE bug: a window at frame F grouped
    // with a window at a different frame F'. Each was fixed where its own scenario happened to hit (the
    // confirmed-cluster gate, the self-only link, the title matcher's 50px tolerance, geometry's cluster key),
    // and each time it simply reappeared through whichever path was still open — because a per-scenario test
    // only pins the path that scenario took. This asserts the RULE over the whole corpus instead, so the next
    // claim path added has to satisfy it too.
    //
    // Fullscreen is exempt by construction: a fullscreen window's tabs genuinely can't share its frame (their
    // position freezes at the pre-fullscreen origin), which is why those clusters are separated by Space.

    /// Every multi-window capture in the corpus, as the kernel sees it. Extend this when adding a capture.
    private static var frameCorpus: [(String, [TabWindow])] {
        let dupTabs = finderDuplicateTabTitlesTabsOfB.map { $0.tabWindow() }
        return [
            ("terminalMerge4Tabs", terminalMerge4Tabs.map { $0.tabWindow() }),
            ("finderDuplicateTabTitles", [finderDuplicateTabTitlesActiveA.tabWindow(),
                                          finderDuplicateTabTitlesActiveB.tabWindow(),
                                          finderDuplicateTabTitlesStandalone.tabWindow()] + dupTabs),
            ("finderSelfOnlyLinkNewTabGap", [finderSelfOnlyLinkNewTabGapVisible.tabWindow(),
                                             finderSelfOnlyLinkNewTabGapBackgrounding.tabWindow(
                                                tabbedSiblingWids: [74626])]),
            ("finderTwoCascadedWindows", [finderTwoCascadedWindowsActiveA.tabWindow()]
                + finderTwoCascadedWindowsTabsA.map { $0.tabWindow() }
                + finderTwoCascadedWindowsTabsB.map { $0.tabWindow() }),
            ("finderTabSwitch", [finderTabSwitchIncomingSettled.tabWindow(), finderTabSwitchOutgoing.tabWindow()]),
            // two coexisting groups at DISTINCT frames + standalones — the exact shape the invariant polices
            ("twoGroupsSameApp", twoGroupsSameApp.map { $0.tabWindow() }),
            // rec21: a fullscreened window's frozen tabs (raw facts: NOT fullscreen) + another window's active
            ("finderThreeFramesAfterFullscreen",
             [finderFullscreenedWindowActive.tabWindow(), finderOtherWindowActiveAfterFullscreen.tabWindow()]
                + finderFullscreenedWindowFrozenTabs.map { $0.tabWindow() }),
        ]
    }

    /// THE invariant: geometry never puts two DIFFERENT windows in one group. Two windows are different exactly
    /// when their frames differ — a tab is its parent's frame, so tabs of one window agree on it.
    ///
    /// **With the one exception the OS forced (live QA 2026-07-30).** "Tabs of one window agree on the frame"
    /// is false after Merge All Windows: the merge never converges the tabs' frames, so a merged group spans a
    /// 29px cascade forever (`terminalMerge4Tabs`) and holding the invariant unconditionally meant no merged
    /// group could ever form. Frames may differ only where AX ITSELF accounted for every member — the visible's
    /// AXTabGroup count equals the cluster size, leaving no room for an intruder. Anything looser is rec11: two
    /// cascaded Finder windows whose tab titles all matched, where position was the only separating fact and
    /// the AX count (11 titles for 8 tracked wids) bounded nothing.
    func testNoGeometryGroupEverMixesDistinctFrames() {
        for (name, windows) in Self.frameCorpus {
            for group in TabGroupResolver.geometryGroups(windows) {
                let members = group.siblingWids.compactMap { wid in windows.first { $0.wid == wid } }
                let frames = Set(members.filter { !$0.isFullscreen }.map(Self.frameKey))
                if frames.count > 1 {
                    let sizes = Set(members.filter { !$0.isFullscreen }.map { Self.sizeOnly($0) })
                    XCTAssertEqual(sizes.count, 1,
                        "\(name): geometry grouped \(group.siblingWids) across SIZES \(sizes.sorted())")
                    let declared = members.first { $0.wid == group.visibleWid }?.tabCount ?? 0
                    XCTAssertEqual(members.count, declared,
                        "\(name): geometry grouped \(group.siblingWids) across frames \(frames.sorted()) "
                            + "without AX accounting for every member (tabCount \(declared))")
                }
            }
        }
    }

    /// The same invariant on the OTHER claim path. Fixing one and not the other is what cost this corpus four
    /// rounds of the same bug in different clothes.
    func testNoTitleMatchEverClaimsAcrossFrames() {
        for (name, windows) in Self.frameCorpus {
            for active in windows where !active.isFullscreen {
                guard let titles = Self.axTitles(for: active.wid) else { continue }
                let m = TabGroupResolver.matchSiblings(active: active, axTitles: titles, sameAppWindows: windows)
                for claimed in m.matchedWids.compactMap({ wid in windows.first { $0.wid == wid } })
                where !claimed.isFullscreen {
                    XCTAssertEqual(Self.frameKey(claimed), Self.frameKey(active),
                        "\(name): #\(active.wid) claimed #\(claimed.wid) at a different frame")
                }
            }
        }
    }

    private static func frameKey(_ w: TabWindow) -> String {
        let s = w.size ?? .zero, p = w.position ?? .zero
        return "\(Int(s.width))x\(Int(s.height))@\(Int(p.x)),\(Int(p.y))"
    }

    private static func sizeOnly(_ w: TabWindow) -> String {
        let s = w.size ?? .zero
        return "\(Int(s.width))x\(Int(s.height))"
    }

    /// The recorded AXTabGroup titles for a capture, if it had any.
    private static func axTitles(for wid: CGWindowID) -> [String]? {
        ([finderDuplicateTabTitlesActiveA, finderDuplicateTabTitlesActiveB, finderSelfOnlyLinkNewTabGapBackgrounding,
          finderTwoCascadedWindowsActiveA, finderTabSwitchIncomingSettled, finderOtherWindowActiveAfterFullscreen]
            + terminalMerge4Tabs + twoGroupsSameApp)
            .first { $0.wid == wid }?.axTabTitles
    }

    /// rec13, 21:06:15.4 — the TAB-SWITCH handover, which no claim path covers: clicking window C's "Movies"
    /// tab showed C as TWO tiles for ~9s (3 tiles for 2 windows).
    ///
    ///     21:06:15.406 added tracked#75468 space=3628 isTabbed=false sp[]   ← Movies tab becomes active
    ///     21:06:15.457 updateState active#75468 titles=["lwouis","Movies", …]
    ///     21:06:15.62  tiles … +3:Finder#75825@286,400 … +18:Finder#75468@286,400   ← both of C shown
    ///
    /// Why both claim paths miss it:
    /// - GEOMETRY needs a Space-less member to call something a background tab; on a switch the OUTGOING tab
    ///   keeps its Space until its 1326 lands (~5s here), so both hold `sp[3628]` and `background` is empty.
    ///   (rec13 logged ZERO `geometryGroup` lines all session.)
    /// - TITLES won't claim an on-screen sibling unless the active is a brand-new window
    ///   (`activeIsNewlyDiscovered`), and a switch targets an ALREADY-TRACKED tab, so that pass never runs.
    /// Note the incoming tab's own position is STALE at claim time — 75468 still read (133,89), its
    /// pre-switch frame, and only became (286,400) ~215ms later, AFTER `updateState` had already run. So a
    /// frame test at that instant compares a stale position against a live one. Any fix must handle that.
    static let finderTabSwitchIncomingStale = CapturedWindow(pid: 779, wid: 75468, title: "Movies",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 133, y: 89),
        spaceIds: [3628], axTabTitles: ["lwouis", "Movies", "lwouis", "lwouis"])
    /// Same tab 215ms later, once its frame caught up to its parent's.
    static let finderTabSwitchIncomingSettled = CapturedWindow(pid: 779, wid: 75468, title: "Movies",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 286, y: 400),
        spaceIds: [3628], axTabTitles: ["lwouis", "Movies", "lwouis", "lwouis"])
    /// C's outgoing active: on-screen, STILL holding the Space (its 1326 hasn't landed), not yet re-tabbed.
    static let finderTabSwitchOutgoing = CapturedWindow(pid: 779, wid: 75825, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 286, y: 400),
        spaceIds: [3628])

    /// rec8, 18:01:21.698 — the FIRST theft of that session, one minute before the rec10 shape and the seed of
    /// the rest. Window 74626 is a real Finder window whose AXTabGroup reads ["lwouis", "Downloads"], but its
    /// "Downloads" tab isn't tracked yet (`untracked=["Downloads"]`, discovery in flight) — so it was linked to
    /// only ITSELF. The user then opened a new tab in it: `removed tracked#74626 space=3628` made it Space-less
    /// for ~800ms until the new tab 74628 was discovered (`discovered new#74628 ... matched=[74626]`, 18:01:22.533).
    /// In that gap geometry clustered it with the unrelated 74625 (Finder, same default 920×436, its own frame)
    /// and made 74625 its parent: `geometryGroup visible#74625 sp[3628] background=[74626]`.
    static let finderSelfOnlyLinkNewTabGapVisible = CapturedWindow(pid: 779, wid: 74625, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 947, y: 514),
        spaceIds: [3628])
    static let finderSelfOnlyLinkNewTabGapBackgrounding = CapturedWindow(pid: 779, wid: 74626, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 191, y: 147),
        spaceIds: [], axTabTitles: ["lwouis", "Downloads"])

    /// rec11, 19:29:53 — TWO fullscreen Finder windows, tabs burst into both, and the switcher showed ONE tile.
    /// The windows sit at (162,118) and (133,89): 29px apart, the macOS window-CASCADE offset, and both at the
    /// default 920×436. Every tab of both is titled "lwouis" (Finder names tabs after the folder), so titles
    /// cannot tell the two apart, and `positionsCompatible`'s 50px tolerance waved the 29px gap through — so
    /// window A's active tab claimed window B's tabs and B lost every member:
    ///
    ///     updateState active#75633 titles=["lwouis" ×11] matched=[75617, 75607, …]
    ///     siblings=[75642, 75633, 75626, 75620, 75617, 75607, 75605, 75492, 75489, 75446]  ← both windows
    ///
    /// Note the AX title COUNT (11, and 5/10/16/17/19/22 elsewhere in the same burst) exceeds the tracked
    /// windows: Finder destroys a backgrounded tab's window, so titles routinely outnumber wids and the count
    /// bounds nothing. Position is the only fact that separates these two windows.
    static let finderTwoCascadedWindowsTabsA: [CapturedWindow] = [75633, 75626, 75620].map {
        CapturedWindow(pid: 779, wid: $0, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118), spaceIds: [])
    }
    static let finderTwoCascadedWindowsTabsB: [CapturedWindow] = [75617, 75607, 75605, 75492].map {
        CapturedWindow(pid: 779, wid: $0, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 133, y: 89), spaceIds: [])
    }
    /// A's active tab, on-screen at A's frame, reporting 11 same-titled tabs.
    static let finderTwoCascadedWindowsActiveA = CapturedWindow(pid: 779, wid: 75642, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118),
        spaceIds: [3628], axTabTitles: Array(repeating: "lwouis", count: 11))

    /// rec14 (2026-07-16, `--tab-diag`, the "Terminal same-frame burst" recording): 3 SEPARATE Terminal
    /// windows all stacked at ONE position (Terminal doesn't cascade), tabs burst into one of them, then the
    /// user switched to a burst tab. At 09:21:07 the switcher showed a 4th Terminal tile for ~200ms:
    ///
    ///     09:21:07.439 removed tracked#77468 → hold-visible #77468        ← outgoing active backgrounds
    ///     (normalize borrows a Space back onto it so its tile can't vanish → sp[3628] again)
    ///     09:21:07.452 updateState active#77467 titles=["~"×6] matched=[77438]   ← 77468 NOT claimed
    ///     09:21:07.452 group dissolve g3                                   ← its group lost its other member
    ///     09:21:07.483 tiles … +0:#77467 … +1:#77468(h) … -2:#77438(t)     ← 4 shown Terminal tiles
    ///
    /// The anti-vanish rule (borrow a Space onto the held rep) had poisoned the anti-void rule's evidence
    /// ("holds a Space ⇒ on-screen ⇒ never claim"), so the incoming tab could not claim the outgoing one and
    /// it stood as a ghost standalone until a later re-read. GROUND TRUTH: a HELD window is by definition a
    /// backgrounding tab mid-swap — the claim must accept it regardless of the borrowed Space, and the two
    /// SEPARATE windows (4px taller: no tab bar was ever added to them — 1027×1107 vs the group's 1027×1103)
    /// must stay unclaimed even though they share the position and the "~" title.
    static let terminalSameFrameBurstIncoming = CapturedWindow(pid: 93001, wid: 77467, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 1027, height: 1103), position: CGPoint(x: 0, y: 31),
        spaceIds: [3628], axTabTitles: ["~", "~", "~", "~", "~", "~"])
    /// The outgoing active: held, its group just dissolved, carrying the Space normalize borrowed back.
    static let terminalSameFrameBurstHeldOutgoing = CapturedWindow(pid: 93001, wid: 77468, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 1027, height: 1103), position: CGPoint(x: 0, y: 31),
        spaceIds: [3628])
    /// A settled background tab of the same group (Space backfilled by updateState).
    static let terminalSameFrameBurstSettledTab = CapturedWindow(pid: 93001, wid: 77438, title: "~",
        subrole: "AXStandardWindow", size: CGSize(width: 1027, height: 1103), position: CGPoint(x: 0, y: 31),
        spaceIds: [3628])
    /// The two genuinely SEPARATE windows, at the same stacked position but 4px taller (no tab bar).
    static let terminalSameFrameBurstSeparateWindows: [CapturedWindow] = [77435, 77431].map {
        CapturedWindow(pid: 93001, wid: $0, title: "~", subrole: "AXStandardWindow",
            size: CGSize(width: 1027, height: 1107), position: CGPoint(x: 0, y: 31), spaceIds: [3628])
    }

    func testHeldOutgoingTabIsClaimableDespiteItsBorrowedSpace() {
        // The rec14 ghost tile: the incoming tab's claim must take the HELD outgoing tab even though it
        // holds a (borrowed) Space — and must still leave the two separate same-position windows alone.
        var held = Self.terminalSameFrameBurstHeldOutgoing.tabWindow()
        held.isHeld = true
        let active = Self.terminalSameFrameBurstIncoming.tabWindow(tabbedSiblingWids: [77467, 77438])
        let tab = Self.terminalSameFrameBurstSettledTab.tabWindow(isTabbed: true, tabbedSiblingWids: [77467, 77438])
        let separate = Self.terminalSameFrameBurstSeparateWindows.map { $0.tabWindow() }
        let m = TabGroupResolver.matchSiblings(active: active,
            axTitles: Self.terminalSameFrameBurstIncoming.axTabTitles!,
            sameAppWindows: [active, held, tab] + separate)
        XCTAssertTrue(m.matchedWids.contains(77468), "the held outgoing tab must be claimed — its Space is ours, borrowed")
        XCTAssertTrue(m.matchedWids.contains(77438))
        XCTAssertFalse(m.matchedWids.contains(77435), "a real separate window is never claimed")
        XCTAssertFalse(m.matchedWids.contains(77431), "a real separate window is never claimed")
    }

    func testUnheldOnScreenWindowStillProtectedInTheSameShape() {
        // The same facts WITHOUT the hold: the on-screen protection must still reject the claim — the hold
        // is the only thing distinguishing a backgrounding tab from a real same-title same-frame window here.
        let notHeld = Self.terminalSameFrameBurstHeldOutgoing.tabWindow()
        let active = Self.terminalSameFrameBurstIncoming.tabWindow(tabbedSiblingWids: [77467, 77438])
        let tab = Self.terminalSameFrameBurstSettledTab.tabWindow(isTabbed: true, tabbedSiblingWids: [77467, 77438])
        let m = TabGroupResolver.matchSiblings(active: active,
            axTitles: Self.terminalSameFrameBurstIncoming.axTabTitles!,
            sameAppWindows: [active, notHeld, tab])
        XCTAssertFalse(m.matchedWids.contains(77468))
    }

    /// rec18 (2026-07-16, `--tab-diag --logs=debug`): rapid tab switching inside a Finder window. AX reads are
    /// QUEUED, so window 78103's titles read landed 6ms before the user's switch-back events, while 78111 —
    /// the tab the user was actually on — was the group's representative:
    ///
    ///     11:25:21.992 updateState active#78103 titles=[…×30] matched=[75937, …] untab=[78111]   ← ejects it
    ///     11:25:21.992 group dissolve g5 / group form g6 rep=#78103                              ← reader wins
    ///     11:25:21.998 added tracked#78103 / removed tracked#78111                               ← real events
    ///
    /// The ejected real active stood as a stray visible tile, and under continued switching every queued read
    /// re-formed the group around whichever member got read — ending in 2 shown tiles for ONE window that
    /// never healed. GROUND TRUTH: focus is authoritative for which member is the group's active tab; a read
    /// that lands from a LESS recently focused member is stale and must neither eject nor displace the
    /// fresher one. All at the window's frame (162,118); focus orders from the recorded MRU bumps.
    static let finderStaleReadReader = CapturedWindow(pid: 5050, wid: 78103, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118),
        spaceIds: [3628], axTabTitles: Array(repeating: "lwouis", count: 16) + ["Movies"] + Array(repeating: "lwouis", count: 13))
    static let finderStaleReadCurrentActive = CapturedWindow(pid: 5050, wid: 78111, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118),
        spaceIds: [3628])
    static let finderStaleReadSettledTabs: [CapturedWindow] = [75937, 75620].map {
        CapturedWindow(pid: 5050, wid: $0, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118), spaceIds: [3628])
    }

    func testStaleReadNeitherEjectsNorDisplacesTheFocusedMember() {
        // The rec18 death spiral, both halves. The group as it stood: 78111 the on-screen representative
        // (focus order 0), the reader 78103 a tabbed member (focus order 1), settled tabs behind them.
        let group: [CGWindowID] = [78111, 78103, 75937, 75620]
        var reader = Self.finderStaleReadReader.tabWindow(isTabbed: true, tabbedSiblingWids: group)
        reader.lastFocusOrder = 1
        var current = Self.finderStaleReadCurrentActive.tabWindow(tabbedSiblingWids: group)
        current.lastFocusOrder = 0
        let tabs = Self.finderStaleReadSettledTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        // Half 1: the stale read KEEPS the more recently focused on-screen member — never `toUntab`s it.
        let m = TabGroupResolver.matchSiblings(active: reader, axTitles: Self.finderStaleReadReader.axTabTitles!,
            sameAppWindows: [reader, current] + tabs)
        XCTAssertTrue(m.matchedWids.contains(78111), "the group's real active must stay a member")
        XCTAssertFalse(m.toUntabWids.contains(78111), "ejecting the focused member is what stranded it visible")
        // Half 2: the representative pick follows FOCUS, not the reader.
        XCTAssertEqual(TabGroupResolver.groupRepresentative([reader, current] + tabs), 78111,
                       "the most recently focused on-screen member is the active tab, whoever got read")
    }

    /// rec20 (2026-07-16): Finder mints a NEW window id per tab switch and destroys the old one. When the
    /// tracked outgoing window died, the group's representative fell back to 75637 and normalize LENT it a
    /// Space so its tile wouldn't blank. The next incoming tab arrived as a brand-new wid (78461) — so no
    /// keep-rule could recognize 75637 (its membership can't contain a wid that didn't exist), and the claim
    /// rejected it as "un-tabbed and on a Space": it was orphaned by the exact-set re-form, KEEPING the Space
    /// we lent it, and stood as a permanent 4th tile:
    ///
    ///     13:49:47.921 group shrink g11 … rep=#75637 reason=windowRemoved   ← rep fallback + Space borrow
    ///     13:49:48.757 group form g12 rep=#78461 members=[78461, …]         ← 75637 NOT claimable ⇒ orphaned
    ///
    /// GROUND TRUTH: a borrowed Space is OUR annotation, not evidence — the claim must see it (like the
    /// hold), and the borrow must die with the membership that justified it.
    static let finderOrphanedExRepReader = CapturedWindow(pid: 5050, wid: 78461, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118),
        spaceIds: [3628], axTabTitles: Array(repeating: "lwouis", count: 16) + ["Movies"] + Array(repeating: "lwouis", count: 18))
    static let finderOrphanedExRep = CapturedWindow(pid: 5050, wid: 75637, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118),
        spaceIds: [3628])  // the BORROWED Space

    func testExRepresentativeWithABorrowedSpaceIsClaimable() {
        let group: [CGWindowID] = [75637, 75638, 75642]
        var exRep = Self.finderOrphanedExRep.tabWindow(tabbedSiblingWids: group)
        exRep.spaceIsBorrowed = true
        exRep.lastFocusOrder = 1
        let reader = Self.finderOrphanedExRepReader.tabWindow()
        let m = TabGroupResolver.matchSiblings(active: reader,
            axTitles: Self.finderOrphanedExRepReader.axTabTitles!, sameAppWindows: [reader, exRep])
        XCTAssertTrue(m.matchedWids.contains(75637),
                      "the Space we lent it must not make the ex-representative look like a separate window")
    }

    func testExRepresentativeWithAGenuineSpaceStaysProtected() {
        // The same shape with a GENUINE Space (borrow flag off): the on-screen protection must still hold —
        // that is a real separate window sharing a tab title (the void).
        let notBorrowed = Self.finderOrphanedExRep.tabWindow()
        let reader = Self.finderOrphanedExRepReader.tabWindow()
        let m = TabGroupResolver.matchSiblings(active: reader,
            axTitles: Self.finderOrphanedExRepReader.axTabTitles!, sameAppWindows: [reader, notBorrowed])
        XCTAssertFalse(m.matchedWids.contains(75637))
    }

    /// rec21 (2026-07-16): the user FULLSCREENED one of three Finder windows. Its background tabs stay frozen
    /// at the windowed frame (162,118, 920×436) and are NOT fullscreen per the OS — but the display mirror
    /// had stamped `isFullscreen` onto them, and feeding that synthetic flag to the kernel disabled both
    /// frame protections (geometry stopped splitting the 920×436 cluster; the title claim waived its
    /// exact-position test): one read merged 25 windows across three frames and hid a real window. The model
    /// now projects only GENUINE fullscreen into `TabWindow`; these captures are the RAW facts (frozen tabs
    /// not fullscreen), so the cross-frame invariants police the shape.
    static let finderFullscreenedWindowActive = CapturedWindow(pid: 5050, wid: 78459, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 2048, height: 1152), position: CGPoint(x: 0, y: 0),
        spaceIds: [4594], isFullscreen: true)
    static let finderFullscreenedWindowFrozenTabs: [CapturedWindow] = [75620, 75626].map {
        CapturedWindow(pid: 5050, wid: $0, title: "lwouis", subrole: "AXStandardWindow",
            size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118), spaceIds: [])
    }
    static let finderOtherWindowActiveAfterFullscreen = CapturedWindow(pid: 5050, wid: 75824, title: "lwouis",
        subrole: "AXStandardWindow", size: CGSize(width: 920, height: 436), position: CGPoint(x: 286, y: 400),
        spaceIds: [3628], axTabTitles: Array(repeating: "lwouis", count: 6))

    func testAnotherWindowNeverClaimsAFullscreenedGroupsFrozenTabs() {
        // Window B's read must not claim window A's frozen tabs: they sit at A's frame, and with only
        // GENUINE fullscreen in the record the exact-position test protects them (the mirrored flag used to
        // waive it — the rec21 mega-merge).
        let active = Self.finderOtherWindowActiveAfterFullscreen.tabWindow()
        let frozen = Self.finderFullscreenedWindowFrozenTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: [78459, 75620, 75626]) }
        let m = TabGroupResolver.matchSiblings(active: active,
            axTitles: Self.finderOtherWindowActiveAfterFullscreen.axTabTitles!,
            sameAppWindows: [active] + frozen)
        XCTAssertFalse(m.matchedWids.contains(75620))
        XCTAssertFalse(m.matchedWids.contains(75626))
    }

    // MARK: - Race interleavings
    //
    // Opening a tab fires events whose order is only PARTIALLY guaranteed, so a single capture is one sample
    // of several possible worlds. Rather than trust whichever order we happened to record, we unroll them:
    //
    //   guaranteed:     windowCreated(new) → discovered(new)      (can't discover before it exists)
    //   guaranteed:     windowCreated(new) → removedFromSpace(old) (the new tab is what backgrounds the old)
    //   NOT guaranteed: removedFromSpace(old)  vs  discovered(new)  ← the race
    //
    // The un-guaranteed pair is the only free variable, so there are exactly two worlds, and each is just a
    // different INPUT STATE to the same kernel — expressible as data:
    //   R→C  the old active is already Space-less when the new tab is discovered
    //   C→R  the old active still holds its (now stale) Space when the new tab is discovered
    // Both must resolve to ONE tile. Recording only ever caught one side at a time; these pin both.

    /// The old active as it looks in the R→C world: its 1326 landed first, so it is Space-less.
    /// Same window as `terminalNewTabStaleOldActive` (the C→R world), only its Space differs.
    static var terminalNewTabBackgroundedOldActive: CapturedWindow {
        var w = terminalNewTabStaleOldActive
        w.spaceIds = []
        return w
    }

    /// The fullscreen old active in the R→C world: Space-less rather than still holding the fullscreen Space.
    static var fullscreenTerminalBackgroundedOldActive: CapturedWindow {
        var w = fullscreenTerminalOldActive
        w.spaceIds = []
        return w
    }

    func testNewTabRaceBothInterleavingsGroupTheOldActive() {
        // The non-fullscreen creation race, both worlds. Whichever lands first, the old active must end up
        // claimed into the new tab's group — never left as a 2nd tile.
        let group: [CGWindowID] = [67088, 67081, 67075]
        let active = Self.terminalNewTabActive.tabWindow()
        let titles = Self.terminalNewTabActive.axTabTitles!
        let settled = Self.terminalNewTabSettledTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        for (world, oldActive) in [("C→R: old still holds its stale Space", Self.terminalNewTabStaleOldActive),
                                   ("R→C: old already Space-less", Self.terminalNewTabBackgroundedOldActive)] {
            let m = TabGroupResolver.matchSiblings(active: active, axTitles: titles,
                sameAppWindows: [active, oldActive.tabWindow()] + settled, activeIsNewlyDiscovered: true)
            XCTAssertTrue(m.matchedWids.contains(67085), "\(world): the old active must be claimed")
            XCTAssertEqual(m.untrackedTitles, [], "\(world): every tab accounted for")
        }
    }

    func testFullscreenNewTabRaceBothInterleavingsGroupTheOldActive() {
        // The fullscreen creation race, both worlds. AX gives no titles here, so geometry alone must land a
        // single group either way: via the same-Space fold (C→R) or via the Space-less background (R→C).
        let group: [CGWindowID] = [70291, 70288, 70220]
        let newTab = Self.fullscreenTerminalNewTab.tabWindow()
        let settled = Self.fullscreenTerminalSettledTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        for (world, oldActive) in [("C→R: old still holds the fullscreen Space", Self.fullscreenTerminalOldActive),
                                   ("R→C: old already Space-less", Self.fullscreenTerminalBackgroundedOldActive)] {
            let groups = TabGroupResolver.geometryGroups(
                [newTab, oldActive.tabWindow(tabbedSiblingWids: group)] + settled)
            XCTAssertEqual(groups.count, 1, "\(world): exactly one group")
            XCTAssertEqual(groups.first?.visibleWid, 70294, "\(world): the new tab is the visible")
            XCTAssertTrue(groups.first?.backgroundWids.contains(70291) ?? false,
                "\(world): the old active must be background, not a 2nd tile")
        }
    }

    // MARK: - The new-tab creation race (non-fullscreen)

    /// The title half of the rec10 capture: the SEPARATE Finder window (74625, its own frame at 523,501)
    /// merely shares the title "lwouis" with tabs of another window's group, and must never be claimed.
    /// `matchSiblings` was always CORRECT here — the theft came from geometry, see the test below.
    func testSeparateWindowSharingATabTitleIsNeverClaimed() {
        let tabsOfB = Self.finderDuplicateTabTitlesTabsOfB.map { $0.tabWindow() }
        let standalone = Self.finderDuplicateTabTitlesStandalone.tabWindow()
        let activeB = Self.finderDuplicateTabTitlesActiveB.tabWindow()
        let m = TabGroupResolver.matchSiblings(active: activeB,
            axTitles: Self.finderDuplicateTabTitlesActiveB.axTabTitles!,
            sameAppWindows: [activeB, standalone] + tabsOfB)
        XCTAssertFalse(m.matchedWids.contains(74625),
                       "74625 is its own window at its own frame — sharing a tab title must not claim it")
    }

    /// The rec10 bug itself, transcribed from the instant it happened (18:26:35.633): the user switched tabs
    /// INSIDE Finder window B, so B's incoming tab 74820 was added to Space 3628 and its outgoing active
    /// 74628 was removed from it. For that beat 74628 is Space-less and not yet re-tabbed — and every Finder
    /// window shares the default 920×436, so it lands in the same size-cluster as the SEPARATE window 74625.
    /// Geometry then made 74625 the visible and annexed 74628 as its background tab:
    ///
    ///     geometryGroup visible#74625 sp[3628] background=[74628]
    ///
    /// which hid a real window, so `secondVisibleIndex` legitimately landed on Chrome. 74625 is nobody's tab:
    /// it sits at its own frame (523,501) and B's group already lists 74628 among its own members. A tab
    /// backgrounding inside one window must not be adoptable by another window that merely shares its size.
    func testTabSwitchInOneWindowIsNotAnnexedByAnotherSameSizeWindow() {
        let standalone = Self.finderDuplicateTabTitlesStandalone.tabWindow()
        let linksOfB: [CGWindowID] = [74628, 74626, 74820]
        // B's outgoing active: 1326 landed (Space-less), its own AX re-read hasn't (still un-tabbed).
        let outgoing = Self.finderDuplicateTabTitlesTabsOfB[1].tabWindow(tabbedSiblingWids: linksOfB)
        // B's incoming active: holds the Space, still flagged tabbed until its AX read lands.
        var incoming = Self.finderDuplicateTabTitlesTabsOfB[0].tabWindow(isTabbed: true,
            tabbedSiblingWids: linksOfB)
        incoming.spaceIds = [3628]
        // B's remaining background tab, carrying the Space `updateState` backfilled onto it.
        var backgroundTab = Self.finderDuplicateTabTitlesActiveB.tabWindow(isTabbed: true,
            tabbedSiblingWids: linksOfB)
        backgroundTab.spaceIds = [3628]
        let groups = TabGroupResolver.geometryGroups([standalone, outgoing, incoming, backgroundTab])
        XCTAssertFalse(groups.contains { $0.siblingWids.contains(74625) },
                       "74625 is a separate window at its own frame — it must not be grouped at all")
        XCTAssertFalse(groups.contains { $0.visibleWid == 74625 && $0.backgroundWids.contains(74628) },
                       "74628 is window B's tab; a same-size unrelated window must not annex it")
    }

    /// rec8's first theft: a window linked only to ITSELF (its own tabs not yet tracked) confirms no cluster,
    /// so its Space-less beat during a new-tab must not let an unrelated same-size window adopt it. This is
    /// what seeded the whole rec8 cascade — once 74625 was wrongly tabbed, `matchSiblings` could claim it BY
    /// TITLE (the `isTabbed || spaceIds.isEmpty` predicate now passed) and `positionsCompatible`'s link bypass
    /// waved through frames 332px apart, so the bad link kept re-justifying itself.
    /// rec11: window A's active tab must claim ONLY the tabs at A's own frame. B's tabs sit 29px away (the
    /// cascade offset) with the same size and the same title, so nothing but position separates them — and
    /// claiming them hid window B entirely, leaving the user one tile for two windows.
    func testCascadedWindowTabsAreNotClaimedAcrossWindows() {
        let tabsA = Self.finderTwoCascadedWindowsTabsA.map { $0.tabWindow() }
        let tabsB = Self.finderTwoCascadedWindowsTabsB.map { $0.tabWindow() }
        let activeA = Self.finderTwoCascadedWindowsActiveA.tabWindow()
        let m = TabGroupResolver.matchSiblings(active: activeA,
            axTitles: Self.finderTwoCascadedWindowsActiveA.axTabTitles!,
            sameAppWindows: [activeA] + tabsA + tabsB)
        XCTAssertEqual(m.matchedWids.sorted(), [75620, 75626, 75633],
                       "A's active tab must claim its own 3 tabs at (162,118) and none of B's at (133,89)")
    }

    /// rec11, 19:29:53.696 — the burst's last tab, 75642, read back `0x0@0,0` (an AX read whose failure was
    /// reported as zeros; the OS also publishes a real new tab at 0×0 before sizing it ~640ms later). It was
    /// the un-tabbed Space-holder, so it became the group's tile — and 0×0 has no thumbnail, so the user got a
    /// single tile of empty pixels that stayed until the switcher was reopened. The group must fall back to the
    /// outgoing tab, which is still sized and captured: the tile stays put rather than blinking to nothing.
    func testGroupIsNotRepresentedByAnUnrenderableIncomingTab() {
        var incoming = Self.finderTwoCascadedWindowsActiveA.tabWindow(tabbedSiblingWids: [75642, 75633, 75626])
        incoming.size = CGSize(width: 0, height: 0)
        incoming.position = .zero
        // MRU: 0 = most recent. The new tab was just focused, the tab it displaced is next, then the rest.
        incoming.lastFocusOrder = 0
        var outgoing = Self.finderTwoCascadedWindowsTabsA[0].tabWindow(isTabbed: true,
            tabbedSiblingWids: [75642, 75633, 75626])
        outgoing.lastFocusOrder = 1
        var other = Self.finderTwoCascadedWindowsTabsA[1].tabWindow(isTabbed: true,
            tabbedSiblingWids: [75642, 75633, 75626])
        other.lastFocusOrder = 2
        XCTAssertEqual(TabGroupResolver.groupRepresentative([incoming, outgoing, other]), 75633,
                       "a 0×0 tab can't be drawn — the group shows the outgoing tab until the new one is sized")
    }

    /// rec12, 20:21:27.462 — why window B's tile VANISHED for ~2s on every tab of a burst, then came back under
    /// a new wid. B's active tab (75617 @133,89) goes Space-less the instant the new tab is created; window A
    /// (75642 @162,118, 29px away, same default 920×436, already AX-linked so the confirmed-cluster gate is
    /// open) then annexed it, and 230ms later annexed every remaining tab of B:
    ///
    ///     geometryGroup visible#75642 sp[3628] background=[75617]
    ///     geometryGroup visible#75642 sp[3628] background=[75446, 75489, 75492, 75468, 75605, 75607]
    ///
    /// B had no member left to show. This is the same cascade collision as
    /// `testCascadedWindowTabsAreNotClaimedAcrossWindows`, reached through GEOMETRY instead of titles — fixing
    /// only the title path left this door wide open.
    func testGeometryDoesNotClusterCascadedWindowsOfTheSameApp() {
        let activeA = Self.finderTwoCascadedWindowsActiveA.tabWindow(
            tabbedSiblingWids: [75642, 75633, 75626, 75620])
        let tabsA = Self.finderTwoCascadedWindowsTabsA.map {
            $0.tabWindow(isTabbed: true, tabbedSiblingWids: [75642, 75633, 75626, 75620])
        }
        // B's active tab, the instant it went Space-less: same size, 29px away, not yet re-tabbed.
        var backgroundingB = Self.finderTwoCascadedWindowsTabsB[0].tabWindow()
        backgroundingB.lastFocusOrder = 1
        let groups = TabGroupResolver.geometryGroups([activeA] + tabsA + [backgroundingB])
        XCTAssertFalse(groups.contains { $0.siblingWids.contains(75617) },
                       "75617 belongs to window B at (133,89) — A at (162,118) must not annex it")
    }

    func testWindowLinkedOnlyToItselfConfirmsNoTabCluster() {
        let visible = Self.finderSelfOnlyLinkNewTabGapVisible.tabWindow()
        let backgrounding = Self.finderSelfOnlyLinkNewTabGapBackgrounding.tabWindow(tabbedSiblingWids: [74626])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, backgrounding]), [],
                       "74626's link names only itself — it confirms nothing about 74625")
    }

    func testWindowDiscoveredAtLaunchNeverClaimsAnotherRealWindow() {
        // THE VOID, captured: two separate Finder windows share the tab title "lwouis". At launch both are
        // merely newly TRACKED — nothing was created — so the on-screen claim must not fire and 73977 must
        // stay its own window. It getting tabbed here is what hid a real window and derailed the selection.
        let active = Self.finderTwoWindowsSharingATabTitleActive.tabWindow()
        let other = Self.finderTwoWindowsSharingATabTitleOther.tabWindow()
        let m = TabGroupResolver.matchSiblings(active: active,
            axTitles: Self.finderTwoWindowsSharingATabTitleActive.axTabTitles!,
            sameAppWindows: [active, other], activeIsNewlyDiscovered: false)
        XCTAssertEqual(m.matchedWids, [], "a separate on-screen window is never claimed at launch")
        XCTAssertEqual(m.untrackedTitles, ["lwouis"], "the real inactive tab has no window yet → discover it")
    }

    func testNewTabClaimsStaleOldActive() {
        // The captured race: the brand-new active tab must claim the previous active even though it still
        // holds its stale Space — same app, same size, same title — so the group is ONE tile from the first
        // render instead of flashing two.
        let group: [CGWindowID] = [67088, 67081, 67075]
        let active = Self.terminalNewTabActive.tabWindow()
        let stale = Self.terminalNewTabStaleOldActive.tabWindow()
        let settled = Self.terminalNewTabSettledTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: Self.terminalNewTabActive.axTabTitles!,
            sameAppWindows: [active, stale] + settled, activeIsNewlyDiscovered: true)
        XCTAssertTrue(m.matchedWids.contains(67085), "the not-yet-backgrounded old active must be claimed")
        XCTAssertEqual(Set(m.matchedWids), [67085, 67081, 67075])
        XCTAssertEqual(m.untrackedTitles, [], "all 4 tabs are accounted for, nothing to brute-force")
    }

    func testStaleOldActiveNotClaimedOnAPlainReview() {
        // The same facts on a REVIEW (not a fresh discovery) must NOT claim the on-screen window — that path
        // can't tell it from a genuine new same-title window (the Finder cmd-N guard).
        let group: [CGWindowID] = [67088, 67081, 67075]
        let active = Self.terminalNewTabActive.tabWindow()
        let stale = Self.terminalNewTabStaleOldActive.tabWindow()
        let settled = Self.terminalNewTabSettledTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: Self.terminalNewTabActive.axTabTitles!,
            sameAppWindows: [active, stale] + settled)
        XCTAssertFalse(m.matchedWids.contains(67085))
    }

    // MARK: - A transient nil AXTabGroup must not dissolve a live group

    func testDissolvedGroupCannotBeRebuiltByMatching() {
        // Captured aftermath of a wrongful dissolution: the orphans hold their STALE Space and are no longer
        // `isTabbed`, so the matcher can claim NONE of them — matched=[] and every title reported untracked,
        // exactly as recorded. Un-tabbing is effectively irreversible from these facts, which is why a nil
        // AXTabGroup read must never dissolve a live group (the group only came back on a later AX review).
        let active = Self.terminalAfterDissolutionActive.tabWindow()
        let orphans = Self.terminalAfterDissolutionOrphans.map { $0.tabWindow() }  // un-tabbed, stale Space
        let m = TabGroupResolver.matchSiblings(active: active,
            axTitles: Self.terminalAfterDissolutionActive.axTabTitles!, sameAppWindows: [active] + orphans)
        XCTAssertEqual(m.matchedWids, [], "orphans are neither tabbed nor Space-less → unclaimable")
        XCTAssertEqual(m.untrackedTitles, ["~", "~", "~"])
    }

    func testLiveGroupSurvivesNilTitlesRead() {
        // The transient nil itself: the active reports no AXTabGroup while its background tab is still tabbed
        // into this group. `matchSiblings` isn't even reached (the adapter returns on nil titles), so the
        // invariant we can pin here is the complement — with titles present again, the still-tabbed sibling is
        // KEPT, never reported untracked. Together with the test above this is why nil ⇒ keep the group.
        let group: [CGWindowID] = [66886, 66881]
        let active = Self.terminalLiveGroupActive.tabWindow(tabbedSiblingWids: group)
        let tab = Self.terminalLiveGroupBackgroundTab.tabWindow(isTabbed: true, tabbedSiblingWids: group)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"], sameAppWindows: [active, tab])
        XCTAssertEqual(m.matchedWids, [66881])
        XCTAssertEqual(m.untrackedTitles, [])
    }

    // MARK: - #5785 composed window titles

    func testComposedWindowTitleMatchesNoSibling() {
        // The defect itself, reproduced from the capture: the AXTabGroup names three tabs and not one of
        // them can be matched to a window, because this app's window title is not its tab title. Reproduces
        // the logged `matched=[] untracked=[all three]` exactly. Note the active's OWN title isn't removed
        // from the list either, for the same reason.
        let active = Self.composedTitleActiveTab.tabWindow()
        let tab = Self.composedTitleBackgroundTab.tabWindow()
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: Self.composedTitleActiveTab.axTabTitles!,
            sameAppWindows: [active, tab])
        XCTAssertEqual(m.matchedWids, [], "no window title equals any tab title, so nothing can be named")
        XCTAssertEqual(m.untrackedTitles, ["~", "~/Downloads", "~/Documents"])
        XCTAssertEqual(m.toUntabWids, [], "and nothing may be un-tabbed on the strength of that silence")
    }

    func testComposedTitleGroupIsFormedByTheTabCount() {
        // The fix: the COUNT from that same unusable read confirms the geometry cluster, so the tabs are
        // grouped into one tile without any title comparison. `tabCount` is derived from `axTabTitles`, the
        // live relationship. Ground truth: 28963 and 28961 are the visible and background tabs of ONE window.
        let active = Self.composedTitleActiveTab.tabWindow()
        let tab = Self.composedTitleBackgroundTab.tabWindow()
        XCTAssertEqual(TabGroupResolver.geometryGroups([active, tab]),
            [GeometryGroup(visibleWid: 28963, backgroundWids: [28961])])
    }

    func testComposedTitleGroupStaysUnformedWithoutTheCount() {
        // The counterfactual that makes the test above meaningful: with no AXTabGroup read (`tabCount` 0)
        // these same two windows are the #5830 case — same app, same size, one briefly Space-less — and must
        // NOT be grouped. The count is doing the work, not the geometry.
        let active = Self.composedTitleActiveTab.tabWindow(tabCount: 0)
        let tab = Self.composedTitleBackgroundTab.tabWindow()
        XCTAssertEqual(TabGroupResolver.geometryGroups([active, tab]), [])
    }

    func testReporterComposedTitlesGroupByTheTabCount() {
        // The reporter's own numbers (#5785 logs) at 1017×610, each tab discovered as a separate window
        // ~250ms apart during a Cmd-T burst. `tabCount` is supplied by the test, NOT by the capture: their
        // AX tab titles were never recorded, so the only evidence these two wids are tabs of one window is
        // the Space-swap signature in their log (13612 out / 13885 in, same Space, same millisecond). That
        // is what an AX read of 2 tab buttons would have told us, so it is what the kernel is given.
        let active = Self.reporterComposedTitleActiveTab.tabWindow(tabCount: 2)
        let tab = Self.reporterComposedTitleBackgroundTab.tabWindow()
        XCTAssertEqual(TabGroupResolver.geometryGroups([active, tab]),
            [GeometryGroup(visibleWid: 13885, backgroundWids: [13612])])
    }

    // MARK: - Fullscreen tabs

    func testFullscreenNewTabGroupsWithOldActiveOnSameSpace() {
        // Captured fullscreen Cmd-T: AX gives no titles, the new tab's own fullscreen flag lags, and the old
        // active still holds the ONE fullscreen Space. Geometry must still produce a single group: the new tab
        // visible, the old active folded in as background (same fullscreen Space ⇒ same window's tabs) along
        // with the Space-less older tabs.
        let group: [CGWindowID] = [70291, 70288, 70220]
        let newTab = Self.fullscreenTerminalNewTab.tabWindow()
        let oldActive = Self.fullscreenTerminalOldActive.tabWindow(tabbedSiblingWids: group)
        let settled = Self.fullscreenTerminalSettledTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        let groups = TabGroupResolver.geometryGroups([newTab, oldActive] + settled)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.visibleWid, 70294, "the brand-new tab is the group's visible")
        XCTAssertEqual(Set(groups.first?.backgroundWids ?? []), [70291, 70288, 70220])
    }

    func testFullscreenTabSwitchEmitsNoAddForATrackedWindow() {
        // The recorded fullscreen switch: the events are an add for the (untracked) incoming tab and a remove
        // for the outgoing active — both Space-membership, no focus event. Pins that the incoming tab arrives
        // via discovery, so it must be fronted explicitly (nothing else will bump its MRU).
        for e in Self.fullscreenTabSwitchEvents {
            XCTAssertEqual(WsEventRouting.action(for: WsEventRouting.notification(e.id)!), .updateSpaceMembership)
        }
        XCTAssertEqual(Self.fullscreenTabSwitchEvents.filter { $0.id == 1325 }.map { $0.wid }, [70211, 70212])
        XCTAssertEqual(Self.fullscreenTabSwitchEvents.filter { $0.id == 1326 }.map { $0.wid }, [70217])
    }

    func testFullscreenAddTabShowsTheNewTabNotThePrevious() {
        // Captured live and currently FAILING behaviour is pinned here as ground truth: adding a tab to a
        // fullscreen Finder window must leave ONE tile showing the NEW tab. The recording had geometry choose
        // the held old tab as the visible (switcher showed the previous tab) and later flip — because the new
        // tab was momentarily Space-less while the old one had a borrowed Space.
        let group: [CGWindowID] = [72695, 72045, 72050]
        let newTab = Self.fullscreenFinderAddTabNewTab.tabWindow()
        let oldActive = Self.fullscreenFinderAddTabHeldOldActive.tabWindow(tabbedSiblingWids: group)
        let frozen = Self.fullscreenFinderAddTabFrozenSibling.tabWindow(isTabbed: true, tabbedSiblingWids: group)
        // `newlyDiscovered` is what the discovery pass passes: in fullscreen AX names nothing and the new tab
        // is momentarily Space-less, so this is the only fact that identifies which member just took over.
        let groups = TabGroupResolver.geometryGroups([newTab, oldActive, frozen], newlyDiscovered: 73147)
        XCTAssertEqual(groups.count, 1, "the new tab and the old active are one group")
        XCTAssertEqual(groups.first?.visibleWid, 73147, "the NEW tab must be the group's visible, not the old one")
        XCTAssertEqual(groups.first?.backgroundWids, [72050])
    }

    func testMidSpaceSwitchNeverFoldsTwoFullscreenWindows() {
        // Captured: mid-transition every member reports BOTH fullscreen Spaces, so no member's Space is
        // evidence. Nothing may be attributed — in particular the second fullscreen window must not be folded
        // into the first's group and hidden (which sent the default selection past both Finder tiles).
        let windows = Self.twoFullscreenFinderWindowsMidSpaceSwitch.enumerated().map { i, w in
            w.tabWindow(isTabbed: i != 0, tabbedSiblingWids: nil)
        }
        XCTAssertEqual(TabGroupResolver.geometryGroups(windows), [],
            "while every window reports two Spaces, nothing is attributable — form no group")
    }

    func testSpacesSettleThenTheTwoFullscreenWindowsResolveSeparately() {
        // The same windows 0.14s later, Spaces settled as recorded (73888 → 4305, 73977 → 4310): now each
        // Space resolves on its own, one tile per fullscreen window.
        let sz = CGSize(width: 2048, height: 1152), pos = CGPoint(x: 0, y: 0)
        let settled: [(CGWindowID, UInt64, Bool)] = [(73888, 4305, false), (73841, 4305, true),
                                                     (73977, 4310, false), (73940, 4305, true)]
        let windows = settled.map { wid, space, tabbed in
            CapturedWindow(pid: 779, wid: wid, title: "lwouis", subrole: "AXStandardWindow", size: sz,
                position: pos, spaceIds: [space], isFullscreen: true).tabWindow(isTabbed: tabbed)
        }
        let groups = TabGroupResolver.geometryGroups(windows)
        // Space 4305 is one window with two tabs ⇒ one group. Space 4310 is a lone window with no tabs ⇒ no
        // group at all (a group needs 2+ members) — it simply shows. What matters is that it is nobody's
        // background tab, which is exactly how it got hidden before.
        XCTAssertEqual(groups.map { $0.visibleWid }, [73888])
        XCTAssertEqual(groups.first?.backgroundWids.sorted(), [73841, 73940])
        XCTAssertFalse(groups.flatMap { $0.backgroundWids }.contains(73977),
            "the other fullscreen window is never folded in as a background tab")
    }

    func testTwoFullscreenWindowsEachResolveToOneTile() {
        // Captured: 2 fullscreen Finder windows + their tabs all share the screen size, so they form ONE size
        // cluster spanning 2 Spaces. Each Space is one window and its tabs, so this must yield TWO groups —
        // one per Space — not a single bailed-out cluster leaving a window's tabs as extra tiles.
        let windows = Self.twoFullscreenFinderWindowsWithTabs.enumerated().map { i, w in
            // as recorded: on each Space one tab is the visible, the other its background tab
            w.tabWindow(isTabbed: i == 1 || i == 3, tabbedSiblingWids: nil)
        }
        let groups = TabGroupResolver.geometryGroups(windows)
        XCTAssertEqual(groups.count, 2, "one group per fullscreen Space, not one cluster-wide verdict")
        XCTAssertEqual(groups.map { $0.visibleWid }, [72050, 73377])
        XCTAssertEqual(groups.map { $0.backgroundWids }, [[72045], [73381]])
    }

    func testHeldSpacelessVisibleNeverStrandsItsOwnTabs() {
        // Captured: the group's visible backgrounded (Space-less, held) while its tabs kept the backfilled
        // Space. Nothing has left this group — it's one fullscreen window's tabs. Judging "holds a Space the
        // visible doesn't" against a Space-LESS visible marked all of them departed, unlinked them, and the
        // switcher showed 3 tiles that never re-merged.
        let group: [CGWindowID] = [72050, 73147, 73201]
        let visible = Self.fullscreenFinderSwitchHeldVisible.tabWindow(tabbedSiblingWids: group)
        let tabs = Self.fullscreenFinderSwitchBackgroundTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        XCTAssertEqual(TabGroupResolver.membersThatLeftGroup(visible: visible, members: [visible] + tabs), [],
            "a Space-less visible can't prove anything left its group")
    }

    func testFullscreenDragOutExtractedWindowsAreUnlinked() {
        // Real capture: 3 SEPARATE fullscreen Finder windows on 3 different Spaces, each still carrying the
        // original group's stale `tabbedSiblingWids`. All three must show — so the two that hold their own
        // fullscreen Space are reported as having LEFT the group (unlink), leaving only the visible.
        let group = Self.fullscreenFinderDragOutStaleGroup
        let windows = Self.fullscreenFinderDragOutWindows.map { $0.tabWindow(tabbedSiblingWids: group) }
        let visible = windows[0]  // 72477, Space 4204
        XCTAssertEqual(TabGroupResolver.membersThatLeftGroup(visible: visible, members: windows), [72050, 72101])
    }

    func testForeignSpaceBackgroundTabsAreNotTreatedAsDeparted() {
        // Real capture: a NORMAL (non-fullscreen) Terminal group whose background tabs report a foreign Space
        // (4179) disjoint from the visible's (3628) — yet they ARE tabs. They must NOT be unlinked; doing so
        // exploded the group into one tile per tab until a second switcher show re-grouped them.
        let group: [CGWindowID] = [71126, 71681, 71677, 71669, 71194, 71667]
        let visible = Self.terminalVisibleWithForeignSpaceTabs.tabWindow(tabbedSiblingWids: group)
        let tabs = Self.terminalForeignSpaceBackgroundTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        XCTAssertEqual(TabGroupResolver.membersThatLeftGroup(visible: visible, members: [visible] + tabs), [])
    }

    func testFullscreenSpacelessBackgroundTabsAreNotDeparted() {
        // A real fullscreen group: the Space-less background tabs are exactly what a background tab looks
        // like, so they are never reported as departed (only a member holding its OWN fullscreen Space is).
        let group: [CGWindowID] = [30170, 30162, 30163, 30168]
        let visible = Self.terminalFullscreenActive.tabWindow(tabbedSiblingWids: group)
        let background = Self.terminalFullscreenBackgroundTabs.map { $0.tabWindow(isTabbed: true, tabbedSiblingWids: group) }
        XCTAssertEqual(TabGroupResolver.membersThatLeftGroup(visible: visible, members: [visible] + background), [])
    }

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
        // them a group of the remaining 3. Pinned against the registry, which owns this decision.
        var t = TabGroupsTable()
        _ = t.form(Self.dragOutPriorSiblings, representative: Self.dragOutLeavingWid, reason: "capture",
            repPicker: { r, _ in r.first })
        let m = t.remove(Self.dragOutLeavingWid, reason: "dragOut", repPicker: { r, _ in r.first })
        XCTAssertEqual(m.ungroupedWids, [Self.dragOutLeavingWid])
        XCTAssertEqual(t.siblingWids(of: 30236), [30236, 30231, 30230])
    }

    func testDragOutVerdictConfirmsTheRealDragOut() {
        // The recorded "Move Tab to New Window": the escaped tab settled at (14,130) at 757×527 while the
        // group's frame is (683,101) 757×543 — a different frame ⇒ it left the window. This is what expels a
        // dragged-out tab from its group now that a Space-join is treated as a tab switch by default.
        let joiner = Self.dragOutStandaloneWindow.tabWindow()
        let prevRep = Self.dragOutRemainingGroup[0].tabWindow()
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), true)
    }

    func testDragOutVerdictConfirmsTheRealTabSwitchAsASwitch() {
        // rec13's Finder tab switch, both windows at the window's frame (286,400): once the incoming tab's
        // frame settles it matches the outgoing active's ⇒ a switch, membership stays.
        let joiner = Self.finderTabSwitchIncomingSettled.tabWindow()
        let prevRep = Self.finderTabSwitchOutgoing.tabWindow()
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), false)
    }

    func testDragOutVerdictUndecidedWhileTheIncomingFrameIsStale() {
        // The rec13 trap: the incoming tab's own position is STALE at claim time (its pre-switch frame,
        // 133,89) and settles ~215ms later. At that instant the verdict would wrongly read "different frame"
        // — the caller's re-check loop is what makes the stale reading harmless, so this pins the stale
        // reading AS the drag-out shape (same facts, different truth), documenting why the verdict must be
        // re-checked rather than trusted once.
        let staleJoiner = Self.finderTabSwitchIncomingStale.tabWindow()
        let prevRep = Self.finderTabSwitchOutgoing.tabWindow()
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: staleJoiner, previousRepresentative: prevRep), true,
                       "a stale frame reads as a drag-out — the 0.4s re-check delay exists to outlive ~215ms of staleness")
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
        XCTAssertTrue(PhantomWindowDetector.syncVerdict(Self.finderLwouisInactiveTab.windowState(isTabbed: false),
            app, isOrderedIn: false, alpha: 1))
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(Self.finderLwouisInactiveTab.windowState(isTabbed: true),
            app, isOrderedIn: false, alpha: 1))
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
    static func teWindow(_ wid: CGWindowID, _ title: String, _ pos: CGPoint, active: Bool,
                         axTabTitles: [String]? = nil) -> CapturedWindow {
        CapturedWindow(pid: realTextEditPid, wid: wid, title: title, subrole: "AXStandardWindow",
            size: CGSize(width: 574, height: 480), position: pos, spaceIds: active ? [1] : [],
            axTabTitles: axTabTitles)
    }
    static let twoGroupsSameApp: [CapturedWindow] = {
        let aPos = CGPoint(x: 0, y: 60), bPos = CGPoint(x: 474, y: 232)
        return [
            teWindow(30543, "Untitled 3", aPos, active: true,    // group A active
                     axTabTitles: ["Untitled", "Untitled 2", "Untitled 3"]),
            teWindow(30542, "Untitled 2", aPos, active: false),  // group A tab
            teWindow(30561, "Untitled 9", bPos, active: true,    // group B active
                     axTabTitles: ["Untitled 7", "Untitled 9"]),
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
