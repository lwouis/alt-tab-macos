import Foundation

/// Pure decision for a single click on an override segmented control / radio button / switch.
/// `OverrideClickResolver.decide` is callable in tests with no AppKit / Preferences / UserDefaults
/// dependencies, so we can pin the override state-machine semantics against regressions.
enum OverrideClickDecision: Equatable {
    /// The click landed on the currently-displayed value — leave override state untouched.
    /// (User clicked the already-selected segment / toggled to its current state.)
    case skip
    /// The click changed the displayed value — set the override to `value`.
    case write(value: String)
}

enum OverrideClickResolver {
    /// Override-control state machine:
    ///   - Override is either SET or UNSET. The displayed value follows the override when SET,
    ///     and follows the global value when UNSET.
    ///   - Clicking the currently-DISPLAYED value is a no-op (`.skip`) regardless of whether the
    ///     override is set. The only way to UNSET an override is the link button.
    ///   - Clicking ANY OTHER value writes the override (`.write`), even if that value happens
    ///     to equal the global. Override SET state and override VALUE are independent: once a
    ///     user has explicitly chosen a value for a shortcut, that shortcut stops auto-tracking
    ///     the global, even if the override value coincidentally matches the global.
    static func decide(
        newIndex: Int,
        hasOverride: Bool,
        storedOverrideValue: String?,
        globalIndex: Int,
        valueAtIndex: (Int) -> String
    ) -> OverrideClickDecision {
        let displayedIndex: Int
        if hasOverride {
            displayedIndex = Int(storedOverrideValue ?? "") ?? -1
        } else {
            displayedIndex = globalIndex
        }
        if newIndex == displayedIndex {
            return .skip
        }
        return .write(value: valueAtIndex(newIndex))
    }
}
