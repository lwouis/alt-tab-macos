import Cocoa
import ApplicationServices

/// **One `AXObserver` per live process generation, and nothing per window.**
///
/// An observer created for a pid and subscribed on the APPLICATION element receives the descendant window
/// notifications this needs. Per-window observers are therefore redundant, and orphaned per-window runloop
/// sources caused #5612's reported 399 GB virtual-memory growth. The observer count here is one per eligible
/// process and is independent of how many windows that process has.
///
/// This provider contributes the app-side story: focus, titles, tab groups, and AX-node creation/end. An AX
/// edge may prompt discovery or reconciliation, but WindowServer evidence still admits and physically retires
/// surfaces. An AX failure must not remove a window, block another process, or delay the first frame.
///
/// Results feed `AttentionDriver`, which is what turns them into a window order, and telemetry.
///
/// Threading: `observers` and `health` belong to `BackgroundWork.axSemanticsThread` and are only touched
/// there. Callbacks arrive on that thread and hand any IPC to `AXCallScheduler`, so a wedged app stalls its
/// own bounded call and not the runloop every other app's notifications arrive on.
class AxObserverRegistry {
    static let shared = AxObserverRegistry()

    private var observers = [pid_t: ObserverEntry]()
    private var health = AxObserverHealthState()
    /// The pids whose observer currently holds a live `titleChanged` subscription. `health` belongs to the
    /// AX thread, but the decision "may this window's title read be skipped" is taken on main, on the event
    /// path, so the one bit main needs is mirrored here. An app missing from it is simply read the old way,
    /// which is why losing an entry can never lose a title.
    private static let titleCapablePids = ConcurrentMap<pid_t, Bool>()

    private static let destroyCorrelations = ConcurrentMap<pid_t, AxDestroyCorrelation>()

    /// **Pids whose `elementDestroyed` deliveries are dropped on arrival**, so the app looks to the rest of
    /// AltTab exactly like one whose accessibility implementation accepted the subscription and never posts:
    /// the capability never turns on, and every close falls back to the WindowServer's order-out probe.
    ///
    /// It exists because that app is not otherwise reproducible. AppKit posts a window's destroy from the
    /// window's own deallocation, so an AppKit process cannot both destroy a window (leaving a dead element
    /// and an absence from `kAXWindows`, which is what the fallback reads) and stay silent about it. The
    /// implementations that CAN are the hand-rolled ones — Chromium, Electron, Qt, the JVM toolkits — and
    /// none of them can be stood up on demand. Injecting the silence here reproduces the one thing that
    /// matters, at the exact boundary where it would really happen: everything downstream of the missing
    /// callback is the ordinary production path, unmocked.
    private static let mutedDestroyPids = ConcurrentMap<pid_t, Bool>()

    /// Replace the muted set (empty clears it). Debug switch; nothing in normal operation calls this.
    ///
    /// Muting also forgets every unconsumed correlation. Otherwise an AX destroy delivered just before the
    /// debug switch was enabled could still exempt its later WindowServer order-out from the fallback probe.
    static func muteDestroys(pids: Set<pid_t>) {
        mutedDestroyPids.withLock { map in
            map.removeAll()
            for pid in pids { map[pid] = true }
        }
        destroyCorrelations.withLock { map in pids.forEach { map[$0] = nil } }
    }

    static func destroysAreMuted(_ pid: pid_t) -> Bool {
        mutedDestroyPids.withLock { $0[pid] != nil }
    }

    /// **The join `AXUIElementDestroyed` needs.** Its element is dead by callback time, so it cannot be asked
    /// its wid — but `CFEqual` recognises it against the element AltTab cached for the window when it was
    /// discovered, locally, in ~30ns and with no IPC. Mirrored off `Window.axUiElement`, which is main-owned,
    /// because the callback arrives on the AX thread.
    ///
    /// An entry going missing costs nothing but the signal: an unmatched destroy is dropped, and removal
    /// falls back to the WindowServer's order-out exactly as before.
    private static let trackedElements = ConcurrentMap<pid_t, [CGWindowID: AXUIElement]>()

    /// Whether this app pushes its title changes, so a title-only AX read for one of its windows is work
    /// the notification has already done (`Applications.refreshWindowTitleAndTabs`).
    static func deliversTitles(_ pid: pid_t) -> Bool {
        titleCapablePids.withLock { $0[pid] != nil }
    }

    static func shouldProbeAfterOrderOut(pid: pid_t, wid: CGWindowID, at: TimeInterval) -> Bool {
        destroyCorrelations.withLock { map in
            var correlation = map[pid] ?? AxDestroyCorrelation()
            let verdict = correlation.shouldProbe(wid, at: at)
            map[pid] = correlation
            return verdict
        }
    }

    private static func noteDestroy(pid: pid_t, wid: CGWindowID, at: TimeInterval) {
        destroyCorrelations.withLock { map in
            var correlation = map[pid] ?? AxDestroyCorrelation()
            correlation.note(wid, at: at)
            map[pid] = correlation
        }
    }

    /// Called from main whenever a window's cached element is set or replaced (`Window.init`,
    /// `Window.rebindAxElement`), and with `nil` when the window leaves the model.
    static func noteTrackedElement(pid: pid_t, wid: CGWindowID, element: AXUIElement?) {
        trackedElements.withLock { map in
            if let element {
                map[pid, default: [:]][wid] = element
            } else if map[pid] != nil {
                map[pid]?.removeValue(forKey: wid)
                if map[pid]?.isEmpty == true { map[pid] = nil }
            }
        }
    }

    static func forgetTrackedElements(pid: pid_t) {
        trackedElements.withLock { $0[pid] = nil }
    }

    /// Which tracked window this dead element was. A linear `CFEqual` scan over one app's windows: no IPC, so
    /// a delivery naming a sub-element (the common case, and the whole of Finder's 16-in-a-millisecond
    /// bursts) costs a few hundred nanoseconds and stops here.
    private static func trackedWid(of element: AXUIElement, pid: pid_t) -> CGWindowID? {
        trackedElements.withLock { map in
            map[pid]?.first { CFEqual($0.value, element) }?.key
        }
    }

    /// Does this window already have a cached element? The mirror is written on every transition of
    /// `Window.axUiElement` (init, rebind, removal), so an entry means yes. ADVISORY ONLY: it is read off
    /// main, where the model may have moved on, and `Applications.applyObservedElement` re-checks the real
    /// thing. Being behind costs one main hop that gets rejected there; being ahead costs nothing, since a
    /// window the model no longer holds is one that hop would have rejected anyway.
    private static func hasTrackedElement(pid: pid_t, wid: CGWindowID) -> Bool {
        trackedElements.withLock { $0[pid]?[wid] != nil }
    }

    private struct ObserverEntry {
        let process: ProcessGeneration
        let observer: AXObserver
        let element: AXUIElement
        let observerGeneration: UInt64
        var sourceInstalled = false
    }

    /// AltTab's own process is excluded: a same-process AX read runs AppKit on the CALLING thread, and this
    /// provider's whole point is to do that work off-main. `AXUIElement.onCorrectThread` exists for the reads
    /// we cannot avoid; an observer we can simply not create.
    func processStarted(_ pid: pid_t) {
        guard pid != AXUIElement.currentProcessPid else { return }
        let process = ProcessGeneration(pid: pid, generation: AttentionEngine.generation(of: pid))
        onAxThread { self.register(process) }
    }

    /// **Generation-checked.** Called both from the explicit quit path and from `Application.deinit`, and a
    /// deinit can land AFTER a replacement process has already registered under the reused pid. Tearing down
    /// by pid alone would then kill the live observer of the new process.
    func processExited(_ pid: pid_t, generation: UInt64) {
        onAxThread {
            guard self.health.entries[pid]?.process.generation == generation else { return }
            self.teardown(pid)
        }
    }

    /// Bounded re-probe triggers. A timer changes HEALTH only: it can start a subscription attempt, and it
    /// can never turn an ambiguous WindowServer event into focus.
    func recover(_ pid: pid_t, _ trigger: AxRecoveryTrigger) {
        onAxThread { self.recoverOnAxThread(pid, trigger) }
    }

    private func recoverOnAxThread(_ pid: pid_t, _ trigger: AxRecoveryTrigger) {
        guard let process = health.entries[pid]?.process else { return }
        guard let entry = observers[pid] else { return startObserverCreation(process) }
        let decision = AxObserverHealth.reduce(&health,
            .recoveryTriggered(entry.process, trigger, at: Self.now()))
        guard case .recoveryStarted = decision else { return }
        subscribeAll(entry.process)
        publishHealth(entry.process)
    }

    /// **The sparse recovery tick.** Every other trigger needs something to happen — an activation, a wake,
    /// an unlock. An app that was wedged and quietly starts answering again causes none of them, so without a
    /// tick it stays quarantined until the user happens to activate it. The health policy refuses anything
    /// not actually in cooldown, so this costs one pass over the table.
    func startRecoveryTicks() {
        scheduleRecoveryTick()
    }

    private func scheduleRecoveryTick() {
        BackgroundWork.axSemanticsThread?.asyncAfter(Self.recoveryTickInterval) { [weak self] in
            self?.recoverAll(.recoveryTick)
            self?.scheduleRecoveryTick()
        }
    }

    /// A BACKSTOP, not the retry driver: every cooldown schedules its own expiry (`scheduleRetry`), and this
    /// only catches an entry whose timer was lost. Matched to the sparse cooldown, because a shorter tick
    /// only asks a silent app more often for the same answer, and every ask is an AX call to a process that
    /// is not listening.
    private static let recoveryTickInterval: Double = 30

    /// Every process at once, for a system-wide event. Cheap: `recoveryTriggered` refuses anything already
    /// healthy, so a wake costs one pass over the table and a subscription attempt only where one is owed.
    func recoverAll(_ trigger: AxRecoveryTrigger) {
        onAxThread {
            if self.health.hasGlobalPermissionFailure, AXIsProcessTrusted() {
                self.restoreGlobalPermission()
                return
            }
            for pid in self.health.entries.keys { self.recoverOnAxThread(pid, trigger) }
        }
    }

    func accessibilityPermissionRestored() {
        onAxThread { self.restoreGlobalPermission() }
    }

    private func restoreGlobalPermission() {
        let decision = AxObserverHealth.reduce(&health, .globalPermissionRestored(at: Self.now()))
        guard case let .globalRecoveryStarted(processes) = decision else { return }
        for process in processes {
            releaseObserver(process.pid)
            startObserverCreation(process)
        }
    }

    // MARK: registration

    private func register(_ process: ProcessGeneration) {
        let decision = AxObserverHealth.reduce(&health, .processStarted(process))
        if case let .processGenerationReplaced(previous, _) = decision {
            releaseObserver(previous.pid)
            Self.forgetTrackedElements(pid: previous.pid)
        }
        guard decision != .ignored(.duplicateProcess) else { return }
        startObserverCreation(process)
    }

    private func startObserverCreation(_ process: ProcessGeneration) {
        let decision = AxObserverHealth.reduce(&health, .beginObserverCreation(process, at: Self.now()))
        guard case let .observerCreationStarted(generation) = decision else { return }
        createObserver(process, generation: generation)
    }

    private func createObserver(_ process: ProcessGeneration, generation: UInt64) {
        let made = makeObserver(process, generation: generation)
        let decision = AxObserverHealth.reduce(&health, .observerCreationResult(process,
            observerGeneration: generation, error: made.error, at: Self.now()))
        guard let entry = made.entry, case .observerReady = decision else {
            if case let .observerCreationRetry(at) = decision { scheduleObserverCreationRetry(process, at) }
            if case .globalPermissionFailed = decision {
                Logger.debug { "ax provider: accessibility API disabled" }
                for pid in Array(observers.keys) { releaseObserver(pid) }
            }
            publishHealth(process)
            return
        }
        observers[process.pid] = entry
        installSource(entry)
        subscribeAll(process)
        publishHealth(process)
    }

    /// Every `AXObserverCreate` result is checked. The old code force-unwrapped the observer and asked in a
    /// comment whether it could ever be nil; it can, for a process that is already gone.
    private func makeObserver(_ process: ProcessGeneration, generation: UInt64)
        -> (entry: ObserverEntry?, error: AxObserverError?) {
        var observer: AXObserver?
        let result = AXObserverCreate(process.pid, Self.callback, &observer)
        guard result == .success, let observer else {
            let error = Self.error(from: result)
            TrackingTelemetryRecorder.axProviderFailed(process, error)
            return (nil, error)
        }
        return (ObserverEntry(process: process, observer: observer,
            element: AXUIElementCreateApplication(process.pid), observerGeneration: generation), nil)
    }

    private func scheduleObserverCreationRetry(_ process: ProcessGeneration,
                                               _ deadline: MonotonicTimestamp) {
        let delay = Self.delay(until: deadline)
        BackgroundWork.axSemanticsThread?.asyncAfter(max(delay, 0)) {
            self.startObserverCreation(process)
        }
    }

    /// **`.commonModes`, and installed exactly once.** A source added in the default mode alone stops
    /// delivering while a scroll or a menu tracking loop is up, which is how notifications used to disappear
    /// mid-gesture.
    private func installSource(_ entry: ObserverEntry) {
        guard !entry.sourceInstalled, let runLoop = BackgroundWork.axSemanticsThread?.runLoop else { return }
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(entry.observer), .commonModes)
        observers[entry.process.pid]?.sourceInstalled = true
    }

    /// Deliberately narrow. `kAXFocusedUIElementChanged` is NOT here and must never be: subscribing to it
    /// harmed JetBrains-derived apps, LibreOffice and MATLAB, and it was removed for that reason.
    private func subscribeAll(_ process: ProcessGeneration) {
        for capability in AxNotificationCapability.allCases where capability.isEnabled {
            subscribe(process, capability)
        }
    }

    private func subscribe(_ process: ProcessGeneration, _ capability: AxNotificationCapability) {
        let begun = AxObserverHealth.reduce(&health, .beginSubscription(process, capability))
        guard case let .subscriptionStarted(_, observerGeneration) = begun,
              let entry = observers[process.pid], entry.process == process else { return }
        let refcon = Self.packRefcon(pid: process.pid, observerGeneration: observerGeneration)
        AXCallScheduler.shared.schedule(key: "axobs-\(process.pid)-\(capability.telemetryName)",
                                        context: "axSemantics", pid: process.pid) {
            let result = entry.element.addNotification(entry.observer, capability.notificationName, refcon)
            if result != .success && result != .notificationAlreadyRegistered {
                Logger.debug { "axobs pid=\(process.pid) \(capability.telemetryName) refused \(result.rawValue)" }
            }
            self.onAxThread {
                self.applySubscriptionResult(process, observerGeneration, capability, Self.result(from: result))
            }
        }
    }

    private func applySubscriptionResult(_ process: ProcessGeneration, _ observerGeneration: UInt64,
                                         _ capability: AxNotificationCapability,
                                         _ result: AxSubscriptionResult) {
        let hadNothing = health.entry(for: process)?.capabilities.isEmpty ?? true
        let decision = AxObserverHealth.reduce(&health, .subscriptionResult(process,
            observerGeneration: observerGeneration, capability, result, at: Self.now()))
        publishHealth(process)
        // **Rescan when an app STARTS ANSWERING, not when we ask it to.** An app that is permanently silent
        // is asked again on every sparse retry, and firing a whole-machine rescan per attempt cost 903 of
        // them in 55 minutes of ordinary use — measured, with six such apps on the machine. A rescan is only
        // owed when a process that had no working subscriptions gains one: that is the moment its windows
        // may be acquirable at last.
        if hadNothing, case .capabilitySubscribed = decision {
            DispatchQueue.main.async { Applications.manuallyRefreshAllWindows() }
        }
        switch decision {
        case let .retryScheduled(_, at, _): scheduleRetry(process, at)
        case .observerRebuildRequired: rebuild(process)
        case .globalPermissionFailed:
            Logger.debug { "ax provider: accessibility API disabled" }
            for pid in Array(observers.keys) { releaseObserver(pid) }
        default: break
        }
    }

    /// The retry budget lives in the pure policy; this only obeys the deadline it returned. The old
    /// implementation retried every 10ms forever, which is the failure this separation exists to prevent.
    ///
    /// **The cooldown has to be RELEASED before another attempt is possible.** A capability sitting in
    /// `.cooldown` refuses `beginSubscription`, so calling `subscribe` straight from here did nothing at all
    /// and the only thing retrying anything was the sparse tick — which is why a wedged app that started
    /// answering again took up to a tick plus a cooldown to come back.
    private func scheduleRetry(_ process: ProcessGeneration, _ deadline: MonotonicTimestamp) {
        let delay = Self.delay(until: deadline)
        BackgroundWork.axSemanticsThread?.asyncAfter(max(delay, 0)) {
            guard self.health.entry(for: process) != nil else { return }
            let decision = AxObserverHealth.reduce(&self.health, .cooldownElapsed(process, at: Self.now()))
            guard case .recoveryStarted = decision else { return }
            self.subscribeAll(process)
            self.publishHealth(process)
        }
    }

    /// An element that outlived its window (Electron and Zoom replace one without sending a destroy) makes
    /// every later call return `.invalidUIElement`. The cure is a new observer generation, not a retry.
    private func rebuild(_ process: ProcessGeneration) {
        releaseObserver(process.pid)
        let generation = health.entry(for: process)?.diagnostics.observerGeneration ?? 1
        createObserver(process, generation: generation)
    }

    // MARK: teardown

    /// **Synchronous invalidation.** The runloop source is removed explicitly rather than left to the
    /// observer's deallocation: orphaned sources are what leaked in #5612, and a source still installed keeps
    /// delivering into a generation that no longer exists.
    private func teardown(_ pid: pid_t) {
        guard let process = health.entries[pid]?.process else { return }
        _ = AxObserverHealth.reduce(&health, .teardown(process))
        releaseObserver(pid)
        Self.forgetTrackedElements(pid: pid)
    }

    private static func setTitleCapability(_ pid: pid_t, _ delivers: Bool) {
        titleCapablePids.withLock { delivers ? ($0[pid] = true) : ($0[pid] = nil) }
    }

    private func releaseObserver(_ pid: pid_t) {
        Self.setTitleCapability(pid, false)
        Self.destroyCorrelations.withLock { $0[pid] = nil }
        guard let entry = observers.removeValue(forKey: pid) else { return }
        guard let runLoop = BackgroundWork.axSemanticsThread?.runLoop else { return }
        CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(entry.observer), .commonModes)
    }

    // MARK: callbacks

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let (pid, observerGeneration) = unpackRefcon(refcon),
              let capability = AxNotificationCapability(notificationName: notification as String) else { return }
        shared.handle(pid, observerGeneration, capability, element)
    }

    /// Runs on the observer thread. It captures, it does not read: the only IPC a semantic edge needs is the
    /// element's wid, and that goes to the bounded pool so a wedged app cannot hold this runloop.
    private func handle(_ pid: pid_t, _ observerGeneration: UInt64, _ capability: AxNotificationCapability,
                        _ element: AXUIElement) {
        guard let entry = observers[pid], entry.observerGeneration == observerGeneration else { return }
        let decision = AxObserverHealth.reduce(&health, .callback(entry.process,
            observerGeneration: observerGeneration, capability, at: Self.now()))
        guard case .callbackAccepted = decision else { return }
        TrackingTelemetryRecorder.axNotification(pid)
        // Measured, never believed: a focused-tab notification is recorded with the window it named and
        // nothing else happens. Its production role is decided from the capture, not assumed here.
        guard capability != .focusedTabChanged else { return recordTabSignal(entry.process, element) }
        guard capability != .titleChanged else { return refreshTitle(entry.process, element) }
        // The destroy is answered entirely from the local cache: no wid to resolve (the element is dead) and
        // no attribute to read.
        guard capability != .elementDestroyed else { return windowDestroyed(entry.process, element) }
        guard capability != .windowCreated else { return windowCreated(entry.process, element) }
        resolveWid(entry.process, element, capability: capability)
    }

    /// **The title, straight from the app that changed it.** Reads the wid and the title in one scheduled
    /// block and hands both to the model, which is what lets `Applications.refreshWindowTitleAndTabs` stop
    /// asking for a title the app has already told us.
    ///
    /// Both reads are `try?`, so this never throws and the scheduler's retry/backoff never engages. A retry
    /// would re-ask a question that has moved on (the title changed again, or the window is gone), and
    /// `TabReadPolicy`'s rolling cursor re-reads the title for anything this missed. The per-key hold in
    /// `AXCallScheduler` plus the per-wid throttle on the apply side are what bound an app that renames its
    /// window continuously.
    ///
    /// **The role is read with the title, and decides whether the title counts.** A delivery names any
    /// element of the app, and only a window's own element speaks for the window: `AxTitleNotificationPolicy`
    /// says why, and #6011 is what it costs to skip. The role rides along in the same
    /// `AXUIElementCopyMultipleAttributeValues`, so it costs no extra round trip.
    private func refreshTitle(_ process: ProcessGeneration, _ element: AXUIElement) {
        AXCallScheduler.shared.schedule(key: Self.perElementKey("axobs-title", process.pid, element),
                                        context: "axSemantics", pid: process.pid) {
            guard let wid = try? element.cgWindowId(pid: process.pid), wid != 0,
                  let attributes = try? element.attributes([kAXTitleAttribute, kAXRoleAttribute], pid: process.pid)
                else { return }
            switch AxTitleNotificationPolicy.verdict(role: attributes.role, title: attributes.title) {
                case .ignoreNotTheWindow:
                    Logger.debug { "axTitle #\(wid) named role=\(attributes.role ?? "nil"); ignored" }
                case .ignoreNoTitle: break
                case .apply(let title):
                    Self.offerElement(process, wid, element, source: "axTitle")
                    DispatchQueue.main.async { Applications.applyObservedTitle(wid: wid, title: title) }
            }
        }
    }

    /// **The app says one window element ended.** Matched locally, then reconciled against a fresh AX window
    /// list and a direct WindowServer surface query. The notification is authoritative only for the node:
    /// apps rebuild one while its window stays on screen (Chromium and Electron do it routinely), and
    /// condemning on that edge alone made a live QQ window vanish and return with no MRU history (#5785).
    private func windowDestroyed(_ process: ProcessGeneration, _ element: AXUIElement) {
        // Dropped BEFORE the match, so a muted app never proves delivery and never gains the capability.
        guard !Self.destroysAreMuted(process.pid) else { return }
        guard let wid = Self.trackedWid(of: element, pid: process.pid) else { return }
        Self.noteDestroy(pid: process.pid, wid: wid, at: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.async {
            guard let window = Windows.byWindowId[wid], window.application.pid == process.pid else { return }
            Logger.debug { "axDestroy #\(wid) pid=\(process.pid) → reconciling" }
            TrackedWindowStateBridge.dispatch(.axElementEnded(wid: wid))
        }
    }

    /// **The app says a window element now exists.** WindowServer 811 remains the primary physical trigger;
    /// this also prompts idempotent discovery for what 811 does not emit (a retained window shown again, a
    /// background tab selected for the first time) and hands over the live element plus the window's tab
    /// group, both read in one scheduled block. For an already-tracked wid it only refreshes those facts.
    private func windowCreated(_ process: ProcessGeneration, _ element: AXUIElement) {
        AXCallScheduler.shared.schedule(key: Self.perElementKey("axobs-created", process.pid, element),
                                        context: "axSemantics", pid: process.pid) {
            let wid = try element.cgWindowId(pid: process.pid)
            guard wid != 0 else { return }
            let group = Self.readTabGroup(element, pid: process.pid)
            DispatchQueue.main.async {
                Applications.applyObservedWindowCreated(wid: wid, pid: process.pid, element: element,
                    tabGroup: group)
            }
        }
    }

    /// The `AXTabGroup` the notification's element belongs to, read INSIDE the delivery. Every window of a
    /// native tab group hands out the same element while it is the selected tab, so this is the group's
    /// identity rather than a guess from titles or geometry — and it is readable at the instant the OS
    /// announces the window (measured on Finder, Terminal and TextEdit).
    ///
    /// **Not gated on the app's known tab capability, deliberately.** The walk costs one `kAXChildren` round
    /// trip plus one per child, which IS the expense `TabReadPolicy` rations — but what it rations is the
    /// per-show pass doing this for every tracked window on every summon, hundreds of trips per press. Here
    /// it is one window, on a real user action, and `AXCallScheduler`'s per-key dedup collapses a burst.
    /// Gating on "this app has shown tabs before" was tried and is worse than useless: an app whose windows
    /// happened to have no tabs when AltTab started has the gate closed, so the tabs it opens later are never
    /// read on the notification at all.
    private static func readTabGroup(_ element: AXUIElement, pid: pid_t) -> TabGroupObservation {
        guard let children = try? element.attributes([kAXChildrenAttribute], pid: pid).children
            else { return .unknown }
        guard let group = TabGroup.extractTabGroup(children) else { return .standalone }
        return .group(titles: group.titles, token: group.token)
    }

    /// **Every notification arrives holding a live window element; three of the four handlers used to read
    /// its wid and drop it.** Offering it costs nothing here: the wid it is keyed by was just read off this
    /// same element, so the binding is proven rather than guessed. `Applications.applyObservedElement` owns
    /// the decision, including the role check that keeps a descendant out of `Window.axUiElement`.
    ///
    /// The reason to bother is the other Space: the posting path has no Space term, so this is the only
    /// channel that hands over an element for a window `kAXWindows` hides, short of the brute-force sweep.
    /// `windowCreated` is not routed through here because it already hands its element over whole, together
    /// with the tab group it read.
    ///
    /// The mirror check is what keeps the ordinary notification off the main queue: almost every window this
    /// is called for already has an element, and that answer is available right here.
    private static func offerElement(_ process: ProcessGeneration, _ wid: CGWindowID, _ element: AXUIElement,
                                     source: String) {
        guard wid != 0, !hasTrackedElement(pid: process.pid, wid: wid) else { return }
        DispatchQueue.main.async {
            Applications.applyObservedElement(wid: wid, pid: process.pid, element: element, source: source)
        }
    }

    private func recordTabSignal(_ process: ProcessGeneration, _ element: AXUIElement) {
        AXCallScheduler.shared.schedule(key: "axobs-tab-\(process.pid)", context: "axSemantics",
                                        pid: process.pid) {
            let wid = try element.cgWindowId(pid: process.pid)
            Self.offerElement(process, wid, element, source: "axFocusedTab")
            DispatchQueue.main.async {
                TrackingTelemetryRecorder.axFocusedTabSignal(pid: process.pid, wid: wid)
            }
        }
    }

    /// **Not cached by element.** Two `AXUIElement`s for one window are different objects that `CFEqual`
    /// considers the same, and their `CFHash` is not unique, so a cache keyed either way can hand back
    /// another window's id. `_AXUIElementGetWindow` is the cheapest AX call there is and a semantic edge is
    /// rare — a focus change, not a stream — so it is read each time, on the bounded pool.
    private func resolveWid(_ process: ProcessGeneration, _ element: AXUIElement, capability: AxNotificationCapability) {
        // **Keyed per capability, not per pid.** `AXCallScheduler` dedups per key, and focused-window and
        // main-window changes arrive together on almost every switch — so a shared key let the focus read
        // swallow the main-window one, and with it the tab-group read that only the latter performs. The
        // coalescing that key was for is still there, now within each capability.
        AXCallScheduler.shared.schedule(key: "axobs-wid-\(process.pid)-\(capability.telemetryName)",
                                        context: "axSemantics", pid: process.pid) {
            let wid = try element.cgWindowId(pid: process.pid)
            Self.offerElement(process, wid, element, source: capability.telemetryName)
            // **The tab switch, carrying its group.** `AXMainWindowChanged` is what the OS emits when the
            // selected tab changes, and the element it hands over answers for its `AXTabGroup` right here —
            // the group's own identity, rather than the arrival-time pairing plus title matching the reducer
            // otherwise reconstructs it from. Read in the same scheduled block as the wid so a switch costs
            // one trip to the app, and only for an app that has ever shown a tab group.
            if capability == .mainWindowChanged {
                let group = Self.readTabGroup(element, pid: process.pid)
                DispatchQueue.main.async {
                    Applications.applyObservedTabGroup(wid: wid, pid: process.pid,
                        observation: group, source: "axMainWindow")
                }
            }
            self.onAxThread {
                // The process may have died, or been replaced by a new generation, while the read was out.
                guard self.observers[process.pid]?.process == process else { return }
                self.publishSemantic(process, wid)
            }
        }
    }

    private func publishSemantic(_ process: ProcessGeneration, _ wid: CGWindowID) {
        guard wid != 0 else { return }
        DispatchQueue.main.async { AttentionEngine.axSemanticFocus(pid: process.pid, wid: wid) }
    }

    private func publishHealth(_ process: ProcessGeneration) {
        guard let entry = health.entry(for: process) else { return }
        let capabilities = Array(entry.capabilities)
        Self.setTitleCapability(process.pid, capabilities.contains(.titleChanged))
        let diagnostics = entry.diagnostics
        let lifecycle = entry.lifecycle
        DispatchQueue.main.async {
            TrackingTelemetryRecorder.axProviderHealth(pid: process.pid, state: lifecycle,
                observerGeneration: diagnostics.observerGeneration, attempts: diagnostics.attemptCount,
                capabilities: capabilities, lastError: diagnostics.lastError)
        }
    }

    // MARK: plumbing

    private func onAxThread(_ block: @escaping () -> Void) {
        guard let thread = BackgroundWork.axSemanticsThread else { return }
        thread.async(block)
    }

    private static func now() -> MonotonicTimestamp {
        MonotonicTimestamp(rawValue: DispatchTime.now().uptimeNanoseconds)
    }

    private static func delay(until deadline: MonotonicTimestamp) -> TimeInterval {
        let now = Self.now().rawValue
        guard deadline.rawValue > now else { return 0 }
        return Double(deadline.rawValue - now) / 1_000_000_000
    }

    /// **A scheduler key for a notification whose payload is ONE WINDOW.** `AXCallScheduler` holds a single
    /// pending block per key and overwrites it, so a pid-wide key does not coalesce a burst from one app — it
    /// runs the first delivery and the last and DROPS everything between, each of which named a different
    /// window. Five Finder tabs created in the same millisecond is the ordinary shape of a Cmd+T burst, and it
    /// is exactly the case where the tab group each callback carries is worth most.
    ///
    /// The element POINTER is the discriminator, not an identity. `resolveWid` rightly warns that two
    /// `AXUIElement`s for one window are distinct objects that `CFEqual` calls equal, so neither the pointer
    /// nor `CFHash` may be cached as a window's identity — but that failure is in the direction this use does
    /// not care about. Two pointers for one window give two keys and run the block twice, which is harmless
    /// because every consumer is idempotent; one pointer arriving twice gives one key and coalesces, which is
    /// the intended saving. What must never happen is two WINDOWS sharing a key, and distinct objects cannot.
    private static func perElementKey(_ prefix: String, _ pid: pid_t, _ element: AXUIElement) -> String {
        "\(prefix)-\(pid)-\(UInt(bitPattern: ObjectIdentifier(element)))"
    }

    /// Process identity travels in the refcon rather than being asked for over IPC on every delivery. The
    /// observer generation rides with it so a callback from a rebuilt observer is recognisably stale.
    private static func packRefcon(pid: pid_t, observerGeneration: UInt64) -> UnsafeMutableRawPointer? {
        let packed = UInt(UInt32(bitPattern: pid)) << 32 | UInt(observerGeneration & 0xFFFF_FFFF)
        return UnsafeMutableRawPointer(bitPattern: packed)
    }

    private static func unpackRefcon(_ refcon: UnsafeMutableRawPointer?) -> (pid_t, UInt64)? {
        guard let refcon else { return nil }
        let packed = UInt(bitPattern: refcon)
        return (pid_t(Int32(bitPattern: UInt32(packed >> 32))), UInt64(packed & 0xFFFF_FFFF))
    }

    /// Each AX result gets its own state, rather than one retry bucket for every failure. `.cannotComplete`
    /// is a busy process and cools down; `.notificationUnsupported` is permanent for THAT notification only
    /// and must not mark the whole observer unhealthy; `.apiDisabled` is global and must not be hammered per
    /// pid.
    private static func result(from error: AXError) -> AxSubscriptionResult {
        switch error {
        case .success: return .success
        case .notificationAlreadyRegistered: return .alreadyRegistered
        case .notificationUnsupported: return .notificationUnsupported
        case .notImplemented: return .notImplemented
        case .cannotComplete: return .cannotComplete
        case .invalidUIElement: return .invalidUIElement
        case .invalidUIElementObserver: return .invalidObserver
        // **Only OUR permission being gone is global.** Measured: several processes on a machine with
        // Accessibility granted still answer `kAXErrorAPIDisabled` (-25211) for their own reasons. Passing
        // that straight through set the provider's global-permission flag and every later subscription for
        // EVERY app was refused before it was attempted — 138 successful subscriptions, then silence. So the
        // escalation is gated on `AXIsProcessTrusted`, and an individual app's refusal is a per-pid
        // temporary failure like any other.
        case .apiDisabled: return AXIsProcessTrusted() ? .cannotComplete : .apiDisabled
        case .illegalArgument: return .invalidArgument
        default: return .genericFailure
        }
    }

    private static func error(from result: AXError) -> AxObserverError {
        switch result {
        case .cannotComplete: return .cannotComplete
        case .invalidUIElement: return .invalidUIElement
        // **Only OUR permission being gone is global.** Measured: several processes on a machine with
        // Accessibility granted still answer `kAXErrorAPIDisabled` (-25211) for their own reasons. Passing
        // that straight through set the provider's global-permission flag and every later subscription for
        // EVERY app was refused before it was attempted — 138 successful subscriptions, then silence. So the
        // escalation is gated on `AXIsProcessTrusted`, and an individual app's refusal is a per-pid
        // temporary failure like any other.
        case .apiDisabled: return AXIsProcessTrusted() ? .cannotComplete : .apiDisabled
        case .illegalArgument: return .invalidArgument
        default: return .genericFailure
        }
    }
}

extension AxNotificationCapability {
    var notificationName: String {
        switch self {
        case .focusedWindowChanged: return kAXFocusedWindowChangedNotification
        case .mainWindowChanged: return kAXMainWindowChangedNotification
        case .titleChanged: return kAXTitleChangedNotification
        case .focusedTabChanged: return "AXFocusedTabChanged"
        case .windowCreated: return kAXWindowCreatedNotification
        case .elementDestroyed: return kAXUIElementDestroyedNotification
        }
    }


    init?(notificationName: String) {
        guard let match = Self.allCases.first(where: { $0.notificationName == notificationName }) else {
            return nil
        }
        self = match
    }
}
