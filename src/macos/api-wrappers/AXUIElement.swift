import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXValue
import ApplicationServices.HIServices.AXError
import ApplicationServices.HIServices.AXRoleConstants
import ApplicationServices.HIServices.AXAttributeConstants
import ApplicationServices.HIServices.AXActionConstants

/// common, subscriptions
extension AXUIElement {
    // default timeout for AX calls is 6s
    // we reduce to 1s to avoid AX calls blocking threads, thus too many threads getting created to make the next AX calls
    private static let globalMessagingTimeoutInSeconds = Float(1)
    static func setGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), globalMessagingTimeoutInSeconds)
    }

    /// **A failed call is not an answer.** Anything but `.success` means the OS told us nothing about this
    /// element, and the two failure shapes need different handling, so they get different errors:
    /// `.cannotComplete` is the messaging timeout of a busy app and may succeed later (`AXCallScheduler`
    /// retries it); every other error is permanent for this call (a dead element, an attribute the app does
    /// not implement, an app refusing the API for its own reasons) and retrying only spends the app's budget.
    ///
    /// Neither may be read as a fact. Returning a zero-filled `AXAttributes` for a failed read is what let one
    /// unanswered call remove a live window from the switcher: `role` and `subrole` came back nil, and
    /// `WindowAdmissionResolver` rightly rejects a surface with no window role — except the app never said it
    /// had none. Same lesson as `castSafely`'s `.axError` placeholders and the empty-Space rule, one level up.
    private func throwIfNotSuccess(_ result: AXError) throws -> Void {
        if result == .success { return }
        throw result == .cannotComplete ? AxError.appUnresponsive : AxError.noAnswer
    }

    /// **The only place `AXObserverAddNotification` is called.**
    ///
    /// `subscribeToNotification` below collapses every failure into a Bool or a throw, which suits its
    /// callers and does not suit `AxObserverRegistry`, whose health policy keys on the exact `AXError` (a
    /// per-notification `notificationUnsupported` must not mark the whole observer unhealthy). Both shapes
    /// go through here.
    ///
    /// Worth knowing when reading its count: the cost is per FIRST call to a process (~25ms, the
    /// accessibility handshake), and ~0.1ms for every further registration on the same observer and element.
    /// So the total tracks how many apps are subscribed, not how many notifications each one takes.
    func addNotification(_ axObserver: AXObserver, _ notification: String,
                         _ refcon: UnsafeMutableRawPointer? = nil) -> AXError {
        AXObserverAddNotification(axObserver, self, notification as CFString, refcon)
    }

    @discardableResult
    func subscribeToNotification(_ axObserver: AXObserver, _ notification: String, _ refcon: UnsafeMutableRawPointer? = nil) throws -> Bool {
        // `refcon` is handed back verbatim to the AX callback for every delivery of this (element,
        // notification) pair. The only remaining caller is DockEvents (Mission Control), which passes nil;
        // the packed-(pid, wid) refcon scheme this supported went away with the per-window AX observers.
        let result = addNotification(axObserver, notification, refcon)
        if result == .success || result == .notificationAlreadyRegistered {
            return true
        }
        if result == .notificationUnsupported || result == .notImplemented {
            // subscription will never succeed
            return false
        }
        // temporary issue; subscription may succeed if retried
        throw AxError.appUnresponsive
    }
}

/// Attributes
extension AXUIElement {
    /// our own process's pid, cached. used to spot same-process AX elements (see `onCorrectThread(pid:_:)`).
    static let currentProcessPid = ProcessInfo.processInfo.processIdentifier

    /// The single place the own-process-AX threading rule lives. An AX read on an element in ANOTHER process is
    /// real Mach IPC and runs inline on the caller's (off-main) thread. An AX read on an element in our OWN
    /// process does NO IPC — `AXUIElementCopy*` / `_AXUIElementGetWindow` dispatch straight into AppKit's
    /// accessibility implementation on the CALLING thread (e.g. `-[_NSPopoverWindow accessibilityTitle]`), and
    /// AppKit is main-thread-only, so off-main they race AppKit's teardown of transient windows and trap in
    /// `__CF_IS_OBJC`. So run `body` on the main thread when `pid` is our own process AND we're off-main (a
    /// `main.sync` from the main thread would deadlock); otherwise run it inline. Every pid-aware AX accessor
    /// (`attributes(_:pid:)`, `liveness(pid:)`, `cgWindowId(pid:)`, `WindowElementAcquisition`) funnels here.
    static func onCorrectThread<T>(pid: pid_t, _ body: () throws -> T) rethrows -> T {
        if pid == currentProcessPid, !Thread.isMainThread {
            return try DispatchQueue.main.sync { try body() }
        }
        return try body()
    }

    /// This element's own AXUIElementID. Used to ANCHOR a brute-force sweep near an app's windows instead of
    /// at id 0, which is what made the inactive-tab scan find anything (`InactiveTabScanPolicy.scanStart`).
    func id() -> AXUIElementID? {
        let pointer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()).advanced(by: 0x20)
        let cfDataPointer = pointer.load(as: CFData?.self)
        let cfData = cfDataPointer
        let bytePtr = CFDataGetBytePtr(cfData)
        return bytePtr?.withMemoryRebound(to: AXUIElementID.self, capacity: 1) { $0.pointee }
    }

    func cgWindowId() throws -> CGWindowID {
        var id = CGWindowID(0)
        try throwIfNotSuccess(_AXUIElementGetWindow(self, &id))
        return id
    }

    /// pid-aware `cgWindowId()` — routes the own-process read to main. See `onCorrectThread(pid:_:)`.
    func cgWindowId(pid: pid_t) throws -> CGWindowID {
        try Self.onCorrectThread(pid: pid) { try cgWindowId() }
    }

    /// A direct liveness probe for the window behind this element. Returns the raw `AXError` so the caller can
    /// tell a DEAD element (`.invalidUIElement` — the window was closed/destroyed) apart from a merely
    /// UNRESPONSIVE app (`.cannotComplete` — retry later) or a live one (`.success`). Reads `kAXRole`, the
    /// cheapest always-present attribute. Used to catch a close that WindowServer's destroy event (804) reports
    /// late or never — apps like Finder retain the CGWindow for seconds-to-forever after closing the window,
    /// but the AX element dies within ~20ms. Own-process read routed to main (see `onCorrectThread(pid:_:)`).
    func liveness(pid: pid_t) -> AXError {
        Self.onCorrectThread(pid: pid) {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(self, kAXRoleAttribute as CFString, &value)
        }
    }

    func attributes(_ keys: [String]) throws -> AXAttributes {
        var values: CFArray?
        try throwIfNotSuccess(AXUIElementCopyMultipleAttributeValues(self, keys as CFArray, [], &values))
        let array = values as? [CFTypeRef] ?? []
        var result = AXAttributes()
        for (index, key) in keys.enumerated() {
            guard index < array.count else { continue }
            let value = array[index]
            switch key {
            case kAXTitleAttribute: result.title = castSafely(value)
            case kAXRoleAttribute: result.role = castSafely(value)
            case kAXSubroleAttribute: result.subrole = castSafely(value)
            case kAXStatusLabelAttribute: result.statusLabel = castSafely(value)
            case kAXMinimizedAttribute: result.isMinimized = castSafely(value)
            case kAXFullscreenAttribute: result.isFullscreen = castSafely(value)
            case kAXMainAttribute: result.isMain = castSafely(value)
            case kAXIsApplicationRunningAttribute: result.appIsRunning = castSafely(value)
            case kAXURLAttribute: result.url = castSafely(value)
            case kAXFocusedWindowAttribute: result.focusedWindow = castSafely(value)
            case kAXMainWindowAttribute: result.mainWindow = castSafely(value)
            case kAXCloseButtonAttribute: result.closeButton = castSafely(value)
            case kAXChildrenAttribute: result.children = castSafely(value)
            case kAXWindowsAttribute: result.windows = castSafely(value)
            case kAXPositionAttribute: result.position = castSafely(value)
            case kAXSizeAttribute: result.size = castSafely(value)
            default: Logger.error { "key:\(key) value:\(value)" }
            }
        }
        return result
    }

    /// pid-aware variant of `attributes(_:)` — routes the own-process read to main. See `onCorrectThread(pid:_:)`.
    func attributes(_ keys: [String], pid: pid_t) throws -> AXAttributes {
        try Self.onCorrectThread(pid: pid) { try attributes(keys) }
    }

    private func walkChildren(pageSize: Int, pid: pid_t, mayRead: () -> Bool,
                              visit: (AXUIElement) -> Bool?) -> AxChildrenTraversal.Result {
        AxChildrenTraversal.walk(pageSize: pageSize, mayRead: mayRead, count: {
            Self.onCorrectThread(pid: pid) {
                var count: CFIndex = 0
                guard AXUIElementGetAttributeValueCount(self, kAXChildrenAttribute as CFString, &count) == .success,
                      count >= 0 else { return nil }
                return Int(count)
            }
        }, page: { offset, amount in
            Self.onCorrectThread(pid: pid) {
                var values: CFArray?
                guard AXUIElementCopyAttributeValues(self, kAXChildrenAttribute as CFString, offset, amount, &values) == .success,
                      let elements = values as? [AXUIElement] else { return nil }
                return elements
            }
        }, visit: visit)
    }

    func castSafely<T>(_ value: CFTypeRef) -> T? {
        switch CFGetTypeID(value) {
        case AXValueGetTypeID():
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .axError:
                // without .stopOnError, AXUIElementCopyMultipleAttributeValues always returns an array. it contains placeholder values.
                // This makes it very hard to know what's real. For example, if an app has no MainWindow, it will return .axError. If we cast it to AXUIElement, it will succeed, but the object will have its attributes zero'd
                // we have to check for .axError, which we map to nil values
                return nil
            // AXValueGetValue leaves the out-param UNTOUCHED when it fails, so ignoring its Bool handed back
            // the zero-initialized value as if the OS had said so: a failed size read became 0×0 and a failed
            // position read became @0,0 (same zeroing the .axError comment above describes). Live, a new Finder
            // tab read back `0x0@0,0`, so no thumbnail could be drawn and the switcher showed one tile of empty
            // pixels until the next read healed it. A failed read is unknown, not zero — say nil.
            case .cgSize:
                var size = CGSize.zero
                guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
                return size as? T
            case .cgPoint:
                var point = CGPoint.zero
                guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
                return point as? T
            case let unknownAXValueType:
                Logger.error { unknownAXValueType }
                return nil
            }
        case AXUIElementGetTypeID(): return value as? T
        case CFArrayGetTypeID(): return value as? T
        case CFURLGetTypeID(): return value as? T
        case CFStringGetTypeID(): return value as? T
        case CFBooleanGetTypeID(): return value as? T
        case let unknownCFTypeID:
            Logger.error { unknownCFTypeID }
            return nil
        }
    }

    /// The window elements an app hands us for one batched read, per `PublishedWindows` — `kAXWindows` (the
    /// CURRENT Space only) plus the two window attributes AppKit does NOT put behind that Space filter. Same
    /// single round trip either way, so the other-Space reach costs no IPC. The specs hold the why.
    func windowsIncludingKeyAndMain() throws -> [AXUIElement] {
        let attributes = try attributes(PublishedWindows.attributes)
        return PublishedWindows.merge(windows: attributes.windows, focused: attributes.focusedWindow,
                                      main: attributes.mainWindow)
    }

    /// Wall-clock budget for any brute-force AX scan. The AXUIElementID space is `UInt64` and a long-lived app's
    /// windows can have high, sparse ids, so TIME — not an id ceiling — is the real bound; a monotonic
    /// `LightweightTimer` (checked every iteration) makes it reliable. Shared so every brute-force is capped the
    /// same way. These run on the isolated AX scan pool (`scan: true`), off the main thread.
    /// Build an element per AXUIElementID for `pid` from a remote token (`_AXUIElementCreateWithRemoteToken` —
    /// the only way to reach elements the app omits from `kAXWindows`, including other-Space windows and
    /// inactive OS tabs) and hand it to `inspect`, until `inspect` returns true or the budget elapses.
    /// IPC per id — off the main thread only. The token's id field is the only part rewritten per iteration.
    ///
    /// Returns the id the sweep stopped at, so a caller that can be RETRIED resumes instead of re-walking the
    /// same dead prefix. That matters because the budget is wall-clock while the id space is `UInt64`: a scan
    /// covers a window of ids, not the space, and restarting always at 0 means every retry inspects exactly the
    /// ids that already failed. Measured live (2026-07-30): the inactive-tab scan ran 31 times and adopted
    /// nothing on any of them, because a long-lived Finder keeps its window elements at ids the first 250ms
    /// never reaches — the same scan adopted 57 in an earlier run where they happened to sit lower.
    @discardableResult
    private static func bruteForceElements(_ pid: pid_t, from startId: AXUIElementID = 0,
                                           _ inspect: (AXUIElement, () -> Bool) -> Bool) -> AXUIElementID {
        // 20 bytes: pid (4) + 0 (4) + magic 0x636f636f "coco" (4) + AXUIElementID (8); byte order matters.
        // ONE mutable CFData for the whole sweep, with only the id field rewritten in place. Building a fresh
        // `Data` per field and bridging it to `CFData` per candidate allocated twice per iteration, and this
        // loop runs thousands of iterations inside its 250ms budget: on a 51s Instruments trace it was 7.5% of
        // the process's entire malloc/free traffic, second only to the state snapshot.
        // Safe because the element does NOT alias the token: measured on TextEdit (two AXWindow roots captured
        // from one reused buffer, then 30k further mutations parked on another id) both kept their own wid and
        // role, so `_AXUIElementCreateWithRemoteToken` parses the bytes rather than retaining them.
        guard let remoteToken = CFDataCreateMutable(kCFAllocatorDefault, 20) else { return startId }
        CFDataSetLength(remoteToken, 20)
        guard let bytes = CFDataGetMutableBytePtr(remoteToken) else { return startId }
        memset(bytes, 0, 20)
        var pidField = pid
        memcpy(bytes, &pidField, 4)
        var magic = Int32(0x636f636f)
        memcpy(bytes + 8, &magic, 4)
        let timer = LightweightTimer()
        return AxTraversalPolicy.scan(from: startId, elapsedMs: { timer.elapsedMilliseconds }, candidate: { id in
            var idField = id
            memcpy(bytes + 12, &idField, 8)
            return _AXUIElementCreateWithRemoteToken(remoteToken)?.takeRetainedValue()
        }, inspect: inspect)
    }

    /// Resolve every requested other-Space wid in ONE AXUIElementID traversal. The inventory knows all of a
    /// process's missing wids at once; scanning once per wid repeated the same id prefix and spent a separate
    /// 250ms budget on every non-window surface. This shares one budget and stops when every requested root is
    /// found. It records no negative range: a later inventory starts a fresh traversal from id 0.
    ///
    /// `_AXUIElementGetWindow` on a descendant returns its CONTAINING window's wid too, so a wid match is not
    /// enough. Read the role only for descendants of a requested wid and keep scanning until the `AXWindow`
    /// root. This is the same #5849 invariant as the single-wid route below.
    static func windowsByBruteForce(_ pid: pid_t, _ wids: Set<CGWindowID>) -> [CGWindowID: AXUIElement] {
        guard !wids.isEmpty else { return [:] }
        var remaining = wids
        var found = [CGWindowID: AXUIElement]()
        found.reserveCapacity(wids.count)
        bruteForceElements(pid) { candidate, mayStartIpc in
            guard mayStartIpc(), let wid = try? candidate.cgWindowId(), remaining.contains(wid), mayStartIpc()
                else { return false }
            let role = (try? candidate.attributes([kAXRoleAttribute]))?.role
            guard BruteForceWindowMatch.isTargetWindowRoot(candidateWid: wid, candidateRole: role, targetWid: wid) else { return false }
            found[wid] = candidate
            remaining.remove(wid)
            return remaining.isEmpty
        }
        return found
    }

    /// The event-driven and stale-element repair paths ask for one wid. Keep their interface and semantics on
    /// the same multi-target implementation used by the inventory.
    static func windowByBruteForce(_ pid: pid_t, _ wid: CGWindowID) -> AXUIElement? {
        windowsByBruteForce(pid, [wid])[wid]
    }

    /// Find untracked standard windows whose title is one of `titles` — the only way to reach an INACTIVE OS
    /// TAB's window, which is absent from every CGS list (so normal discovery misses it) yet still reachable
    /// through the remote token. A tracked window's child elements resolve to its (excluded) wid, so they're
    /// skipped before the subrole read; only untracked wids pay for it. Returns each match's wid + element +
    /// title; stops once `titles.count` are found.
    /// `from` / the returned `nextId` let successive attempts RESUME: this scan is retried per app (see
    /// `InactiveTabScanPolicy`), and restarting at 0 each time re-inspected the same ids that had already
    /// failed, so no number of retries could ever reach a long-lived app's windows. The caller owns the cursor.
    static func untrackedWindowsByBruteForce(_ pid: pid_t, excluding: Set<CGWindowID>, matching titles: [String],
                                             from startId: AXUIElementID = 0)
                                             -> (found: [(CGWindowID, AXUIElement, String)], nextId: AXUIElementID) {
        var seen = Set<CGWindowID>()
        var result = [(CGWindowID, AXUIElement, String)]()
        let titleSet = Set(titles)
        let nextId = bruteForceElements(pid, from: startId) { candidate, mayStartIpc in
            guard mayStartIpc(), let wid = try? candidate.cgWindowId(), wid != 0,
                  !excluding.contains(wid), !seen.contains(wid), mayStartIpc(),
                  let a = try? candidate.attributes([kAXSubroleAttribute, kAXTitleAttribute]),
                  a.subrole == kAXStandardWindowSubrole, let title = a.title, titleSet.contains(title) else { return false }
            seen.insert(wid)
            result.append((wid, candidate, title))
            return result.count >= titles.count
        }
        return (result, nextId)
    }
}

/// Actions
extension AXUIElement {
    /// Raise the window within its app's stack. Returns the raw AXError instead of throwing, so callers can
    /// react to `.invalidUIElement` (a stale element: the app silently rebuilt the window's accessibility node,
    /// #5586) by re-resolving and retrying, rather than silently no-opping.
    @discardableResult
    func raiseWindow() -> AXError {
        return AXUIElementPerformAction(self, kAXRaiseAction as CFString)
    }

    func setAttribute(_ key: String, _ value: Any) throws {
        try throwIfNotSuccess(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef))
    }

    func performAction(_ action: String) throws {
        try throwIfNotSuccess(AXUIElementPerformAction(self, action as CFString))
    }

    private static let tabGroupDirectChildPageSize = 64
    private static let tabButtonPageSize = 128
    private static let tabGroupTraversalBudgetMs: Double = 250

    /// Query the window's AXTabGroup child to detect OS-level tabs. Foreign AX arrays use bounded pages;
    /// an incomplete page, failed child read, or expired traversal is `.unknown`, never `.standalone`, because
    /// silence from a partial tree must not dissolve a group the app did not actually deny.
    ///
    /// **DIRECT children only, deliberately, and fullscreen windows are therefore not read here.** A
    /// fullscreen window's tab bar is reachable — probed at length — but only unevenly: Finder and Script
    /// Editor list the containing AXGroup as a child, Terminal and TextEdit do not (their tab bar lives in a
    /// separate NSToolbarFullScreenWindow that no downward walk reaches, only a coordinate hit-test).
    ///
    /// Descending one level was tried and REVERTED. It works, but it buys tab reading for SOME apps and not
    /// others, and that asymmetry is worse than the gap: a fullscreen active that can suddenly read its tabs
    /// reaches `matchSiblings`, where nothing stopped it claiming a windowed window's tab (the title matches
    /// under Finder's duplicate titles, and `positionsCompatible` waives the frame test for fullscreen) —
    /// a real window hidden, for a feature that is deliberately not needed. Fullscreen grouping is the
    /// geometry path's job: a fullscreen Space holds one window and its tabs, so the Space invariant plus
    /// Space-less-ness already identifies them.
    /// Returns the tab TITLES and the group's own identity (`TabGroupToken`), which is the `AXTabGroup`
    /// element's `AXUIElementID`. Every window of a group hands out the same one while it is the selected
    /// tab, so the token is a membership fact the titles can only guess at. The BUTTONS are deliberately not kept: they are rebuilt by ordinary tab
    /// operations (Finder rebuilds all of them on one Cmd+T) and each reports the SELECTED window's wid
    /// rather than its own, so a button is neither stable nor self-naming. Measured on Finder, Terminal and
    /// TextEdit.
    func tabGroupObservation(pid: pid_t) -> TabGroupObservation {
        let timer = LightweightTimer()
        let mayRead = { !timer.hasElapsed(milliseconds: Self.tabGroupTraversalBudgetMs) }
        var observation = TabGroupObservation.unknown
        var complete = true
        let result = walkChildren(pageSize: Self.tabGroupDirectChildPageSize, pid: pid, mayRead: mayRead) { child in
            guard let role = try? child.attributes([kAXRoleAttribute], pid: pid).role else {
                complete = false
                return false
            }
            guard role == "AXTabGroup" else { return false }
            var titles = [String]()
            let tabs = child.walkChildren(pageSize: Self.tabButtonPageSize, pid: pid, mayRead: mayRead) { tab in
                guard let attributes = try? tab.attributes([kAXSubroleAttribute, kAXTitleAttribute], pid: pid)
                    else { return nil }
                if attributes.subrole == "AXTabButton" { titles.append(attributes.title ?? "") }
                return false
            }
            if tabs == .complete {
                observation = titles.count >= 2 ? .group(titles: titles, token: child.id()) : .standalone
            }
            return true
        }
        return result == .complete && complete ? .standalone : observation
    }
}

/// tests have shown that this ID has a range going from 0 to probably UInt.MAX
/// it starts at 0 for each app, and increments over time, for each new UI element
/// this means that long-lived apps (e.g. Finder) may have high IDs
/// we don't know how high it can go, and if it wraps around
typealias AXUIElementID = UInt64

/// Why an AX call produced no answer. The two are handled differently by `AXCallScheduler`: only
/// `.appUnresponsive` is worth retrying. See `AXUIElement.throwIfNotSuccess`.
enum AxError: Error {
    /// `.cannotComplete` — the messaging timeout expired on a busy app. Retryable.
    case appUnresponsive
    /// any other AX error — a dead element, an unimplemented attribute, an app refusing the API. Permanent
    /// for this call: retrying re-asks a question that cannot be answered, and marking the app unresponsive
    /// for it quarantines a process that is answering fine.
    case noAnswer
}

struct AXAttributes {
    var title: String?
    var role: String?
    var subrole: String?
    var isMinimized: Bool?
    var isFullscreen: Bool?
    var isMain: Bool?
    var children: [AXUIElement]?
    var focusedWindow: AXUIElement?
    var mainWindow: AXUIElement?
    var closeButton: AXUIElement?
    var appIsRunning: Bool?
    var url: URL?
    var statusLabel: String?
    var windows: [AXUIElement]?
    var position: CGPoint?
    var size: CGSize?
}
