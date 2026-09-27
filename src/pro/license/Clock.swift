import Foundation

protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date {
        #if DEBUG
        if QaLifecycleEnvironment.enabled, let now = QaLifecycleEnvironment.now { return now }
        #endif
        return Date()
    }
}

#if DEBUG
/// Shared by the app and its unit-test target; opt-in only for a UUID-scoped live QA session.
enum QaLifecycleEnvironment {
    static let session = CommandLine.arguments.first { $0.hasPrefix("--qa-lifecycle-session=") }
        .flatMap { UUID(uuidString: String($0.dropFirst("--qa-lifecycle-session=".count)))?.uuidString }
    static var enabled: Bool { session != nil }
    static var now: Date?
    static var namespace: String { "\(App.bundleIdentifier).qa.lifecycle.\(session!)" }
}
#endif
