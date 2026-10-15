import Foundation

/// A cancelled history read must stay cancelled even if the session becomes available again before it completes.
final class ProPromptPresentation {
    private var generation = UInt64(0)
    private var timeout: DispatchWorkItem?
    private let scheduleTimeout: (DispatchWorkItem) -> Void
    private(set) var isPending = false

    init(scheduleTimeout: @escaping (DispatchWorkItem) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: $0)
    }) {
        self.scheduleTimeout = scheduleTimeout
    }

    func cancel() {
        generation += 1
        isPending = false
        timeout?.cancel()
        timeout = nil
    }

    func load<Value>(using load: (@escaping (Value) -> Void) -> Void,
                     fallback: Value? = nil,
                     canPresent: @escaping () -> Bool, show: @escaping (Value) -> Void) {
        cancel()
        guard canPresent() else { return }
        let request = generation
        isPending = true
        let finish: (Value) -> Void = { [weak self] value in
            guard let self, self.generation == request, self.isPending else { return }
            self.isPending = false
            self.timeout?.cancel()
            self.timeout = nil
            guard canPresent(), self.generation == request else { return }
            show(value)
        }
        if let fallback {
            let item = DispatchWorkItem { finish(fallback) }
            timeout = item
            scheduleTimeout(item)
        }
        load(finish)
    }

    struct Context {
        var sessionAvailable = true
        var isPro = false
        var switcherActive = false
        var onboarding = false
        var competingUI = false
        var fullscreen = false
        var optedOut = false
        var messageToday = false

        var canPresentProactively: Bool {
            sessionAvailable && !switcherActive && !onboarding && !competingUI && !fullscreen
        }

        func allows(userInitiated: Bool, blockedFeaturePopover: Bool = false) -> Bool {
            guard sessionAvailable, !isPro, (!switcherActive || blockedFeaturePopover), !onboarding else { return false }
            return userInitiated || (canPresentProactively && !optedOut && !messageToday)
        }
    }
}
