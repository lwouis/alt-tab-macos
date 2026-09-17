import Foundation

/// The canonical, test-constructible data record of an `Application`. Plain value type, no OS handles
/// — held as a stored `var state: ApplicationState` on the live `Application` class (mutated in place
/// when KVO / AX notifications fire), and constructed directly in tests. The switcher's logic kernels
/// take `ApplicationState` instead of `Application`, so they're hostless / AppKit-free.
struct ApplicationState: Equatable {
    var pid: pid_t
    var bundleIdentifier: String?
    var localizedName: String?
    var isHidden: Bool
}

enum ApplicationAdmissionEvidence: Equatable {
    case discovery
    case attention
}

enum ApplicationAdmissionResolver {
    /// The process that draws the desktop chrome on macOS 13+: the wallpaper, the Stage Manager strip and
    /// the Mission Control overlays. It owns no window a user can switch to, so nothing about it is worth
    /// an accessibility observer or an acquisition scan, and a click on its surfaces (the desktop) names no
    /// window. It answers accessibility with nothing, so without this rule every inventory pass spent three
    /// 250ms brute-force scans on its wallpaper surface alone, whose size passes the physical gate and whose
    /// level does not reject it (`WindowAdmissionResolver.shouldAcquireSemantics`).
    static let windowManagerBundleId = "com.apple.WindowManager"

    static func accepts(isXpc: Bool, isZombie: Bool, isKnownUserFacingException: Bool,
                        isWindowManager: Bool = false, evidence: ApplicationAdmissionEvidence) -> Bool {
        guard !isZombie, !isWindowManager else { return false }
        return !isXpc || isKnownUserFacingException || evidence == .attention
    }
}

/// What a `.discovery` refusal remembered about the process it refused, so the verdict can be reused
/// instead of re-bought. The bundle id is the whole payload: it is the guard against pid reuse.
struct RefusedApplication: Equatable {
    let bundleId: String?
}

/// May `Applications.findOrCreate` answer from a remembered refusal instead of asking the OS again?
///
/// **The fast path in `findOrCreate` is the app list, which only ever holds ACCEPTED apps.** A refused pid
/// is never added to it, so every inventory sweep re-bought the same verdict: `GetProcessForPID`,
/// `GetProcessInformation` and a `sysctl` zombie probe, per refused pid, forever. Measured over one live pass:
/// 8,978 classifications, of which a single `ThemeWidgetControlViewService` accounted for 1,072 and a single
/// `CursorUIViewService` for 708, every one of them reaching the same answer.
///
/// Two rules, and both are load-bearing:
///   - **Only a `.discovery` refusal is reusable.** `ApplicationAdmissionResolver` admits an XPC process the
///     user has actually gone to, so the same process is refused under `.discovery` and accepted under
///     `.attention`. An attention lookup that inherited the discovery refusal would drop the window the user
///     just clicked.
///   - **The bundle id must still match.** macOS reuses pids, and a refusal that outlived its process would
///     make a real app permanently invisible — the worst shape of bug this could have, since nothing about
///     it points at a cache. A different process wearing the same number has a different bundle id, misses,
///     and is asked properly. One reused by a process with the SAME bundle id inherits a verdict that is
///     correct for it anyway.
enum ApplicationVerdictCache {
    static func refusalStillAnswers(_ recorded: RefusedApplication?, bundleId: String?,
                                    evidence: ApplicationAdmissionEvidence) -> Bool {
        guard evidence == .discovery, let recorded else { return false }
        return recorded.bundleId == bundleId
    }
}

/// Only `.regular` apps get a placeholder row. An accessory app with no window is a menubar agent, and
/// having been frontmost doesn't make it one the user can switch back to: Raycast's palette and
/// CoreServicesUIAgent's Gatekeeper alert both activate their process, then leave a process whose only
/// surfaces are auxiliary. Pinned by `testAccessoryApplicationNeverGetsPlaceholder`.
enum WindowlessApplicationResolver {
    static func shouldCreate(isRegular: Bool, isTerminated: Bool, hasExistingPlaceholder: Bool,
                             hasNonPhantomWindow: Bool) -> Bool {
        guard !isTerminated, !hasExistingPlaceholder, !hasNonPhantomWindow else { return false }
        return isRegular
    }
}
