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
