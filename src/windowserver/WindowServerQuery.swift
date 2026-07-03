import Cocoa

/// The "one big SLS call": batch-query the WindowServer for a set of windows and read every field off the
/// returned iterator snapshot (no per-field IPC). Feeds the pure `WsWindowState` decoder. Impure (Mach IPC),
/// so no Specs/Tests triad — verified at runtime. MUST run off the main thread: the query blocks while the
/// WindowServer is busy (measured up to ~27ms during a Space transition vs ~84µs idle for the whole screen).
enum WindowServerQuery {
    /// Serializes query-vs-query on the shared `CGS_CONNECTION`. The `cgsCall` lane is 4-wide, so at launch the
    /// `windowCreated` burst can run several `discoverWindow` queries at once. The SkyLight query client keeps
    /// the snapshot buffer keyed to the connection and isn't reentrant on it: a second `SLSWindowQueryWindows`
    /// frees/reuses that buffer while another thread's `result`/`iterator` are still live, so ARC releasing the
    /// now-dangling snapshot crashes in `swift_unknownObjectRelease` (issue #5819). The whole read must be
    /// exclusive — locking only the `SLSWindowQueryWindows` call wouldn't help, since the corruption happens
    /// while the first query is still iterating. Only queries contend on this; the other `cgsCall` reads stay
    /// parallel. `query` calls nothing reentrant, so this can't deadlock.
    private static let queryLock = NSLock()

    /// One batched query → a decoded snapshot per wid. The iterator getters read the local snapshot the
    /// query returned, so the cost is one IPC for the batch, not one per field.
    static func query(_ wids: [CGWindowID]) -> [WsRawWindow] {
        guard !wids.isEmpty else { return [] }
        queryLock.lock()
        defer { queryLock.unlock() }
        let result = SLSWindowQueryWindows(CGS_CONNECTION, wids as CFArray, Int32(wids.count)).takeRetainedValue()
        let iterator = SLSWindowQueryResultCopyWindows(result).takeRetainedValue()
        var out: [WsRawWindow] = []
        out.reserveCapacity(wids.count)
        while SLSWindowIteratorAdvance(iterator) {
            out.append(WsRawWindow(
                wid: SLSWindowIteratorGetWindowID(iterator),
                pid: SLSWindowIteratorGetPID(iterator),
                attributes: SLSWindowIteratorGetAttributes(iterator),
                level: SLSWindowIteratorGetLevel(iterator),
                spaceTypeMask: SLSWindowIteratorGetSpaceTypeMask(iterator),
                title: SLSWindowIteratorCopyTitle(iterator)?.takeRetainedValue() as String? ?? "",
                bounds: SLSWindowIteratorGetBounds(iterator)
            ))
        }
        return out
    }
}
