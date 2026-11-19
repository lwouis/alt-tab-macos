import XCTest

final class PermissionStartupTests: XCTestCase {
    private struct Permissions: CustomStringConvertible {
        var accessibility: PermissionStatus
        var recording: PermissionStatus
        var complete: Bool { accessibility == .granted && recording != .notGranted }
        var description: String { "\(accessibility)/\(recording)" }
    }

    /// The main queue and the permission-check queue advance only when a test explicitly runs them.
    /// These are action-boundary tests: macOS replies and AppKit effects are replaced, not the gate.
    private final class Session {
        var permissions = Permissions(accessibility: .notGranted, recording: .notGranted)
        var started = false
        var starts = 0
        var shows = 0
        var visible = false
        var retries = 0
        var checkPending = false
        var main: [() -> Void] = []
        var violations: [String] = []

        func check() {
            guard !started else { return }
            PermissionStartup(
                isComplete: { self.permissions.complete },
                hasStarted: { self.started },
                enqueue: { self.main.append($0) },
                start: {
                    if self.started || !self.permissions.complete { self.violations.append("started twice or without permission") }
                    self.started = true
                    self.starts += 1
                    self.visible = false
                },
                showWindow: {
                    if self.started || self.permissions.complete { self.violations.append("showed an obsolete window") }
                    self.shows += 1
                    self.visible = true
                },
                checkAgain: {
                    self.retries += 1
                    self.checkPending = true
                }
            ).check()
        }

        func publish(_ permissions: Permissions) {
            self.permissions = permissions
            check()
        }

        func runMain(_ count: Int = 1) {
            for _ in 0..<count {
                guard !main.isEmpty else { return }
                main.removeFirst()()
            }
        }

        func runRetry() {
            guard checkPending else { return }
            checkPending = false
            check()
        }

        func settle() {
            for _ in 0..<32 {
                guard !main.isEmpty || checkPending else { return }
                runMain()
                runRetry()
            }
            violations.append("queues did not settle")
        }
    }

    private let allowed = Permissions(accessibility: .granted, recording: .granted)
    private let missing = Permissions(accessibility: .notGranted, recording: .notGranted)
    private let axMissing = Permissions(accessibility: .notGranted, recording: .granted)
    private let screenMissing = Permissions(accessibility: .granted, recording: .notGranted)
    private let waived = Permissions(accessibility: .granted, recording: .skipped)

    func testMissingPermissionKeepsAUsableWindow() {
        for permissions in [missing, axMissing, screenMissing, Permissions(accessibility: .notGranted, recording: .skipped)] {
            let s = Session()
            s.publish(permissions)
            XCTAssertFalse(s.visible)
            s.settle()
            XCTAssertTrue(s.visible, "\(permissions)")
            XCTAssertEqual(s.starts, 0)
            XCTAssertEqual(s.violations, [])
        }
    }

    func testGrantOrWaiverBeforePresentationSuppressesOldWindowAndStarts() {
        for resolved in [allowed, waived] {
            let s = Session()
            s.publish(screenMissing)
            s.publish(resolved)
            s.runMain()
            XCTAssertEqual(s.shows, 0)
            XCTAssertEqual(s.starts, 0, "The old presentation must not take over startup")
            s.settle()
            XCTAssertEqual(s.starts, 1)
            XCTAssertFalse(s.visible)
            XCTAssertEqual(s.violations, [])
        }
    }

    func testGrantRevokeGrantWithSeveralPendingChecksStartsOnlyOnce() {
        for revoked in [axMissing, screenMissing, missing] {
            let s = Session()
            for permissions in [missing, allowed, revoked, allowed, allowed] { s.publish(permissions) }
            s.settle()
            XCTAssertEqual(s.starts, 1)
            XCTAssertEqual(s.shows, 0)
            XCTAssertFalse(s.visible)
            XCTAssertEqual(s.violations, [])
        }
    }

    func testRevocationBeforeQueuedStartupRetriesAndKeepsWindow() {
        for revoked in [axMissing, screenMissing] {
            let s = Session()
            s.publish(allowed)
            s.permissions = revoked
            s.runMain()
            XCTAssertEqual(s.starts, 0)
            XCTAssertEqual(s.retries, 1, "A changed result must schedule a fresh check, even before another notification")
            XCTAssertTrue(s.checkPending)
            s.runRetry()
            s.settle()
            XCTAssertTrue(s.visible, "\(revoked)")
            XCTAssertEqual(s.starts, 0)
            s.publish(allowed)
            s.settle()
            XCTAssertEqual(s.starts, 1)
            XCTAssertFalse(s.visible)
            XCTAssertEqual(s.violations, [])
        }
    }

    func testRegrantWhileRetryIsPendingUsesLatestPermission() {
        let s = Session()
        s.publish(allowed)
        s.permissions = axMissing
        s.runMain()
        XCTAssertTrue(s.checkPending)
        s.permissions = allowed
        s.runRetry()
        s.settle()
        XCTAssertEqual(s.starts, 1)
        XCTAssertEqual(s.shows, 0)
        XCTAssertEqual(s.violations, [])
    }

    func testPendingRetryAfterAnotherCheckStartsDoesNotStartAgain() {
        let s = Session()
        s.publish(allowed)
        s.permissions = axMissing
        s.runMain()
        s.publish(allowed)
        s.runMain()
        XCTAssertEqual(s.starts, 1)
        s.runRetry()
        s.settle()
        XCTAssertEqual(s.starts, 1)
        XCTAssertEqual(s.violations, [])
    }

    func testEachPermissionCanChangeSeparatelyBeforePresentation() {
        for first in [axMissing, screenMissing] {
            let s = Session()
            s.publish(missing)
            s.publish(first)
            s.runMain()
            XCTAssertTrue(s.visible, "One grant must not hide a still-required step")
            XCTAssertEqual(s.starts, 0)
            s.publish(allowed)
            s.settle()
            XCTAssertEqual(s.starts, 1)
            XCTAssertFalse(s.visible)
            XCTAssertEqual(s.violations, [])
        }
    }

    func testUndoWaiverBeforeStartupDoesNotStartWithoutScreenPermission() {
        let s = Session()
        s.publish(screenMissing)
        s.publish(waived)
        s.publish(screenMissing)
        s.settle()
        XCTAssertEqual(s.starts, 0)
        XCTAssertTrue(s.visible)
        s.publish(waived)
        s.settle()
        XCTAssertEqual(s.starts, 1)
        XCTAssertFalse(s.visible)
        XCTAssertEqual(s.violations, [])
    }

    func testOldPresentationDoesNotReopenWindowAfterStartupEvenIfRevoked() {
        for latest in [allowed, axMissing, screenMissing, waived] {
            let s = Session()
            s.publish(missing)
            s.started = true
            s.permissions = latest
            s.settle()
            XCTAssertEqual(s.shows, 0, "Post-startup revocation belongs to recovery, not a queued startup window")
            XCTAssertEqual(s.starts, 0)
            XCTAssertEqual(s.violations, [])
        }
    }

    private enum Action: String { case result, main, retry }

    private func explore(_ results: [Permissions], _ actions: [Action] = []) -> Int {
        let s = Session()
        defer { s.main.removeAll() }
        var nextResult = 0
        for action in actions {
            switch action {
                case .result:
                    s.publish(results[nextResult])
                    nextResult += 1
                case .main: s.runMain()
                case .retry: s.runRetry()
            }
        }
        let trace = "\(results); \(actions.map { $0.rawValue })"
        guard actions.count < 20 else {
            XCTFail("Queues did not settle: \(trace)")
            return 0
        }
        var branches = 0
        if nextResult < results.count { branches += explore(results, actions + [.result]) }
        if !s.main.isEmpty { branches += explore(results, actions + [.main]) }
        if s.checkPending { branches += explore(results, actions + [.retry]) }
        guard branches == 0 else { return branches }
        XCTAssertEqual(s.violations, [], trace)
        XCTAssertLessThanOrEqual(s.starts, 1, trace)
        if s.started {
            XCTAssertFalse(s.visible, trace)
        } else {
            XCTAssertFalse(s.permissions.complete, "Resolved permissions stranded startup: \(trace)")
            XCTAssertTrue(s.visible, "Missing permissions stranded the user without a window: \(trace)")
        }
        return 1
    }

    func testAllInterleavingsOfThreeResultsAndBothQueues() {
        let states = [missing, axMissing, screenMissing, allowed, waived,
                      Permissions(accessibility: .notGranted, recording: .skipped)]
        var schedules = 0
        for first in states {
            for second in states {
                for third in states { schedules += explore([first, second, third]) }
            }
        }
        XCTAssertEqual(schedules, 1616)
    }
}
