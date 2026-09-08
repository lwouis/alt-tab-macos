import CoreGraphics
import Foundation

/// One thing a user does. A `TestScenario` is a sequence of these; a test IS that sequence. Named to avoid
/// colliding with the app's trackpad "gestures".
enum TestUserAction: Equatable, CustomStringConvertible {
    case newWindow(pid: pid_t)
    case openTab(window: Int)                 // window: index into created order
    case switchTab(window: Int, tab: Int)
    case enterFullscreen(window: Int)
    case exitFullscreen(window: Int)
    case switchToSpace(window: Int)           // move to the Space `window` lives on (its own, if fullscreen)
    case minimize(window: Int)
    case restoreFromDock(window: Int)         // click its tile in the Dock
    case show                                 // summon the switcher (the app's pre-show reconcile)
    var description: String {
        switch self {
        case .newWindow(let p): return "newWindow(pid: \(p))"
        case .openTab(let w): return "openTab(window: \(w))"
        case .switchTab(let w, let t): return "switchTab(window: \(w), tab: \(t))"
        case .enterFullscreen(let w): return "enterFullscreen(window: \(w))"
        case .exitFullscreen(let w): return "exitFullscreen(window: \(w))"
        case .switchToSpace(let w): return "switchToSpace(window: \(w))"
        case .minimize(let w): return "minimize(window: \(w))"
        case .restoreFromDock(let w): return "restoreFromDock(window: \(w))"
        case .show: return "show"
        }
    }
}

/// THE model of OS behavior: `[TestUserAction ⇒ OS events]`. It holds GROUND TRUTH — which windows are real,
/// which are tabs of one window, which tab is active, each window's frame/Space/fullscreen — and for each
/// action emits the WindowServer/AX event sequence AltTab would observe, as `TestReducerRunner.Step`s. It
/// performs NOTHING itself: `TestScenarioSimulator` drives the steps through the reducer, which lets the
/// same action be replayed under different event ORDERINGS (the interleaving fuzz).
///
/// Faithfulness is grounded in the recordings (see `TestScenarioSimulatorSpecs.md`): a tabbed window shows
/// ONE tile; its active tab holds the window's Space, background tabs are Space-less; switching tabs MINTS
/// a fresh wid for the incoming tab and its prior wid LINGERS alive + AX-reachable (rec25 accumulation); a
/// fullscreen window's tabs share ONE fullscreen Space; a `show` runs the app's pre-show reconcile (discover
/// untracked actives, adopt inactive tabs, AX-title read for windowed groups, authoritative Space re-query,
/// phantom pass).
struct TestInteractionModel {
    /// One real top-level window. Stable `identity` across tab churn (its wids change; the window doesn't).
    struct RealWindow {
        var identity: Int
        var pid: pid_t
        var size: CGSize
        var position: CGPoint
        var isFullscreen: Bool
        var isMinimized: Bool = false
        /// The frame fullscreen replaced, restored on the way out. macOS puts the window back exactly where
        /// it was, which is what makes leaving fullscreen land it in its old size cluster again.
        var windowedSize: CGSize?
        var windowedPosition: CGPoint?
        var space: UInt64
        var tabs: [Tab]
        var activeTab: Int
        var activeWid: CGWindowID { tabs[activeTab].wid }
        /// PRIOR wids of tabs re-minted on activation, each keeping its tab's title and FROZEN frame — alive
        /// + AX-reachable, so they accumulate (rec25). See the spec.
        var staleWids: [Tab] = []
        var allWids: [CGWindowID] { tabs.map { $0.wid } + staleWids.map { $0.wid } }
        private func tab(_ wid: CGWindowID) -> Tab? {
            tabs.first { $0.wid == wid } ?? staleWids.first { $0.wid == wid }
        }
        func title(of wid: CGWindowID) -> String? { tab(wid)?.title }
        /// The frame a wid's window actually has. Only the ACTIVE tab wears the window's current frame; every
        /// other tab is FROZEN at the frame it had when it was last active — which is why fullscreening a
        /// tabbed window leaves its background tabs at the old windowed size (the premise of the fullscreen
        /// mirror, rec21). Modelling one shared frame instead made a fullscreen group span two frames.
        func frame(of wid: CGWindowID) -> (size: CGSize, position: CGPoint) {
            wid == activeWid ? (size, position) : (tab(wid).map { ($0.size, $0.position) } ?? (size, position))
        }
    }
    struct Tab {
        var title: String
        var wid: CGWindowID
        var tracked: Bool
        var size: CGSize
        var position: CGPoint
    }

    /// What one action produces: `ordered` steps happen synchronously in sequence (WS events, app/Space
    /// state); `readUnits` are the async read RESULTS (AX/CGS reads) that land afterwards and whose ORDER is
    /// free — the interleaving fuzz permutes them. Each unit is internally ordered (e.g. track then its
    /// discoveryLanded stay paired).
    struct ActionEvents {
        var ordered: [TestReducerRunner.Step] = []
        var readUnits: [[TestReducerRunner.Step]] = []
        /// A Space transition is still in flight for this window (by IDENTITY, not wid) and settles during
        /// the NEXT action — BOUNDED cross-action interleaving. Only for genuinely slow OS work: a transition
        /// takes ~500ms, so it straddles whatever the user does next (rec24c: the fullscreen window rejoined
        /// its Space after the show's title read had already landed). Deliberately one action deep —
        /// deferring everything is unfaithful (a discovery lands in ~ms) and produces false failures.
        ///
        /// The settle STEPS are built when it fires, not here, because the window's visible wid can change in
        /// between: open a tab mid-transition and the Space settles onto the NEW tab. Pre-building them
        /// re-added the tab that had since backgrounded, which left the group showing the previous tab
        /// (generator, seed 6 — a model bug, not an app one).
        var settlingWindow: Int?
    }

    /// Every window and tab of every app shares ONE title. Finder names each window after the folder it
    /// shows, so duplicate titles are the norm, not an edge case — and a title is what `matchSiblings` claims
    /// a tab by, so collisions are where a group steals a window (rec8/10/11/24c).
    let duplicateTitles: Bool

    /// Switching to a tab REUSES its existing window instead of minting a fresh wid. **This is the normal
    /// case and so the default**: rec26 drove eight windowed and fullscreen switches and every one announced
    /// itself as `added tracked#<wid> isTabbed=true` — the tab's own window rejoining the Space, already
    /// tracked and grouped, so the switch is a pure representative move. Setting this false models the RARER
    /// minted switch (rec24b's `added untracked#78695`, a brand-new wid with no create event), which happens
    /// when the tab's window no longer exists and which has to be discovered before the group recovers.
    let reusesTabWindows: Bool

    /// Creating the FIRST tab in a standalone window makes the OS grow that window by the height of the tab
    /// bar it just gained. The incoming tab is drawn at the grown frame; the outgoing one keeps the frame it
    /// had, because a background tab gets no geometry event to correct it. So for as long as the pair lives,
    /// **the two tabs of one window report DIFFERENT sizes** — and every clustering rule keys on size, so
    /// they land in different clusters and the window shows two tiles.
    ///
    /// Measured live on macOS 26 via `SLSWindowQueryWindows` (one Terminal window, then New Tab): the
    /// standalone was 757x547, and afterwards the active read 757x583 while the background read 757x543.
    /// The reporter's #5785 capture is the same shape at their size — 1017x610 against 1017x565, same
    /// position, same width, differing only by the tab bar. Every window in this model shared one size
    /// before this axis existed, which is exactly why a green generator sweep never found the bug.
    ///
    /// Off by default: it changes the geometry every existing scenario asserts on, and its own scenarios say
    /// when they want it.
    let tabBarResizesWindow: Bool

    /// The app composes its WINDOW title from more than its TAB title, so the two strings never match. Stock
    /// Terminal does exactly this: `"~/Documents — -zsh ▸ -zsh — 80×23"` as a window, `"~/Documents"` as a
    /// tab, because the window title has settings (dimensions, active process) the tab title has no
    /// counterpart for (#5785, dumped live on macOS 26). Every title-keyed decision then fails at once, which
    /// is not a degraded match but NO match: `matchSiblings` names nobody and the group must be found some
    /// other way.
    ///
    /// Distinct from `duplicateTitles`, which makes every title the SAME string — those still MATCH, so the
    /// title path still works. Nothing in this model could express titles that match NOTHING, which is why a
    /// green sweep coexisted with a live bug for a month.
    let composedWindowTitles: Bool

    /// The suffix a composed window title carries and its tab title does not.
    static let windowTitleSuffix = " — -zsh — 80×25"

    /// How much the window grows when its tab bar appears. The exact number is not load-bearing (the rules
    /// compare sizes for equality, never by how far apart they are), only that it is non-zero.
    static let tabBarHeight: CGFloat = 40

    init(duplicateTitles: Bool = false, reusesTabWindows: Bool = true, tabBarResizesWindow: Bool = false,
         composedWindowTitles: Bool = false) {
        self.duplicateTitles = duplicateTitles
        self.reusesTabWindows = reusesTabWindows
        self.tabBarResizesWindow = tabBarResizesWindow
        self.composedWindowTitles = composedWindowTitles
    }

    /// Can this window's tabs be read? Windowed: yes. FULLSCREEN: no — `AXUIElement.tabGroupInfo` reads
    /// direct children only, deliberately, so fullscreen grouping is geometry's job. See that method for why
    /// reading them unevenly (only the apps that list the group as a child) was tried and reverted.
    private func tabsReadable(_ w: RealWindow) -> Bool { !w.isFullscreen }

    /// The `AXTabGroup` element the OS hands out for this window's group. Modelled as the window's own
    /// identity because that is exactly what it is: one element per logical window, the same one from every
    /// tab of it, for as long as the group lives. nil under the same conditions the shell reads nil (no tab
    /// bar, or a fullscreen bar `tabGroupInfo` does not reach), so the model never hands the reducer an
    /// identity the real read could not have supplied.
    private func tabGroupToken(_ w: RealWindow) -> TabGroupToken? {
        w.tabs.count > 1 && tabsReadable(w) ? TabGroupToken(w.identity) : nil
    }

    private(set) var world = [RealWindow]()
    private var createdIdentities = [Int]()
    private var nextWid: CGWindowID = 1000
    private var nextIdentity = 1
    private var nextSpace: UInt64 = 100
    private var now: TimeInterval = 1.0
    let windowedSpace: UInt64 = 1
    private var currentVisibleSpace: UInt64 = 1

    private let sharedTitle = "lwouis"
    /// The window (by identity) whose Space transition is in flight. CGS does NOT list a transitioning
    /// window on its Space — that is WHY it reads as Space-less — so the authoritative re-query and the
    /// phantom pass must both omit it, or the model heals the transient it is supposed to expose.
    private var transitioningIdentities = Set<Int>()

    /// EVERY wid of the transitioning window. It is the WINDOW that is moving, so none of its wids is
    /// drawable meanwhile — including a tab opened mid-transition, and the tab that just backgrounded to make
    /// room for it. Exempting only the current active left the outgoing one looking wrongly hidden.
    var windowsInSpaceTransition: Set<CGWindowID> {
        Set(world.filter { transitioningIdentities.contains($0.identity) }.flatMap { $0.allWids })
    }

    /// Fire ONE pending transition's settle: the window rejoins its Space — as whichever tab is active NOW —
    /// and the transition ends. Called by the driver at the end of the straddled action, never earlier:
    /// ending it sooner would model a transition that finished before it finished, and the window would be
    /// expected to draw during the gap it is by definition absent from.
    mutating func spaceTransitionSettleSteps(for id: Int) -> [TestReducerRunner.Step] {
        guard let w = world.first(where: { $0.identity == id }) else { transitioningIdentities.remove(id); return [] }
        transitioningIdentities.remove(id)
        return [.input(.spaceMembershipChanged(wid: w.activeWid, spaceId: w.space, added: true,
                                               now: tick(), inSpaceTransition: false))]
    }

    /// Tabs that just backgrounded and so may be HELD visible through the incoming tab's discovery gap. The
    /// app schedules a `holdReleaseCheck` to end each hold once the replacement lands; without modelling that
    /// follow-up, every hold stayed armed for the rest of the scenario — and a held tab keeps a borrowed
    /// Space, which quietly made the authoritative Space re-query unable to wipe anything. That masked the
    /// entire rec24 class.
    private var pendingHoldReleaseWids = [CGWindowID]()

    /// A window that already existed when AltTab started. See `seed`.
    struct PreexistingWindow {
        var pid: pid_t
        var tabs: Int
        var isFullscreen: Bool
        /// Fullscreen only: are the background tabs frozen at the PRE-fullscreen windowed frame? A tab freezes
        /// at the frame it had when it was last active, so this asks what the user did after fullscreening.
        /// Switched tabs at least once (the default, `false`) ⇒ those tabs were active while fullscreen and
        /// wear the fullscreen frame. Fullscreened and never switched since (`true`) ⇒ they still wear the
        /// windowed frame, and are then in a different size cluster from their own active tab.
        var tabsFrozenAtWindowedFrame: Bool
        init(pid: pid_t, tabs: Int = 1, isFullscreen: Bool = false, tabsFrozenAtWindowedFrame: Bool = false) {
            self.pid = pid
            self.tabs = tabs
            self.isFullscreen = isFullscreen
            self.tabsFrozenAtWindowedFrame = tabsFrozenAtWindowedFrame
        }
    }

    /// Seed a world that AltTab NEVER SAW BEING BUILT — no create, no Space join, no focus, nothing. This is
    /// the cold start: AltTab launches (or is updated, or is installed mid-session) into a desktop that
    /// already has a Finder window with six tabs and a fullscreen Terminal.
    ///
    /// It is the initial condition every other scenario lacks, and it is the one that separates the two
    /// sources tab detection can draw on. Watching a window from birth gives you HISTORY — the create, the
    /// handover, the focus — and history is a derivative: it reports CHANGES in Space occupancy, so it can
    /// only ever tell you about groups that changed while you were watching. Everything here predates us, so
    /// the only facts available are the ones readable NOW: the AXTabGroup, and the frames. A scenario that
    /// starts empty cannot tell the two apart, because history covers everything.
    ///
    /// Faithfulness notes, each mirroring what the corresponding action emits:
    /// - every tab is UNTRACKED, so the first `show` discovers the actives and brute-force-adopts the
    ///   inactive ones — exactly the launch path (`Applications.manuallyRefreshAllWindows`);
    /// - the LAST tab is active, since that is where opening tabs leaves you;
    /// - a fullscreen window's background tabs stay FROZEN at the windowed frame (the model's established
    ///   claim, confirmed in `TestScenarioSimulatorSpecs.md`) — which is why a pre-existing fullscreen group
    ///   is the hard case: AX exposes no tab group for it, and its members aren't even in one size cluster;
    /// - the user is looking at the WINDOWED Space, as after a login. A test that wants to start inside a
    ///   fullscreen Space opens with `.switchToSpace(window:)`.
    mutating func seed(_ windows: [PreexistingWindow]) {
        for w in windows {
            let identity = nextIdentity; nextIdentity += 1
            let windowedSize = CGSize(width: 900, height: 600)
            let windowedPosition = CGPoint(x: 40 * createdIdentities.count, y: 30 * createdIdentities.count)
            let size = w.isFullscreen ? CGSize(width: 1440, height: 900) : windowedSize
            let position = w.isFullscreen ? .zero : windowedPosition
            let backgroundSize = w.tabsFrozenAtWindowedFrame ? windowedSize : size
            let backgroundPosition = w.tabsFrozenAtWindowedFrame ? windowedPosition : position
            var tabs = [Tab]()
            for t in 0..<max(1, w.tabs) {
                let wid = newWid()
                let title = duplicateTitles ? sharedTitle : (t == 0 ? "w\(identity)" : "t\(wid)")
                let active = t == max(1, w.tabs) - 1
                tabs.append(Tab(title: title, wid: wid, tracked: false,
                    size: active ? size : backgroundSize, position: active ? position : backgroundPosition))
            }
            var space = windowedSpace
            if w.isFullscreen { space = nextSpace; nextSpace += 1 }
            world.append(RealWindow(identity: identity, pid: w.pid, size: size, position: position,
                isFullscreen: w.isFullscreen, space: space, tabs: tabs, activeTab: tabs.count - 1))
            createdIdentities.append(identity)
        }
    }

    private mutating func tick() -> TimeInterval { now += 0.01; return now }
    private mutating func newWid() -> CGWindowID { defer { nextWid += 1 }; return nextWid }
    private func index(ofWindow i: Int) -> Int? {
        guard i >= 0, i < createdIdentities.count else { return nil }
        return world.firstIndex { $0.identity == createdIdentities[i] }
    }

    /// One window's WindowServer snapshot, as the batched query would report it.
    private func wsSnapshot(_ wi: Int, isMinimized: Bool) -> WsWindowSnapshot {
        let w = world[wi]
        return WsWindowSnapshot(wid: w.activeWid, position: w.position, size: w.size,
            isFullscreen: w.isFullscreen, isVisible: !isMinimized, isMinimized: isMinimized)
    }

    /// The app-activation steps every action fires (one app frontmost + active, others inactive).
    private func appSteps(_ pid: pid_t) -> [TestReducerRunner.Step] {
        var steps: [TestReducerRunner.Step] = [.setFrontmost(pid: pid), .setAppActive(pid: pid, isActive: true)]
        for other in Set(world.map { $0.pid }) where other != pid {
            steps.append(.setAppActive(pid: other, isActive: false))
        }
        return steps
    }

    // MARK: - the one entry point

    mutating func apply(_ action: TestUserAction) -> ActionEvents {
        // A beat between user actions. Events WITHIN an action are milliseconds apart; separate actions are
        // seconds apart, and the reducer's recency windows (`hadRecentWindowCreate`, 0.5s) are keyed off that
        // difference. Without the gap every scenario ran inside one creation window, so holds stayed armed
        // that real usage would have released — and a held window is exempted from claims, which silently
        // hid the very races these scenarios exist to catch.
        now += 1.0
        switch action {
        case .newWindow(let pid): return newWindow(pid: pid)
        case .openTab(let w): return openTab(window: w)
        case .switchTab(let w, let t): return switchTab(window: w, toIndex: t)
        case .enterFullscreen(let w): return enterFullscreen(window: w)
        case .exitFullscreen(let w): return exitFullscreen(window: w)
        case .switchToSpace(let w): return switchToSpace(window: w)
        case .minimize(let w): return minimize(window: w)
        case .restoreFromDock(let w): return restoreFromDock(window: w)
        case .show: return show()
        }
    }

    /// Minimizing emits ONE WindowServer event — an order-out — because the OS has no minimize notification.
    /// The window keeps its Space (a minimized window is still listed on the Space it belongs to; the
    /// reporter's capture shows `sp[1]` throughout), so what makes it minimized in the model is the AX read
    /// the order-out queues, landing as its own unit.
    private mutating func minimize(window: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window), !world[wi].isMinimized else { return ActionEvents() }
        world[wi].isMinimized = true
        let wid = world[wi].activeWid
        var e = ActionEvents()
        e.ordered = [.input(.windowOrderedOut(wid: wid, inSpaceTransition: false))]
        // The order-out's WindowServer query is what flags the window minimized. It is still a read UNIT —
        // it lands asynchronously and the fuzz may deliver it late — but unlike the AX read it replaced, it
        // cannot be held up by the app itself, which is the whole reason a summon could beat it.
        e.readUnits = [[.input(.windowServerStateRead([wsSnapshot(wi, isMinimized: true)]))]]
        return e
    }

    /// Restoring from the Dock, with the ONE property that makes it different from every other way back on
    /// screen, and the reason it had its own bug: **the AX read that follows answers STALE**. Measured live
    /// (macOS 26, 8/8, Finder and Chrome): the Dock press emits the order-in within ~30ms while the app keeps
    /// reporting `kAXMinimized = true` for ~530ms. So the read unit below carries `true` — about a window the
    /// WindowServer has already put back on screen — and any handling that simply believes it re-strands the
    /// window. Emitting `false` here instead would model the AX-driven restore (`AXUIElementSetAttributeValue`,
    /// ~35ms of lag), which is the path that kept every test green while the Dock one was broken.
    ///
    /// The restore also ACTIVATES the app. That is ambient state (`appSteps`), not an `appActivated` input:
    /// when the app was already frontmost — the reporter's case — macOS emits nothing else at all, and the
    /// order-in is the whole of what AltTab hears.
    private mutating func restoreFromDock(window: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window), world[wi].isMinimized else { return ActionEvents() }
        world[wi].isMinimized = false
        let wid = world[wi].activeWid
        var e = ActionEvents()
        e.ordered = appSteps(world[wi].pid)
            + [.input(.windowOrderedIn(wid: wid, now: tick(), inSpaceTransition: false))]
        // ...and the query that follows the order-in STILL SAYS MINIMIZED, because on this path the
        // WindowServer's own bit only clears when the Dock animation ends (~644ms, measured) — later than
        // the order-in that already put the window back on screen, and later even than AX. Modelled as the
        // stale `true` it is; anything that believes it re-strands the window.
        e.readUnits = [[.input(.windowServerStateRead([wsSnapshot(wi, isMinimized: true)]))]]
        return e
    }

    // MARK: - per-action event emission

    private mutating func newWindow(pid: pid_t) -> ActionEvents {
        let wid = newWid()
        let identity = nextIdentity; nextIdentity += 1
        let title = duplicateTitles ? sharedTitle : "w\(identity)"
        let size = CGSize(width: 900, height: 600)
        let position = CGPoint(x: 40 * createdIdentities.count, y: 30 * createdIdentities.count)
        world.append(RealWindow(identity: identity, pid: pid, size: size, position: position,
            isFullscreen: false, space: windowedSpace,
            tabs: [Tab(title: title, wid: wid, tracked: true, size: size, position: position)], activeTab: 0))
        createdIdentities.append(identity)
        var e = ActionEvents()
        // A new window opens on the WINDOWED Space, and macOS takes you there — so if you were inside a
        // fullscreen Space, you are not any more. Leaving `currentVisibleSpace` behind made every later
        // action on that window look like it happened on a Space the user wasn't viewing, which suppresses
        // the untracked-join signals (focus promotion, hold, group inheritance) that only arm on a VISIBLE
        // Space. That is a model artefact, and it produced app-looking failures (generator seed 15).
        if currentVisibleSpace != windowedSpace {
            currentVisibleSpace = windowedSpace
            e.ordered = [.setSpaces(visible: [windowedSpace], current: windowedSpace, index: (windowedSpace, 1))]
        }
        e.ordered += appSteps(pid) + [.input(.windowCreated(wid: wid, now: tick(), inSpaceTransition: false))]
        e.readUnits = [[.track(trackedWindow(identity: identity, wid: wid, spaceIds: [windowedSpace])),
                        .input(.discoveryLanded(wid: wid, accepted: true, newlyTracked: true,
                            adoptedAsInactiveTab: false, queriedSpaceIds: [windowedSpace], isOrderedIn: true,
                            tabTitles: nil, tabGroupToken: nil))]]
        e.ordered.append(.input(.windowFocused(wid: wid, now: tick())))
        return e
    }

    private mutating func openTab(window: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window) else { return ActionEvents() }
        let oldWid = world[wi].activeWid
        let space = world[wi].space
        let wid = newWid()
        let identity = world[wi].identity
        // The tab bar appears with the SECOND tab, growing the window. The existing tab keeps its own stored
        // frame (it is about to be background, and background tabs get no geometry event), so the pair now
        // disagrees on size — see `tabBarResizesWindow`.
        // NOT in fullscreen: that window is already screen-sized and cannot grow, so the tab bar takes its
        // room from the CONTENT instead. Growing it there is unfaithful, and the sweep said so immediately
        // (seed 9: a fullscreen window and its own new tab landed in different size clusters, so the
        // fullscreen fold never saw them together and the window showed two tiles).
        if tabBarResizesWindow && world[wi].tabs.count == 1 && !world[wi].isFullscreen {
            world[wi].size.height += Self.tabBarHeight
        }
        world[wi].tabs.append(Tab(title: duplicateTitles ? sharedTitle : "t\(wid)", wid: wid, tracked: true,
            size: world[wi].size, position: world[wi].position))
        world[wi].activeTab = world[wi].tabs.count - 1
        var e = ActionEvents()
        // The real order, from the #5785 capture: the new tab is CREATED, then JOINS the Space, and only
        // then does the tab it replaced LEAVE it. The join was missing here, and it is not decoration — it is
        // the half of the handover that names the successor, so without it nothing could pair the incoming
        // tab with the outgoing one and a scenario could never exercise that path.
        e.ordered = appSteps(world[wi].pid)
            + [.input(.windowCreated(wid: wid, now: tick(), inSpaceTransition: false)),
               .input(.spaceMembershipChanged(wid: wid, spaceId: space, added: true, now: tick(), inSpaceTransition: false)),
               // The outgoing tab goes OFF SCREEN before it leaves the Space. Measured on macOS 26 with a
               // per-window notification probe over a real tab group: `1325(incoming) → 816(outgoing) →
               // 1326(outgoing) → 815(incoming)` on a switch, and `811 → 816 → 816 → 1326 → 1326` on Merge
               // All Windows. The 816 was missing here, which made a modelled background tab look like it
               // was still drawn — the one fact that separates a tab from a real window we lost the Space of.
               .input(.windowOrderedOut(wid: oldWid, inSpaceTransition: false)),
               .input(.spaceMembershipChanged(wid: oldWid, spaceId: space, added: false, now: tick(), inSpaceTransition: false))]
        e.readUnits = [[.track(trackedWindow(identity: identity, wid: wid, spaceIds: [space])),
                        .input(.discoveryLanded(wid: wid, accepted: true, newlyTracked: true,
                            adoptedAsInactiveTab: false, queriedSpaceIds: [space],
                            isOrderedIn: true, tabTitles: world[wi].tabs.map { $0.title },
                            tabGroupToken: tabGroupToken(world[wi]))),
                        // the replacement landed, so the hold on the tab it displaced ends
                        .input(.holdReleaseCheck(wid: oldWid, attempt: 0))]]
        return e
    }

    private mutating func switchTab(window: Int, toIndex: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window),
              toIndex >= 0, toIndex < world[wi].tabs.count, toIndex != world[wi].activeTab else { return ActionEvents() }
        let space = world[wi].space
        let outgoingWid = world[wi].activeWid
        let incoming = world[wi].tabs[toIndex]
        let reuse = reusesTabWindows && incoming.tracked
        var staleLeavingSpace: CGWindowID?
        let incomingWid: CGWindowID
        if reuse {
            incomingWid = incoming.wid                  // the tab's own window rejoins the Space, still tracked
        } else {
            world[wi].staleWids.append(incoming)        // re-created; the old wid lingers alive, frame frozen
            // The replaced wid is no longer a visible window, so CGS stops listing it on the Space — rec26
            // probed exactly these accumulated wids and every one came back empty. Leaving it on the Space
            // let a pile of stale wids keep a GENUINE membership forever, form their own group, and stand as
            // a second tile for a window that has one (generator seed 106).
            staleLeavingSpace = incoming.wid
            incomingWid = newWid()
            world[wi].tabs[toIndex].wid = incomingWid
            world[wi].tabs[toIndex].tracked = false     // untracked until the next show discovers it
        }
        world[wi].tabs[toIndex].size = world[wi].size          // the incoming tab is drawn at the window's frame
        world[wi].tabs[toIndex].position = world[wi].position
        world[wi].activeTab = toIndex
        pendingHoldReleaseWids.append(outgoingWid)   // released once the incoming tab's discovery lands
        var e = ActionEvents()
        // the incoming joins the visible Space, the outgoing leaves. A MINTED incoming is untracked and gets
        // discovered at the next show (fullscreen has no readable AXTabGroup; windowed is re-read there); a
        // REUSED one is already tracked, so the switch is nothing but a representative move.
        e.ordered = appSteps(world[wi].pid)
            + (staleLeavingSpace.map {
                [TestReducerRunner.Step.input(.spaceMembershipChanged(wid: $0, spaceId: space, added: false,
                    now: tick(), inSpaceTransition: false))] } ?? [])
            + [.input(.spaceMembershipChanged(wid: incomingWid, spaceId: space, added: true, now: tick(), inSpaceTransition: false)),
               .input(.windowOrderedOut(wid: outgoingWid, inSpaceTransition: false)),   // see `openTab`
               .input(.spaceMembershipChanged(wid: outgoingWid, spaceId: space, added: false, now: tick(), inSpaceTransition: false))]
        if reuse {
            // the switch's frames are re-queried and the drag-out verdict fires (same frame ⇒ a tab switch)
            e.readUnits = [[.input(.dragOutCheck(wid: incomingWid, previousRepWid: outgoingWid, attempt: 0))]]
        }
        return e
    }

    private mutating func enterFullscreen(window: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window) else { return ActionEvents() }
        let space = nextSpace; nextSpace += 1
        world[wi].windowedSize = world[wi].size
        world[wi].windowedPosition = world[wi].position
        world[wi].isFullscreen = true
        world[wi].space = space
        world[wi].size = CGSize(width: 1440, height: 900)
        world[wi].position = .zero
        world[wi].tabs[world[wi].activeTab].size = world[wi].size
        world[wi].tabs[world[wi].activeTab].position = world[wi].position
        currentVisibleSpace = space
        let activeWid = world[wi].activeWid
        var e = ActionEvents()
        e.ordered = [.setSpaces(visible: [space], current: space, index: (space, 2))]
            + appSteps(world[wi].pid)
            + [.input(.windowServerStateRead([WsWindowSnapshot(wid: activeWid, position: .zero,
                   size: CGSize(width: 1440, height: 900), isFullscreen: true, isVisible: true)])),
               .input(.spaceMembershipChanged(wid: activeWid, spaceId: space, added: true, now: tick(), inSpaceTransition: false)),
               .input(.spaceMembershipChanged(wid: activeWid, spaceId: windowedSpace, added: false, now: tick(), inSpaceTransition: false))]
        return e
    }

    /// **Leaving fullscreen**, which is NOT the enter events played backwards. Measured live (2026-09-08,
    /// macOS 26, Chrome; the same shape twice in one session):
    ///
    ///     33.845  windowOrderedIn        the window is raised as the animation starts
    ///     33.845  1326 space=764         it drops its fullscreen Space — and is now Space-LESS
    ///     33.895  windowMovedOrResized   its frame is ALREADY back to the windowed one
    ///     33.896  windowOrderedOut       it goes off screen for the length of the animation
    ///     34.361  1325 space=1           ~516ms later it joins the windowed Space
    ///     34.396  spaceCurrentChanged    and only then does the Space itself flip
    ///
    /// Two properties matter and neither has an analogue in `enterFullscreen`. The window spends half a
    /// second Space-less, ordered out, wearing its WINDOWED frame — so it is back in the size cluster of
    /// every other window of its app while holding no Space to tell them apart. And the WindowServer
    /// snapshot that clears `isFullscreen` is a READ, landing whenever the query answers: until it does, the
    /// window is a fullscreen-flagged member of a windowed cluster, which is what waives tab grouping's
    /// confirmation gate.
    ///
    /// The rejoin is `settlingWindow` (it straddles the next action) for the same reason `switchToSpace`'s
    /// is: that gap is the whole point of modelling this at all.
    private mutating func exitFullscreen(window: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window), world[wi].isFullscreen else { return ActionEvents() }
        let fullscreenSpace = world[wi].space
        world[wi].isFullscreen = false
        world[wi].space = windowedSpace
        world[wi].size = world[wi].windowedSize ?? CGSize(width: 900, height: 600)
        world[wi].position = world[wi].windowedPosition ?? .zero
        world[wi].tabs[world[wi].activeTab].size = world[wi].size
        world[wi].tabs[world[wi].activeTab].position = world[wi].position
        currentVisibleSpace = windowedSpace
        transitioningIdentities.insert(world[wi].identity)
        let activeWid = world[wi].activeWid
        var e = ActionEvents()
        e.ordered = [.setSpaces(visible: [windowedSpace], current: windowedSpace, index: (windowedSpace, 1))]
            + appSteps(world[wi].pid)
            + [.input(.windowFocused(wid: activeWid, now: tick())),
               .input(.windowOrderedIn(wid: activeWid, now: tick(), inSpaceTransition: false)),
               .input(.spaceMembershipChanged(wid: activeWid, spaceId: fullscreenSpace, added: false,
                   now: tick(), inSpaceTransition: false)),
               .input(.windowMovedOrResized(wid: activeWid, inSpaceTransition: false)),
               .input(.windowOrderedOut(wid: activeWid, inSpaceTransition: false))]
        e.readUnits = [[.input(.windowServerStateRead([WsWindowSnapshot(wid: activeWid,
            position: world[wi].position, size: world[wi].size, isFullscreen: false, isVisible: true)]))]]
        e.settlingWindow = world[wi].identity
        return e
    }

    /// Move to the Space `window` lives on. The transition is NOISY and SLOW: the target's active wid drops
    /// its Space membership as the animation starts and only rejoins once it settles — so mid-transition the
    /// window is transiently Space-less, which reads exactly like a backgrounded tab. The rejoin is `deferred`
    /// (it lands during the NEXT action) because that straddle is the whole point: in rec24c a windowed
    /// group's title read landed inside the gap and annexed the Space-less FULLSCREEN window.
    private mutating func switchToSpace(window: Int) -> ActionEvents {
        guard let wi = index(ofWindow: window) else { return ActionEvents() }
        let space = world[wi].space
        let activeWid = world[wi].activeWid
        var e = ActionEvents()
        // Already on that Space? Then there is no transition at all — the OS emits no Space membership
        // churn, it just focuses the window. Emitting a transition anyway made every window look like it
        // briefly left the Space it was sitting on, which reads as a vanished tile (first thing the
        // generator flagged, and a model bug, not an app one).
        guard space != currentVisibleSpace else {
            e.ordered = appSteps(world[wi].pid) + [.input(.windowFocused(wid: activeWid, now: tick()))]
            return e
        }
        currentVisibleSpace = space
        // Only a FULLSCREEN target goes transiently Space-less. Its Space is a separate one being animated
        // forward, which is what rec24c captured. Switching back to the shared WINDOWED Space moves nothing:
        // those windows sit still and only the viewport changes. Emitting the transient for them said a live
        // window had left its Space, so it was hidden — the app doing exactly the right thing with a lie
        // (generator seeds 6/8/21/39).
        guard world[wi].isFullscreen else {
            e.ordered = [.setSpaces(visible: [space], current: space, index: (space, 1))]
                + appSteps(world[wi].pid) + [.input(.windowFocused(wid: activeWid, now: tick()))]
            return e
        }
        transitioningIdentities.insert(world[wi].identity)
        e.ordered = [.input(.spaceMembershipChanged(wid: activeWid, spaceId: space, added: false,
                now: tick(), inSpaceTransition: false)),
            .setSpaces(visible: [space], current: space, index: (space, world[wi].isFullscreen ? 2 : 1))]
            + appSteps(world[wi].pid)
        // moving to a Space FOCUSES the window there, which fronts it in the MRU-sorted list — and that
        // order is what decides which same-title candidate a claim reaches first (rec24c matched the
        // fullscreen window before the windowed group's own tab, which only happens when it sorts ahead).
        e.ordered.append(.input(.windowFocused(wid: activeWid, now: tick())))
        e.settlingWindow = world[wi].identity
        return e
    }

    /// The app's pre-show reconcile — emitted entirely as read UNITS, whose landing order is what the fuzz
    /// varies (a Space re-query landing before vs after a title read is the rec24c/rec24e class).
    private mutating func show() -> ActionEvents {
        var e = ActionEvents()
        // `Windows.sort()` runs before the tiles are built, so every read below lands against an MRU-ordered
        // list — which is the order the reducer's first-wins rules walk (rec26).
        e.ordered = [.sortByMru]
        // Which actives AltTab knows about is snapshotted HERE, before any of this show's discoveries land:
        // every read below is ISSUED now and lands later, in whatever order. Reading tracked-ness as the
        // event list is built instead let the Space re-query name a wid the show itself was still
        // discovering — the group would never look lost, which is precisely the rec24 gap.
        let trackedActives = Set(world.filter { $0.tabs[$0.activeTab].tracked }.map { $0.activeWid })
        // The wids `syncSpacesState` captures for its per-window backfill: every window AltTab tracks AT THIS
        // MOMENT — background tabs and stale wids included, since the app asks about its whole list. Snapshot
        // it here with `trackedActives`, for the same reason: a window this show is still discovering was
        // never asked about, so the answer must say nothing about it (`.spacesSynced`'s `queried`).
        let queriedWids = Set(world.flatMap { w in (w.tabs + w.staleWids).filter { $0.tracked }.map { $0.wid } })
        // discover untracked ACTIVE tabs (the incoming active minted on a switch). Background tabs and stale
        // wids need no adoption here — they were tracked when active and REMAIN tracked (Space-less, retained
        // by Finder), and reconcile folds them; that is the accumulation, not a re-adoption.
        for i in world.indices {
            let active = world[i].tabs[world[i].activeTab]
            if !active.tracked {
                world[i].tabs[world[i].activeTab].tracked = true
                e.readUnits.append(appSteps(world[i].pid)
                    + [.track(trackedWindow(identity: world[i].identity, wid: active.wid, spaceIds: [world[i].space])),
                       .input(.discoveryLanded(wid: active.wid, accepted: true, newlyTracked: true,
                           adoptedAsInactiveTab: false, queriedSpaceIds: [world[i].space],
                           isOrderedIn: true, tabTitles: tabsReadable(world[i]) ? world[i].tabs.map { $0.title } : nil,
                           tabGroupToken: tabGroupToken(world[i])))]
                    // the tabs this discovery replaced can stop being held
                    + pendingHoldReleaseWids.map { .input(.holdReleaseCheck(wid: $0, attempt: 0)) })
                pendingHoldReleaseWids = []
            }
        }
        // brute-force AX adoption of INACTIVE tabs AltTab never tracked (you switched away from a tab before
        // it was ever discovered). An inactive tab is in no CGS list, so it arrives Space-LESS, and its own
        // fullscreen flag is false even inside a fullscreen window — its window is frozen at the parent's
        // frame, and the mirror hasn't been stamped yet. `adoptedAsInactiveTab` is the contract that says
        // "this is a known BACKGROUND tab, not the brand-new active" (rec24e).
        // ...but ONLY for a window whose ACTIVE tab was already tracked when this show began. The adoption is
        // not a free-standing scan: `Applications.discoverInactiveTabs` is driven by `untrackedTitles`, which
        // comes out of `matchSiblings`, which needs the active tracked and its AXTabGroup read. So a window
        // discovered by THIS show cannot also have its inactive tabs adopted by it — they arrive in a later
        // pass. Without this gate the read units were free to land an adoption BEFORE the discovery it
        // depends on, and at cold start (where every active is untracked) that unreachable interleaving made
        // a background tab the group's representative and hid the genuine active. Every pre-existing scenario
        // is unaffected: their actives were tracked by an earlier action.
        for i in world.indices where trackedActives.contains(world[i].activeWid) {
            for t in world[i].tabs.indices where t != world[i].activeTab && !world[i].tabs[t].tracked {
                world[i].tabs[t].tracked = true
                let wid = world[i].tabs[t].wid
                e.readUnits.append([.track(trackedWindow(identity: world[i].identity, wid: wid,
                        spaceIds: [], isFullscreen: false)),
                    .input(.discoveryLanded(wid: wid, accepted: true, newlyTracked: true,
                        adoptedAsInactiveTab: true, queriedSpaceIds: [], isOrderedIn: true,
                        tabTitles: nil, tabGroupToken: nil))])
            }
        }
        // The active tab's AXTabGroup read, WINDOWED ONLY — `tabsReadable` gates it, matching what
        // `AXUIElement.tabGroupInfo` actually reads (direct children). Not because a fullscreen tab group is
        // unreadable: a live probe showed a fullscreen window exposes the same AXTabGroup with the same tab
        // buttons and titles, nested one level deeper (`AXWindow/AXGroup/AXTabGroup`). Descending to it was
        // reverted because only SOME
        // apps expose it that way, and modelling an app-dependent read would grade downstream changes against
        // a world AltTab does not live in. See `tabsReadable` and `AXUIElement.tabGroupInfo`.
        for w in world where w.tabs.count > 1 && tabsReadable(w) {
            e.readUnits.append([.input(.titleAndTabsRead(wid: w.activeWid, tabTitles: w.tabs.map { $0.title },
                tabGroupToken: tabGroupToken(w), reconcileTabs: true, changedSoFar: false))])
        }
        // authoritative Space re-query (active tab → its Space; everything else absent)
        // The map is built from AltTab's TRACKED windows, so an UNTRACKED minted active contributes nothing —
        // and neither does its group, whose background tabs CGS lists on no Space and whose outgoing rep just
        // genuinely left. That is why the re-query wiped a whole group mid-switch (rec24): between the minted
        // wid's Space-join and its discovery, the group is invisible to this read.
        var spaceMap = [CGWindowID: [UInt64]]()
        let transitioning = windowsInSpaceTransition
        for w in world where !transitioning.contains(w.activeWid) && trackedActives.contains(w.activeWid) {
            spaceMap[w.activeWid] = [w.space]
        }
        // An ALL-empty map is unreachable in the app and so is never emitted: `syncSpacesState` backfills any
        // tracked wid the per-Space enumeration missed with a per-window `CGSCopySpacesForWindows` (#5791),
        // and that query still reports a backgrounded tab's OLD Space. Emitting one anyway asked the reducer
        // to converge from "every tracked window is Space-less at once", a state it never actually sees.
        if !spaceMap.isEmpty {
            // You cannot hold an answer about a window you never asked about: every wid the map places was
            // tracked when the pass captured its list. Asserted because `queriedWids` is otherwise pinned by
            // nothing — the scenarios pass with it set to every wid or to none, so a model that quietly stops
            // asking would keep every corpus test green while the re-query decided nothing at all.
            assert(spaceMap.keys.allSatisfy { queriedWids.contains($0) },
                "the model answered about \(spaceMap.keys.filter { !queriedWids.contains($0) }), which it never queried")
            // `placedByWindowServer` is empty: in the model the two OS reads never contradict each other, so
            // every unplaced wid is a confirmed empty. The contradiction is a live-OS anomaly (#5954) with no
            // recording to model it — inventing one would grade changes against a world we have not observed.
            e.readUnits.append([.input(.spacesSynced(windowToSpaces: spaceMap, queried: queriedWids,
                answered: queriedWids, placedByWindowServer: [], topologyChanged: false))])
        }
        // phantom pass: active tabs on the visible Space are VISIBLE; every wid is in ALL (Finder retains
        // the windows). The order of THIS vs the title/sync reads is exactly the rec24c/rec24e race the
        // interleaving fuzz varies.
        // ...and a MINIMIZED window is on no screen, so CGS does not list it as visible — while still
        // listing it in ALL. That asymmetry is what makes minimized windows look phantom to the naive rule,
        // and why `PhantomWindowDetector` exempts them explicitly.
        let visible = Set(world.filter { $0.space == currentVisibleSpace && !$0.isMinimized }.map { $0.activeWid })
            .subtracting(transitioning)
        let all = Set(world.flatMap { $0.allWids })
        e.readUnits.append([.input(.cgsWindowListsRead(visible: visible, all: all,
            queried: queriedWids))])
        // the switcher captures what it is showing; the pixels land after the reads that decided the layout
        e.readUnits.append(world.map { .thumbnailCaptured(wid: $0.activeWid) })
        return e
    }

    // MARK: - projection

    func trackedWindow(identity: Int, wid: CGWindowID, spaceIds: [UInt64],
                       isFullscreen: Bool? = nil, size: CGSize? = nil,
                       position: CGPoint? = nil) -> TrackedWindow {
        let w = world.first { $0.identity == identity }!
        // The WINDOW title, which is what discovery records. With `composedWindowTitles` it carries a suffix
        // the AX TAB title does not, so the two can never be compared successfully — see that flag.
        let tabTitle = w.title(of: wid) ?? w.tabs[w.activeTab].title
        let title = composedWindowTitles ? tabTitle + Self.windowTitleSuffix : tabTitle
        let known = w.frame(of: wid)
        let frame = (size: size ?? known.size, position: position ?? known.position)
        return TrackedWindow(id: "wid-\(wid)", wid: wid, pid: w.pid, title: title,
            size: frame.size, position: frame.position, spaceIds: spaceIds, spaceIndexes: [], isOnAllSpaces: false,
            spaceIsBorrowed: false, isFullscreen: isFullscreen ?? w.isFullscreen, isFullscreenMirrored: false,
            isMinimized: w.isMinimized, isMainWindow: false, isWindowlessApp: false, cgsPhantomLatch: false,
            // A brand-new window has NO pixels yet — its capture lands later, as its own read.
            lastFocusOrder: 0, creationOrder: Int(wid), hasThumbnail: false)
    }
}
