import XCTest

final class StartupRecoveryPolicyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testBudgetSurvivesNewInstancesAndStopsAfterThirdFailure() throws {
        XCTAssertEqual(try StartupRecoveryStore(directory: directory).recordFailure().retryDelay, 1)
        XCTAssertEqual(try StartupRecoveryStore(directory: directory).recordFailure().retryDelay, 3)
        XCTAssertNil(try StartupRecoveryStore(directory: directory).recordFailure().retryDelay)
        for _ in 0..<4 {
            let record = try StartupRecoveryStore(directory: directory).recordFailure()
            XCTAssertEqual(record.failures, 3)
            XCTAssertNil(record.retryDelay)
        }
    }

    func testManualRetryStartsANewBudget() throws {
        let store = StartupRecoveryStore(directory: directory)
        for _ in 0..<3 { _ = try store.recordFailure() }
        try store.retryManually()
        XCTAssertEqual(try StartupRecoveryStore(directory: directory).recordFailure().retryDelay, 1)
    }

    func testOnlyUnchangedFailureCanBeClearedByAStableInstance() throws {
        let store = StartupRecoveryStore(directory: directory)
        let first = try store.recordFailure()
        let newer = try StartupRecoveryStore(directory: directory).recordFailure()
        try store.clear(ifUnchanged: first.generation)
        XCTAssertEqual(try store.read(), newer)
        try store.clear(ifUnchanged: newer.generation)
        XCTAssertNil(try store.read())
    }

    func testCorruptRecordDoesNotRestoreAutomaticRetries() throws {
        let store = StartupRecoveryStore(directory: directory)
        _ = try store.recordFailure()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("startup-recovery.json"))
        XCTAssertThrowsError(try store.recordFailure())
        try store.retryManually()
        XCTAssertEqual(try store.recordFailure().failures, 1)
    }

    func testOutOfRangeRecordFailsClosed() throws {
        let store = StartupRecoveryStore(directory: directory)
        _ = try store.recordFailure()
        for count in [-1, 0, 4, Int.max] {
            let bytes = try JSONEncoder().encode(StartupRecoveryRecord(failures: count, generation: UUID()))
            try bytes.write(to: directory.appendingPathComponent("startup-recovery.json"))
            XCTAssertThrowsError(try store.recordFailure())
        }
    }

    func testStorageFailureCannotAuthorizeARestart() throws {
        try Data().write(to: directory)
        XCTAssertThrowsError(try StartupRecoveryStore(directory: directory).recordFailure())
    }

    func testConcurrentInstancesCannotLoseFailureCounts() throws {
        let lock = NSLock()
        var records = [StartupRecoveryRecord]()
        var errors = [Error]()
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do {
                let record = try StartupRecoveryStore(directory: directory).recordFailure()
                lock.lock(); records.append(record); lock.unlock()
            } catch { lock.lock(); errors.append(error); lock.unlock() }
        }
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(records.filter { $0.retryDelay != nil }.count, 2)
        XCTAssertEqual(try StartupRecoveryStore(directory: directory).read()?.failures, 3)
    }

    func testRepeatedFailureNotificationsAreHandledOncePerProcess() {
        var policy = StartupRecoveryPolicy()
        XCTAssertTrue(policy.beginFailure())
        XCTAssertFalse(policy.beginFailure())
        policy.becameReady(at: 0)
        XCTAssertFalse(policy.canClear(at: 1000))
    }

    func testClearNeedsOneMinuteAfterReadyNotAfterProcessLaunch() {
        var policy = StartupRecoveryPolicy()
        XCTAssertFalse(policy.canClear(at: 1000))
        policy.becameReady(at: 1000)
        XCTAssertFalse(policy.canClear(at: 1059.99))
        XCTAssertTrue(policy.canClear(at: 1060))
        XCTAssertFalse(policy.canClear(at: 900))
    }

    func testFailureDuringTheStableIntervalCancelsReset() {
        var policy = StartupRecoveryPolicy()
        policy.becameReady(at: 100)
        XCTAssertTrue(policy.beginFailure())
        XCTAssertFalse(policy.canClear(at: 160))
    }
}
