import Cocoa

/// Off-main scheduler for blocking WindowServer / SkyLight reads (`CGS*`, `CGWindowList*`). Sibling of
/// `AXCallScheduler` (Accessibility) and `ProcessCallScheduler` (process & sysctl) — the three front doors
/// for blocking SDK calls.
///
/// The raw SDK functions are `fileprivate` here, so call sites can't make a naive main-thread call: they go
/// through a use-case method that runs the work OFF the main thread on a bounded, QoS'd queue (no thread
/// explosion; OS threads reused via GCD). Two shapes per use-case:
/// - `useCase(args, thenMain:)` — caller is ON main: dispatch off-main, deliver the result on main.
/// - `useCase(args) -> T` — caller is ALREADY off-main: run inline; `dispatchPrecondition(.notOnQueue(.main))`
///   turns a misuse from main into a loud debug crash.
class CGSCallScheduler {
    // isolated from the AX event-read pools so a slow WindowServer query can't starve focused-window reads.
    // Carries ALL blocking WindowServer/SkyLight reads, including the bulk SLSWindowQueryWindows discovery
    // snapshot + per-window state queries (moved off the AX pools, B4). 4-wide so a show's Space + discovery
    // + phantom reads can overlap; still bounded — see BackgroundWork's thread-count budget.
    private static let queue = LabeledOperationQueue("cgsCall", .userInitiated, 4)

    #if DEBUG
    // read-only handle for the "Live queue graph" sampler (DebugMenu); keeps `queue` private otherwise
    static var debugQueue: LabeledOperationQueue { queue }
    #endif

    /// Run an arbitrary blocking WindowServer/SkyLight read off-main on this lane (isolated from the AX
    /// pools). For the multi-call reads — the bulk discovery snapshot + Space topology + per-window state
    /// query — that dispatch their own result back to main. Fire-and-forget; callers may be on any thread.
    static func run(_ block: @escaping () -> Void) {
        queue.addOperation(block)
    }

    /// The Space(s) a window currently belongs to. Fetched off-main, delivered on main.
    static func windowSpaces(_ wid: CGWindowID, thenMain: @escaping ([CGSSpaceID]) -> Void) {
        queue.addOperation {
            let spaceIds = rawWindowSpaces(wid)
            DispatchQueue.main.async { thenMain(spaceIds) }
        }
    }

    /// Synchronous form for callers ALREADY off-main: the Space(s) a single window belongs to. Used by the
    /// #5791 backfill (a window the per-Space enumeration misses would otherwise get empty spaceIds).
    static func windowSpaces(_ wid: CGWindowID) -> [CGSSpaceID] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return rawWindowSpaces(wid)
    }

    /// Which of `wids` still exist (CGWindowListCreateDescriptionFromArray — a targeted lookup of exactly
    /// these wids, NOT a Space-scoped enumeration, so it can't false-negative on other-Space windows). `nil`
    /// = the query failed, so the caller must treat existence as unknown and NOT discard. Fetched off-main.
    static func existingWindowIds(among wids: [CGWindowID], thenMain: @escaping (Set<CGWindowID>?) -> Void) {
        queue.addOperation {
            let alive = rawExistingWindowIds(wids)
            DispatchQueue.main.async { thenMain(alive) }
        }
    }

    /// The on-screen window ids in the given Spaces, top-most first (CGSCopyWindowsWithOptionsAndTags).
    /// Self-dispatching form for callers ON main.
    static func windowsInSpaces(_ spaceIds: [CGSSpaceID], thenMain: @escaping ([CGWindowID]) -> Void) {
        queue.addOperation {
            let wids = rawWindowsInSpaces(spaceIds, true)
            DispatchQueue.main.async { thenMain(wids) }
        }
    }

    /// Synchronous form for callers ALREADY off-main (e.g. inside another scheduler's block).
    static func windowsInSpaces(_ spaceIds: [CGSSpaceID], _ includeInvisible: Bool = true) -> [CGWindowID] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return rawWindowsInSpaces(spaceIds, includeInvisible)
    }
}

// Raw SkyLight / CGWindowList calls — fileprivate so the only way to reach them is through a use-case.
fileprivate func rawWindowSpaces(_ wid: CGWindowID) -> [CGSSpaceID] {
    return CGSCopySpacesForWindows(CGS_CONNECTION, CGSSpaceMask.all.rawValue, [wid] as CFArray) as! [CGSSpaceID]
}

fileprivate func rawExistingWindowIds(_ wids: [CGWindowID]) -> Set<CGWindowID>? {
    let rawIds: CFArray = wids.map { UnsafeRawPointer(bitPattern: UInt($0)) }.withUnsafeBufferPointer {
        CFArrayCreate(nil, UnsafeMutablePointer(mutating: $0.baseAddress), $0.count, nil)
    }
    guard let descriptions = CGWindowListCreateDescriptionFromArray(rawIds) as? [[CFString: Any]] else { return nil }
    return Set(descriptions.compactMap { $0[kCGWindowNumber] } as? [CGWindowID] ?? [])
}

fileprivate func rawWindowsInSpaces(_ spaceIds: [CGSSpaceID], _ includeInvisible: Bool) -> [CGWindowID] {
    var set_tags = ([] as CGSCopyWindowsTags).rawValue
    var clear_tags = ([] as CGSCopyWindowsTags).rawValue
    var options = [.screenSaverLevel1000] as CGSCopyWindowsOptions
    if includeInvisible {
        options = [options, .invisible1, .invisible2]
    }
    return CGSCopyWindowsWithOptionsAndTags(CGS_CONNECTION, 0, spaceIds as CFArray, options.rawValue, &set_tags, &clear_tags) as! [CGWindowID]
}
