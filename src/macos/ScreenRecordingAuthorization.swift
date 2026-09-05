import Foundation

enum ScreenRecordingProbeFailure: Equatable {
    case timeout
    case screenCaptureKit(domain: String, code: Int)
}

enum ScreenRecordingProbeResult: Equatable {
    case granted
    case notGranted
    case temporarilyUnavailable(ScreenRecordingProbeFailure)
}

enum ScreenRecordingAuthorizationState: Equatable {
    case unknown
    case granted
    case temporarilyUnavailable
    case needsUserReview
}

enum ScreenRecordingAuthorizationEffect: Equatable {
    case persistGrant
    case scheduleConfirmation(after: TimeInterval)
    case cancelConfirmations
    case openOnboarding
    case showPassiveReview
}

struct ScreenRecordingAuthorizationModel {
    private(set) var state: ScreenRecordingAuthorizationState
    private(set) var wasGranted: Bool
    private var failedChecks = 0

    init(wasGranted: Bool) {
        self.wasGranted = wasGranted
        state = wasGranted ? .granted : .unknown
    }

    mutating func receive(_ result: ScreenRecordingProbeResult) -> [ScreenRecordingAuthorizationEffect] {
        switch result {
            case .granted:
                let mustPersist = !wasGranted
                wasGranted = true
                failedChecks = 0
                state = .granted
                return (mustPersist ? [.persistGrant] : []) + [.cancelConfirmations]
            case .notGranted where !wasGranted && state == .unknown:
                state = .needsUserReview
                return [.openOnboarding]
            case .notGranted, .temporarilyUnavailable:
                failedChecks += 1
                if failedChecks >= 3 {
                    state = .needsUserReview
                    return [.showPassiveReview]
                }
                state = .temporarilyUnavailable
                return failedChecks == 1
                    ? [.scheduleConfirmation(after: 10), .scheduleConfirmation(after: 30)]
                    : []
        }
    }
}
