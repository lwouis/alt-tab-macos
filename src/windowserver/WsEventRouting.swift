import Cocoa

/// Pure classification of WindowServer connection-notification ids into the model action each implies, and
/// what their payload carries. The id→meaning map was established empirically on macOS 26 (registering a
/// wide id range, then driving window lifecycle/focus/space changes) — see `WsEventRoutingSpecs.md`. Holds
/// no state; `WindowServerEvents` turns these decisions into model mutations.
enum WsEventRouting {
    /// The WindowServer notifications AltTab acts on (raw ids confirmed live).
    enum Notification: UInt32, CaseIterable {
        case windowCreated = 811
        case windowDestroyed = 804
        case windowMoved = 806
        case windowResized = 807
        case windowOrderedIn = 815
        case windowOrderedOut = 816
        case windowFocused = 808
        case windowAddedToSpace = 1325
        case windowRemovedFromSpace = 1326
        case spaceCurrentChanged = 1329
        case activeSpaceChanged = 1401
    }

    /// What the model should do. The wid (and Space, where applicable) come from the notify-proc payload.
    enum Action: Equatable {
        case acquireAndDiscriminate  // possibly-untracked wid → get its AX element + decide if it's a real window
        case remove                  // window gone
        case updateGeometry          // moved/resized → refresh bounds
        case noteFocusEvent          // the WindowServer says this window came forward (808)
        case refreshVisibility       // ordered in/out → re-read minimized/visible (minimize isn't its own event)
        case updateSpaceMembership   // payload carries (spaceId, wid)
        case spaceTransition         // current/active Space changed
    }

    static func notification(_ raw: UInt32) -> Notification? {
        Notification(rawValue: raw)
    }

    static func action(for n: Notification) -> Action {
        switch n {
            case .windowCreated: return .acquireAndDiscriminate
            case .windowDestroyed: return .remove
            case .windowMoved, .windowResized: return .updateGeometry
            case .windowFocused: return .noteFocusEvent
            case .windowOrderedIn, .windowOrderedOut: return .refreshVisibility
            case .windowAddedToSpace, .windowRemovedFromSpace: return .updateSpaceMembership
            case .spaceCurrentChanged, .activeSpaceChanged: return .spaceTransition
        }
    }
}

/// Ordered ingress buffer for the WindowServer notify proc. Move/resize reports only say "read the latest
/// geometry", so repeated reports for one wid are interchangeable until a semantic edge intervenes. Focus,
/// order, lifecycle and Space events split segments and are never coalesced or reordered.
struct WsEventIngress {
    struct Event: Equatable {
        let notification: WsEventRouting.Notification
        let w0: UInt32
        let space: UInt64
        let widInSpace: UInt32
        let at: TimeInterval
    }

    struct Drain: Equatable {
        let events: [Event]
        let coalescedGeometryEvents: Int
    }

    private struct GeometryKey: Hashable {
        let segment: UInt64
        let wid: UInt32
    }

    private var events = [Event]()
    private var geometryIndexes = [GeometryKey: Int]()
    private var segment: UInt64 = 0
    private var coalescedGeometryEvents = 0

    mutating func append(_ event: Event) {
        guard event.notification == .windowMoved || event.notification == .windowResized else {
            events.append(event)
            segment &+= 1
            return
        }
        let key = GeometryKey(segment: segment, wid: event.w0)
        if let index = geometryIndexes[key] {
            events[index] = event
            coalescedGeometryEvents += 1
        } else {
            geometryIndexes[key] = events.count
            events.append(event)
        }
    }

    mutating func drain() -> Drain {
        let result = Drain(events: events, coalescedGeometryEvents: coalescedGeometryEvents)
        self = WsEventIngress()
        return result
    }
}
