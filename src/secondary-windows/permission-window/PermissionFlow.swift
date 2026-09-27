import Foundation

/// What macOS reports for one permission, plus the one state macOS has no opinion on: `.skipped`,
/// which records that the user chose to run without Screen Recording. `AccessibilityPermission`
/// never produces `.skipped`.
enum PermissionStatus {
    case granted
    case notGranted
    case skipped
}

/// Pure decisions for the first-run permissions window: which of the two steps the user is on, how
/// each step's card renders, and what the bottom bar offers. `PermissionFlow` is callable in tests
/// with no AppKit / TCC dependencies, so the sequencing is pinned independently of the views.
///
/// The window walks one step at a time. Only the live step shows its justification and its
/// before/after illustration; a finished step collapses to its title row and an upcoming step is a
/// greyed title row. That keeps exactly one thing on screen to act on.
///
/// The two steps are not equal. Accessibility is mandatory — AltTab cannot focus a window without
/// it, so the only alternative offered is quitting. Screen Recording is waivable: the user can
/// continue with app icons instead of window pictures, which is what `PermissionStatus.skipped`
/// records.
enum PermissionFlow {
    enum Step: Equatable {
        case accessibility
        case screenRecording
    }

    enum StepState: Equatable {
        /// Granted, or (Screen Recording only) waived. Collapsed to a title row.
        case done
        /// The step the user is on: justification and illustration are shown.
        case live
        /// Not reached yet. Collapsed to a greyed title row.
        case upcoming
    }

    /// The step the user is on, or `nil` when nothing is left to resolve and the window should close.
    /// Accessibility comes first because granting it is what lets AltTab run at all; Screen Recording
    /// only blocks while it is still `.notGranted` (`.skipped` resolves it just as `.granted` does).
    static func liveStep(accessibility: PermissionStatus, screenRecording: PermissionStatus) -> Step? {
        if accessibility != .granted { return .accessibility }
        if screenRecording == .notGranted { return .screenRecording }
        return nil
    }

    static func state(of step: Step, accessibility: PermissionStatus, screenRecording: PermissionStatus) -> StepState {
        if step == liveStep(accessibility: accessibility, screenRecording: screenRecording) { return .live }
        switch step {
            case .accessibility: return accessibility == .granted ? .done : .upcoming
            case .screenRecording: return screenRecording == .notGranted ? .upcoming : .done
        }
    }

    /// Whether the bottom bar offers "Continue without thumbnails". Only on the Screen Recording
    /// step: waiving Accessibility is not a thing, and once every step is resolved the window closes
    /// instead of offering anything.
    static func showsWaiveOption(accessibility: PermissionStatus, screenRecording: PermissionStatus) -> Bool {
        return liveStep(accessibility: accessibility, screenRecording: screenRecording) == .screenRecording
    }

    static func isComplete(accessibility: PermissionStatus, screenRecording: PermissionStatus) -> Bool {
        return liveStep(accessibility: accessibility, screenRecording: screenRecording) == nil
    }

    /// Whether a step's card offers to grant after all, next to its "Skipped" label. The window is
    /// reopened later from "Check permissions…", and that is where the user changes their mind. Not
    /// while Accessibility is missing: that step comes first.
    static func offersGrantAfterSkip(_ step: Step, accessibility: PermissionStatus, screenRecording: PermissionStatus) -> Bool {
        return step == .screenRecording && screenRecording == .skipped && accessibility == .granted
    }

    enum PrimaryAction: Equatable {
        case grant
        case close
    }

    /// The bottom bar's main button. At launch the window closes by itself once complete, so "Close"
    /// only shows when it was reopened from "Check permissions…".
    static func primaryAction(accessibility: PermissionStatus, screenRecording: PermissionStatus) -> PrimaryAction {
        return isComplete(accessibility: accessibility, screenRecording: screenRecording) ? .close : .grant
    }
}
