import Cocoa

/// Main-thread inventory of every WindowServer surface from the latest all-Space snapshot. Keeping this
/// separate from `Windows.byWindowId` is essential: a physical background-tab row is not yet a tracked
/// switch destination and must not prevent inactive-tab AX adoption from looking for it.
enum WindowSurfaceInventory {
    private(set) static var byWindowId = [CGWindowID: WsRawWindow]()
    private static var mutationSequence: UInt64 = 0
    private static var lastMutation = [CGWindowID: UInt64]()
    private static var lastProcessRemoval = [pid_t: UInt64]()
    private static var latestAppliedSnapshot: UInt64 = 0

    /// Whether a whole-machine sweep has ever landed here. Until it has, this holds only the handful of rows
    /// single-window discoveries happened to upsert, so it cannot answer "what else does this app have on
    /// screen?" — a question `Applications.discoverInactiveTabs` must not get a partial answer to (an empty
    /// `others` waves every candidate through). After the first `replace` it is a SUPERSET of the on-screen
    /// list: every app-level surface on every Space, not just the current one.
    private(set) static var hasFullSnapshot = false

    /// Stamp a full snapshot when it is issued, before its WindowServer call leaves main. A targeted upsert
    /// or removal that happens after this token must survive even when the older full answer lands later.
    static func beginSnapshot() -> UInt64 {
        mutationSequence += 1
        return mutationSequence
    }

    /// `issuedAt` defaults to a token taken right now, which is only right when the rows were fetched
    /// synchronously. The asynchronous caller must stamp its own with `beginSnapshot()` BEFORE its query
    /// leaves main, or a targeted mutation made while that query was in flight loses to the stale answer.
    static func replace(_ rows: [WsRawWindow], issuedAt: UInt64? = nil) {
        let issuedAt = issuedAt ?? beginSnapshot()
        guard issuedAt >= latestAppliedSnapshot else { return }
        latestAppliedSnapshot = issuedAt
        let answer = Dictionary(uniqueKeysWithValues: rows.map { ($0.wid, $0) })
        for (wid, row) in answer where (lastMutation[wid] ?? 0) <= issuedAt
            && (lastProcessRemoval[row.pid] ?? 0) <= issuedAt {
            byWindowId[wid] = row
            lastMutation[wid] = issuedAt
        }
        for wid in byWindowId.keys where answer[wid] == nil && (lastMutation[wid] ?? 0) <= issuedAt {
            byWindowId.removeValue(forKey: wid)
            lastMutation[wid] = issuedAt
        }
        hasFullSnapshot = true
    }

    /// The visible surfaces of one process, for the callers that need to reason about an app's own window
    /// layout. Returns nil before the first full sweep rather than a misleadingly short list.
    static func visibleSurfaces(pid: pid_t) -> [WsRawWindow]? {
        guard hasFullSnapshot else { return nil }
        return byWindowId.values.filter { $0.pid == pid && WsWindowState.isVisible($0) }
    }

    static func upsert(_ rows: [WsRawWindow]) {
        mutationSequence += 1
        for row in rows {
            byWindowId[row.wid] = row
            lastMutation[row.wid] = mutationSequence
        }
    }

    static func remove(pid: pid_t) {
        mutationSequence += 1
        lastProcessRemoval[pid] = mutationSequence
        for wid in byWindowId.values.filter({ $0.pid == pid }).map({ $0.wid }) {
            byWindowId.removeValue(forKey: wid)
            lastMutation[wid] = mutationSequence
        }
    }

    static func remove(_ wid: CGWindowID) {
        mutationSequence += 1
        byWindowId.removeValue(forKey: wid)
        lastMutation[wid] = mutationSequence
    }

    static func raw(_ wid: CGWindowID) -> WsRawWindow? {
        byWindowId[wid]
    }

    /// Follow WindowServer parent links while they stay inside one process. Cycles and missing/cross-process
    /// parents stop at the last trustworthy surface instead of inventing a relationship.
    static func representativeWid(_ wid: CGWindowID) -> CGWindowID {
        guard let first = byWindowId[wid] else { return wid }
        var current = first
        var visited = Set([wid])
        while current.parentWid != 0,
              !visited.contains(current.parentWid),
              let parent = byWindowId[current.parentWid], parent.pid == first.pid {
            visited.insert(parent.wid)
            current = parent
        }
        return current.wid
    }
}
