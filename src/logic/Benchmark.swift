import Foundation

final class BenchmarkRunner {
    static let launchDuration = 10000
    static let startupDelay = 5000
    static let showDuration = 500
    static let hideDuration = 500
    static let shortcutIndex = 0
    private static var config: BenchmarkConfig?
    private static var remainingCycles = 0

    static func configureFromArgs(_ args: [String]) {
        config = BenchmarkConfig.parse(args)
    }

    static func startIfNeeded() {
        guard let config else { return }
        switch config.mode {
        case .launch:
            scheduleTerminate(after: launchDuration)
        case .showUi(let count):
            remainingCycles = count
            scheduleShow(after: startupDelay)
        }
    }

    private static func scheduleShow(after delay: Int) {
        guard remainingCycles > 0 else { scheduleTerminate(after: hideDuration); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
            App.showUi(shortcutIndex)
            scheduleHide(after: showDuration)
        }
    }

    private static func scheduleHide(after delay: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
            App.hideUi()
            remainingCycles -= 1
            scheduleShow(after: hideDuration)
        }
    }

    private static func scheduleTerminate(after delay: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
            App.shared.terminate(nil)
        }
    }
}

struct BenchmarkConfig {
    enum Mode {
        case launch
        case showUi(Int)
    }

    let mode: Mode

    static func parse(_ args: [String]) -> BenchmarkConfig? {
        guard let index = args.firstIndex(of: "--benchmark"), index + 1 < args.count else { return nil }
        let mode = args[index + 1]
        if mode == "launch" { return BenchmarkConfig(mode: .launch) }
        if mode == "showUi" { return parseShowUi(args, index) }
        print("Unsupported benchmark mode: \(mode)")
        return nil
    }

    private static func parseShowUi(_ args: [String], _ index: Int) -> BenchmarkConfig? {
        guard index + 2 < args.count, let count = Int(args[index + 2]), count > 0 else {
            print("Invalid benchmark showUi count")
            return nil
        }
        return BenchmarkConfig(mode: .showUi(count))
    }
}
