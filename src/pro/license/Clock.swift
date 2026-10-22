import Foundation

protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date {
        #if DEBUG
        if let now = QaLifecycleEnvironment.visualNow { return now }
        if QaLifecycleEnvironment.enabled, let now = QaLifecycleEnvironment.now { return now }
        return Date(timeIntervalSinceNow: QaLifecycleEnvironment.menuClockOffset)
        #else
        return Date()
        #endif
    }
}

#if DEBUG
/// Shared by the app and its unit-test target; opt-in only for a UUID-scoped live QA session.
enum QaLifecycleEnvironment {
    static let session = CommandLine.arguments.first { $0.hasPrefix("--qa-lifecycle-session=") }
        .flatMap { UUID(uuidString: String($0.dropFirst("--qa-lifecycle-session=".count)))?.uuidString }
    static var enabled: Bool { session != nil }
    static var now: Date?
    /// Visual captures use a fixed local date so trial text does not change with the day of the run.
    static var visualNow: Date?
    /// Set by the QA menu's day and time controls. Unlike `now`, the clock keeps ticking, so timers fire.
    static var menuClockOffset: TimeInterval = 0
    static var namespace: String { "\(App.bundleIdentifier).qa.lifecycle.\(session!)" }
}
#endif
