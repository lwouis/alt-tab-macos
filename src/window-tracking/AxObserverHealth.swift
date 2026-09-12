import Foundation
import CoreGraphics

/// Correlates an AX destroy with the WindowServer order-out for that same surface. Delivery for one window
/// says nothing about whether the app will announce its next close, so the exemption is single-use and
/// scoped by wid rather than becoming a permanent per-process capability.
struct AxDestroyCorrelation: Equatable {
    static let horizon: TimeInterval = 2
    private var deliveredAt = [CGWindowID: TimeInterval]()

    mutating func note(_ wid: CGWindowID, at: TimeInterval) {
        discardExpired(at)
        deliveredAt[wid] = at
    }

    mutating func shouldProbe(_ wid: CGWindowID, at: TimeInterval) -> Bool {
        discardExpired(at)
        guard deliveredAt.removeValue(forKey: wid) != nil else { return true }
        return false
    }

    private mutating func discardExpired(_ at: TimeInterval) {
        deliveredAt = deliveredAt.filter { at - $0.value <= Self.horizon }
    }
}

enum AxNotificationCapability: CaseIterable, Hashable {
    case focusedWindowChanged
    case mainWindowChanged
    /// **The title, pushed instead of polled.** There is no WindowServer title event, so without this the
    /// title has to be re-read from AX on every order-in, every order-out and every switcher show, and a
    /// title that changes between two shows is simply stale (the one live exposure named in the AX-to-WS
    /// event map: `matchSiblings` compares fresh AX tab titles against model window titles).
    ///
    /// It is in the core set rather than optional because it REPLACES per-app polling rather than adding to
    /// it, and because it was measured to register on every app that owns user-facing windows.
    /// Unlike `kAXFocusedUIElementChanged` (which must never be subscribed) this is a window-level
    /// notification, not an element-level stream.
    case titleChanged
    /// **Optional and unproven.** A private notification some apps post when the selected tab changes. It is
    /// registered separately and its refusal is that notification's business alone: an app that does not
    /// support it is not an unhealthy app, and the health policy already treats `notificationUnsupported` as
    /// permanent for one capability rather than for the observer.
    ///
    /// It mutates nothing. A third-party investigation reported it arriving in pairs naming the outgoing and
    /// incoming tab, but follow-up testing found that wrong for Finder, for Merge All Windows, and for an
    /// ungrouped window joining a group — so it is measured here before it is believed anywhere.
    case focusedTabChanged
    /// **The app naming its own new window.** The WindowServer's 811 is always first (measured 11/11 on real
    /// apps, by 36-597ms), so 811 remains the primary discovery trigger. AX creation carries what 811 cannot:
    /// a live `AXUIElement` for the window, which saves the `kAXWindows` acquisition round trip, and
    /// that element's `AXTabGroup`, readable inside the callback, so a mint is classified as a tab of a known
    /// group or a standalone window at the instant it appears.
    ///
    /// It means "an AXWindow element came into existence", NOT "a window was created": it also fires when a
    /// retained window is shown again (where the WindowServer emits only an order-in) and when a background
    /// tab is selected for the first time. Every consumer must be idempotent for an already-tracked wid.
    case windowCreated
    /// **The app saying one of its windows is gone.** The only prompt signal for the four close shapes the
    /// WindowServer cannot report: closed while minimized, while the app is hidden, while on another Space,
    /// or as a background tab. Measured at ~175ms on 11 real closes across 6 apps, where WindowServer 816
    /// covers only the on-screen case and 804 arrives 57-231s later.
    ///
    /// The notification's element is already dead, so `_AXUIElementGetWindow` cannot name it — but `CFEqual`
    /// against the element AltTab cached for the window does, locally, in ~30ns
    /// (`AxObserverRegistry.trackedElements`). An unmatched delivery is dropped before any attribute read,
    /// which is what makes the known bursts (Finder: 16 in one millisecond, all sub-window elements) free.
    case elementDestroyed

    /// **Off by default, and switchable on its own.** The probe registers a private notification on every
    /// app; nothing depends on the answer yet, and the set this provider actually needs must stay the narrow
    /// three that broad AX subscriptions taught us to keep it to.
    static var focusedTabProbeEnabled = false

    /// Whether this capability is part of the set every eligible process gets subscribed to.
    var isEnabled: Bool {
        self != .focusedTabChanged || Self.focusedTabProbeEnabled
    }
}

enum AxNotificationState: Equatable {
    case unattempted
    case subscribing
    case subscribed
    case unsupported
    case cooldown(until: MonotonicTimestamp)
}

enum AxProviderLifecycle: Equatable {
    case unregistered
    case registering
    case healthy
    case degraded
    case unresponsive
    case recovering
    case globalPermissionFailure
}

enum AxObserverInstanceState: Equatable {
    case absent
    case creating
    case ready
    case cooldown(until: MonotonicTimestamp)
}

enum AxObserverError: Equatable {
    case notificationUnsupported
    case notImplemented
    case cannotComplete
    case invalidUIElement
    case apiDisabled
    case invalidObserver
    case invalidArgument
    case genericFailure
}

enum AxSubscriptionResult: Equatable {
    case success
    case alreadyRegistered
    case notificationUnsupported
    case notImplemented
    case cannotComplete
    case invalidUIElement
    case apiDisabled
    case invalidObserver
    case invalidArgument
    case genericFailure
}

enum AxRecoveryTrigger: Equatable {
    case processBecameFrontmost
    case wake
    case unlock
    case otherAxCallSucceeded
    case recoveryTick
}

struct AxObserverDiagnostics: Equatable {
    var attemptCount = 0
    var capabilityAttemptCounts = [AxNotificationCapability: Int]()
    var observerGeneration: UInt64 = 0
    var consecutiveCannotComplete = 0
    var capabilityConsecutiveCannotComplete = [AxNotificationCapability: Int]()
    var lastError: AxObserverError?
    var nextRetry: MonotonicTimestamp?
    var observerCreationAttempts = 0
    var consecutiveObserverCreationFailures = 0

    mutating func recordAttempt(_ capability: AxNotificationCapability) {
        attemptCount += 1
        capabilityAttemptCounts[capability, default: 0] += 1
    }

    mutating func recordCannotComplete(_ capability: AxNotificationCapability) -> Int {
        capabilityConsecutiveCannotComplete[capability, default: 0] += 1
        refreshCannotCompleteAggregate()
        return capabilityConsecutiveCannotComplete[capability, default: 0]
    }

    mutating func resetCannotComplete(_ capability: AxNotificationCapability) {
        capabilityConsecutiveCannotComplete[capability] = nil
        refreshCannotCompleteAggregate()
    }

    mutating func resetCannotComplete() {
        capabilityConsecutiveCannotComplete.removeAll(keepingCapacity: true)
        consecutiveCannotComplete = 0
    }

    private mutating func refreshCannotCompleteAggregate() {
        consecutiveCannotComplete = capabilityConsecutiveCannotComplete.values.max() ?? 0
    }
}

struct AxProcessObserverHealth: Equatable {
    let process: ProcessGeneration
    var lifecycle = AxProviderLifecycle.unregistered
    var notifications: [AxNotificationCapability: AxNotificationState]
    var diagnostics = AxObserverDiagnostics()
    var observer = AxObserverInstanceState.absent

    init(process: ProcessGeneration) {
        self.process = process
        notifications = Dictionary(uniqueKeysWithValues: AxNotificationCapability.allCases.map { (
            $0,
            .unattempted
        ) })
    }

    var capabilities: Set<AxNotificationCapability> {
        Set(notifications.compactMap { $0.value == .subscribed ? $0.key : nil })
    }
}

struct AxObserverHealthState: Equatable {
    var entries = [Int32: AxProcessObserverHealth]()
    var hasGlobalPermissionFailure = false

    func entry(for process: ProcessGeneration) -> AxProcessObserverHealth? {
        guard let entry = entries[process.pid], entry.process == process else { return nil }
        return entry
    }
}

struct AxObserverRetryPolicy: Equatable {
    let shortRetryLimit: Int
    let initialRetryDelay: UInt64
    let maximumRetryDelay: UInt64
    /// The FIRST sparse wait, doubling up to `sparseCooldown`. A flat 30s here meant an app that was wedged
    /// when AltTab started and then began answering again waited out a full cooldown before anyone asked it
    /// anything, which for the user is half a minute of the switcher not offering windows that are on
    /// screen. The growth costs a handful of extra attempts in the first minute against an app that is
    /// permanently silent, and nothing at all after that.
    let initialSparseDelay: UInt64
    let sparseCooldown: UInt64

    static let `default` = Self(shortRetryLimit: 4, initialRetryDelay: 100_000_000,
                                maximumRetryDelay: 800_000_000, initialSparseDelay: 1_000_000_000,
                                sparseCooldown: 30_000_000_000)
}

enum AxObserverHealthInput: Equatable {
    case processStarted(ProcessGeneration)
    case beginObserverCreation(ProcessGeneration, at: MonotonicTimestamp)
    case observerCreationResult(ProcessGeneration, observerGeneration: UInt64,
                                error: AxObserverError?, at: MonotonicTimestamp)
    case beginSubscription(ProcessGeneration, AxNotificationCapability)
    case subscriptionResult(ProcessGeneration, observerGeneration: UInt64, AxNotificationCapability,
                            AxSubscriptionResult, at: MonotonicTimestamp)
    case callback(ProcessGeneration, observerGeneration: UInt64, AxNotificationCapability,
                  at: MonotonicTimestamp)
    case recoveryTriggered(ProcessGeneration, AxRecoveryTrigger, at: MonotonicTimestamp)
    case cooldownElapsed(ProcessGeneration, at: MonotonicTimestamp)
    case globalPermissionRestored(at: MonotonicTimestamp)
    case teardown(ProcessGeneration)
}

enum AxObserverHealthIgnoreReason: Equatable {
    case unknownProcess
    case staleProcessGeneration
    case staleObserverGeneration
    case globalPermissionFailure
    case notificationState
    case cooldown
    case duplicateProcess
    case noRecoveryNeeded
}

enum AxObserverHealthDecision: Equatable {
    case processRegistered(ProcessGeneration)
    case processGenerationReplaced(ProcessGeneration, cancelledObserverGeneration: UInt64)
    case observerCreationStarted(observerGeneration: UInt64)
    case observerReady(observerGeneration: UInt64)
    case observerCreationRetry(at: MonotonicTimestamp)
    case subscriptionStarted(AxNotificationCapability, observerGeneration: UInt64)
    case capabilitySubscribed(AxNotificationCapability)
    case capabilityUnsupported(AxNotificationCapability)
    case retryScheduled(AxNotificationCapability, at: MonotonicTimestamp, sparse: Bool)
    case observerRebuildRequired(cancelledGeneration: UInt64, replacementGeneration: UInt64)
    case callbackAccepted(AxNotificationCapability)
    case recoveryStarted(AxRecoveryTrigger)
    case globalPermissionFailed
    case globalRecoveryStarted([ProcessGeneration])
    case tornDown(cancelledObserverGeneration: UInt64)
    case ignored(AxObserverHealthIgnoreReason)
}

enum AxObserverHealth {
    static func reduce(_ state: inout AxObserverHealthState, _ input: AxObserverHealthInput,
                       policy: AxObserverRetryPolicy = .default) -> AxObserverHealthDecision {
        switch input {
        case let .processStarted(process): return processStarted(&state, process)
        case let .beginObserverCreation(process, time): return beginObserverCreation(&state, process, time)
        case let .observerCreationResult(process, generation, error, time):
            return observerCreationResult(&state, process, generation, error, time, policy)
        case let .beginSubscription(process, capability):
            return beginSubscription(&state, process, capability)
        case let .subscriptionResult(process, generation, capability, result, time):
            return subscriptionResult(&state, process, generation, capability, result, time, policy)
        case let .callback(process, generation, capability, _):
            return callback(&state, process, generation, capability)
        case let .recoveryTriggered(process, trigger, time):
            return recovery(&state, process, trigger, time)
        case let .cooldownElapsed(process, time):
            return recovery(&state, process, .recoveryTick, time)
        case .globalPermissionRestored:
            return permissionRestored(&state)
        case let .teardown(process): return teardown(&state, process)
        }
    }

    private static func processStarted(_ state: inout AxObserverHealthState,
                                       _ process: ProcessGeneration) -> AxObserverHealthDecision {
        guard let previous = state.entries[process.pid] else {
            state.entries[process.pid] = newEntry(process, state.hasGlobalPermissionFailure)
            return .processRegistered(process)
        }
        guard previous.process != process else { return .ignored(.duplicateProcess) }
        state.entries[process.pid] = newEntry(process, state.hasGlobalPermissionFailure)
        return .processGenerationReplaced(previous.process,
                                          cancelledObserverGeneration: previous.diagnostics.observerGeneration)
    }

    private static func newEntry(_ process: ProcessGeneration,
                                 _ hasGlobalPermissionFailure: Bool) -> AxProcessObserverHealth {
        var entry = AxProcessObserverHealth(process: process)
        guard hasGlobalPermissionFailure else { return entry }
        entry.lifecycle = .globalPermissionFailure
        entry.diagnostics.lastError = .apiDisabled
        return entry
    }

    private static func beginObserverCreation(_ state: inout AxObserverHealthState,
                                              _ process: ProcessGeneration,
                                              _ time: MonotonicTimestamp) -> AxObserverHealthDecision {
        guard !state.hasGlobalPermissionFailure else { return .ignored(.globalPermissionFailure) }
        guard var entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        if case let .cooldown(until) = entry.observer, time < until { return .ignored(.cooldown) }
        guard entry.observer != .creating, entry.observer != .ready else {
            return .ignored(.noRecoveryNeeded)
        }
        entry.diagnostics.observerGeneration &+= 1
        entry.diagnostics.observerCreationAttempts += 1
        entry.observer = .creating
        entry.lifecycle = .registering
        state.entries[process.pid] = entry
        return .observerCreationStarted(observerGeneration: entry.diagnostics.observerGeneration)
    }

    private static func observerCreationResult(_ state: inout AxObserverHealthState,
                                               _ process: ProcessGeneration, _ generation: UInt64,
                                               _ error: AxObserverError?, _ time: MonotonicTimestamp,
                                               _ policy: AxObserverRetryPolicy) -> AxObserverHealthDecision {
        guard var entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        guard entry.diagnostics.observerGeneration == generation else {
            return .ignored(.staleObserverGeneration)
        }
        guard entry.observer == .creating else { return .ignored(.notificationState) }
        guard let error else {
            entry.observer = .ready
            entry.lifecycle = .registering
            entry.diagnostics.lastError = nil
            entry.diagnostics.nextRetry = nil
            entry.diagnostics.consecutiveObserverCreationFailures = 0
            state.entries[process.pid] = entry
            return .observerReady(observerGeneration: generation)
        }
        if error == .apiDisabled { return permissionFailed(&state) }
        entry.diagnostics.consecutiveObserverCreationFailures += 1
        let tier = entry.diagnostics.consecutiveObserverCreationFailures
        var delay = min(policy.initialSparseDelay, policy.sparseCooldown)
        for _ in 1 ..< tier { delay = min(policy.sparseCooldown, adding(delay, to: delay)) }
        let retry = adding(delay, to: time)
        entry.observer = .cooldown(until: retry)
        entry.lifecycle = .degraded
        entry.diagnostics.lastError = error
        entry.diagnostics.nextRetry = retry
        state.entries[process.pid] = entry
        return .observerCreationRetry(at: retry)
    }

    private static func beginSubscription(_ state: inout AxObserverHealthState, _ process: ProcessGeneration,
                                          _ capability: AxNotificationCapability)
        -> AxObserverHealthDecision {
        guard !state.hasGlobalPermissionFailure else { return .ignored(.globalPermissionFailure) }
        guard var entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        guard entry.notifications[capability] == .unattempted else { return .ignored(.notificationState) }
        if entry.diagnostics.observerGeneration == 0 { entry.diagnostics.observerGeneration = 1 }
        entry.notifications[capability] = .subscribing
        entry.diagnostics.recordAttempt(capability)
        entry.lifecycle = entry.capabilities.isEmpty ? .registering : .recovering
        state.entries[process.pid] = entry
        return .subscriptionStarted(capability, observerGeneration: entry.diagnostics.observerGeneration)
    }

    private static func subscriptionResult(_ state: inout AxObserverHealthState, _ process: ProcessGeneration,
                                           _ generation: UInt64, _ capability: AxNotificationCapability,
                                           _ result: AxSubscriptionResult, _ time: MonotonicTimestamp,
                                           _ policy: AxObserverRetryPolicy) -> AxObserverHealthDecision {
        guard var entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        guard entry.diagnostics.observerGeneration == generation
        else { return .ignored(.staleObserverGeneration) }
        guard entry.notifications[capability] == .subscribing else { return .ignored(.notificationState) }
        switch result {
        case .success, .alreadyRegistered:
            entry.notifications[capability] = .subscribed
            entry.diagnostics.resetCannotComplete(capability)
            entry.diagnostics.nextRetry = nextRetry(entry)
            refreshLifecycle(&entry)
            state.entries[process.pid] = entry
            return .capabilitySubscribed(capability)
        case .notificationUnsupported, .notImplemented:
            entry.notifications[capability] = .unsupported
            entry.diagnostics.lastError = result == .notificationUnsupported
                ? .notificationUnsupported
                : .notImplemented
            entry.diagnostics.nextRetry = nextRetry(entry)
            refreshLifecycle(&entry)
            state.entries[process.pid] = entry
            return .capabilityUnsupported(capability)
        case .cannotComplete:
            return cannotComplete(&state, entry, capability, time, policy)
        case .invalidUIElement, .invalidObserver:
            return rebuild(&state, entry, result == .invalidUIElement ? .invalidUIElement : .invalidObserver)
        case .apiDisabled:
            return permissionFailed(&state)
        case .invalidArgument, .genericFailure:
            let error: AxObserverError = result == .invalidArgument ? .invalidArgument : .genericFailure
            return sparseFailure(&state, entry, capability, error, time, policy)
        }
    }

    private static func callback(_ state: inout AxObserverHealthState, _ process: ProcessGeneration,
                                 _ generation: UInt64,
                                 _ capability: AxNotificationCapability) -> AxObserverHealthDecision {
        guard var entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        guard entry.diagnostics.observerGeneration == generation
        else { return .ignored(.staleObserverGeneration) }
        guard entry.notifications[capability] == .subscribed else { return .ignored(.notificationState) }
        entry.diagnostics.resetCannotComplete(capability)
        refreshLifecycle(&entry)
        state.entries[process.pid] = entry
        return .callbackAccepted(capability)
    }

    private static func cannotComplete(_ state: inout AxObserverHealthState, _ entry: AxProcessObserverHealth,
                                       _ capability: AxNotificationCapability, _ time: MonotonicTimestamp,
                                       _ policy: AxObserverRetryPolicy) -> AxObserverHealthDecision {
        var entry = entry
        let refusalCount = entry.diagnostics.recordCannotComplete(capability)
        let sparse = refusalCount > policy.shortRetryLimit
        let delay = sparse
            ? sparseDelay(refusalCount - policy.shortRetryLimit, policy)
            : exponentialDelay(refusalCount, policy)
        let retry = adding(delay, to: time)
        entry.notifications[capability] = .cooldown(until: retry)
        entry.lifecycle = .unresponsive
        entry.diagnostics.lastError = .cannotComplete
        entry.diagnostics.nextRetry = nextRetry(entry)
        state.entries[entry.process.pid] = entry
        return .retryScheduled(capability, at: retry, sparse: sparse)
    }

    private static func sparseFailure(_ state: inout AxObserverHealthState, _ entry: AxProcessObserverHealth,
                                      _ capability: AxNotificationCapability, _ error: AxObserverError,
                                      _ time: MonotonicTimestamp,
                                      _ policy: AxObserverRetryPolicy) -> AxObserverHealthDecision {
        var entry = entry
        let retry = adding(policy.sparseCooldown, to: time)
        entry.notifications[capability] = .cooldown(until: retry)
        entry.lifecycle = .degraded
        entry.diagnostics.lastError = error
        entry.diagnostics.nextRetry = nextRetry(entry)
        state.entries[entry.process.pid] = entry
        return .retryScheduled(capability, at: retry, sparse: true)
    }

    private static func rebuild(_ state: inout AxObserverHealthState, _ entry: AxProcessObserverHealth,
                                _ error: AxObserverError) -> AxObserverHealthDecision {
        var entry = entry
        let cancelled = entry.diagnostics.observerGeneration
        entry.diagnostics.observerGeneration &+= 1
        entry.diagnostics.observerCreationAttempts += 1
        entry.observer = .creating
        entry.diagnostics.lastError = error
        entry.diagnostics.resetCannotComplete()
        entry.diagnostics.nextRetry = nil
        resetAttemptableCapabilities(&entry)
        entry.lifecycle = .recovering
        state.entries[entry.process.pid] = entry
        return .observerRebuildRequired(cancelledGeneration: cancelled,
                                        replacementGeneration: entry.diagnostics.observerGeneration)
    }

    private static func permissionFailed(_ state: inout AxObserverHealthState) -> AxObserverHealthDecision {
        state.hasGlobalPermissionFailure = true
        for pid in Array(state.entries.keys) {
            guard var entry = state.entries[pid] else { continue }
            resetAttemptableCapabilities(&entry)
            entry.lifecycle = .globalPermissionFailure
            entry.observer = .absent
            entry.diagnostics.lastError = .apiDisabled
            entry.diagnostics.nextRetry = nil
            state.entries[pid] = entry
        }
        return .globalPermissionFailed
    }

    private static func permissionRestored(_ state: inout AxObserverHealthState) -> AxObserverHealthDecision {
        guard state.hasGlobalPermissionFailure else { return .ignored(.noRecoveryNeeded) }
        state.hasGlobalPermissionFailure = false
        for pid in Array(state.entries.keys) {
            guard var entry = state.entries[pid] else { continue }
            entry.observer = .absent
            entry.lifecycle = .recovering
            entry.diagnostics.consecutiveObserverCreationFailures = 0
            state.entries[pid] = entry
        }
        return .globalRecoveryStarted(state.entries.values.map(\.process).sorted())
    }

    private static func recovery(_ state: inout AxObserverHealthState, _ process: ProcessGeneration,
                                 _ trigger: AxRecoveryTrigger,
                                 _ time: MonotonicTimestamp) -> AxObserverHealthDecision {
        guard !state.hasGlobalPermissionFailure else { return .ignored(.globalPermissionFailure) }
        guard var entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        let bypassCooldown = trigger == .otherAxCallSucceeded
        let recoverable = entry.notifications.filter {
            guard case let .cooldown(until) = $0.value else { return false }
            return bypassCooldown || time >= until
        }.map(\.key)
        guard !recoverable.isEmpty else {
            return .ignored(entry.diagnostics.nextRetry == nil ? .noRecoveryNeeded : .cooldown)
        }
        for capability in recoverable { entry.notifications[capability] = .unattempted }
        entry.diagnostics.nextRetry = nextRetry(entry)
        entry.lifecycle = .recovering
        state.entries[process.pid] = entry
        return .recoveryStarted(trigger)
    }

    private static func teardown(_ state: inout AxObserverHealthState,
                                 _ process: ProcessGeneration) -> AxObserverHealthDecision {
        guard let entry = state.entries[process.pid] else { return .ignored(.unknownProcess) }
        guard entry.process == process else { return .ignored(.staleProcessGeneration) }
        state.entries[process.pid] = nil
        return .tornDown(cancelledObserverGeneration: entry.diagnostics.observerGeneration)
    }

    private static func resetAttemptableCapabilities(_ entry: inout AxProcessObserverHealth) {
        for capability in AxNotificationCapability.allCases {
            if entry.notifications[capability] != .unsupported {
                entry.notifications[capability] = .unattempted
            }
        }
    }

    private static func refreshLifecycle(_ entry: inout AxProcessObserverHealth) {
        let hasCooldown = entry.notifications.values.contains {
            if case .cooldown = $0 { return true }; return false
        }
        if hasCooldown { entry.lifecycle = .degraded }
        else if !entry.capabilities.isEmpty { entry.lifecycle = .healthy }
        else if entry.notifications.values.contains(.subscribing) { entry.lifecycle = .registering }
        else { entry.lifecycle = .degraded }
    }

    private static func nextRetry(_ entry: AxProcessObserverHealth) -> MonotonicTimestamp? {
        entry.notifications.values.compactMap {
            if case let .cooldown(until) = $0 { return until }; return nil
        }.min()
    }

    /// `tier` counts from 1 at the first sparse failure: 1s, 2s, 4s … up to the cooldown, and there forever.
    private static func sparseDelay(_ tier: Int, _ policy: AxObserverRetryPolicy) -> UInt64 {
        var delay = min(policy.initialSparseDelay, policy.sparseCooldown)
        for _ in 1 ..< max(tier, 1) { delay = min(policy.sparseCooldown, adding(delay, to: delay)) }
        return delay
    }

    private static func exponentialDelay(_ attempt: Int, _ policy: AxObserverRetryPolicy) -> UInt64 {
        guard attempt > 1 else { return min(policy.initialRetryDelay, policy.maximumRetryDelay) }
        var delay = min(policy.initialRetryDelay, policy.maximumRetryDelay)
        for _ in 1 ..< attempt { delay = min(policy.maximumRetryDelay, adding(delay, to: delay)) }
        return delay
    }

    private static func adding(_ value: UInt64, to time: MonotonicTimestamp) -> MonotonicTimestamp {
        MonotonicTimestamp(rawValue: adding(value, to: time.rawValue))
    }

    private static func adding(_ lhs: UInt64, to rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}
