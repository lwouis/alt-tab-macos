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
        case bumpFocusOrder          // became frontmost → MRU
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
            case .windowFocused: return .bumpFocusOrder
            case .windowOrderedIn, .windowOrderedOut: return .refreshVisibility
            case .windowAddedToSpace, .windowRemovedFromSpace: return .updateSpaceMembership
            case .spaceCurrentChanged, .activeSpaceChanged: return .spaceTransition
        }
    }

    /// The Space notifications carry an 8-byte spaceId + 4-byte wid, so membership is free (no follow-up
    /// query). Every other window notification carries only the 4-byte wid.
    static func payloadCarriesSpaceId(_ n: Notification) -> Bool {
        n == .windowAddedToSpace || n == .windowRemovedFromSpace
    }
}
