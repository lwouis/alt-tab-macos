import XCTest
import Foundation

final class ProcessLivenessTests: XCTestCase {

    func testOwnPidIsAlive() {
        XCTAssertTrue(getpid().isAlive())
    }

    func testReapedPidIsNotAlive() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        XCTAssertFalse(child.processIdentifier.isAlive())
    }

    func testUnsignalableProcessIsAlive() {
        XCTAssertTrue(pid_t(1).isAlive(), "launchd exists; EPERM must read as alive")
    }

    func testNonPositivePidIsNotAlive() {
        XCTAssertFalse(pid_t(-1).isAlive())
        XCTAssertFalse(pid_t(0).isAlive())
    }

    func testZombieIsAliveButZombie() throws {
        var pid = pid_t()
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup("/usr/bin/true"), nil]
        defer { argv.forEach { free($0) } }
        XCTAssertEqual(posix_spawn(&pid, "/usr/bin/true", nil, nil, &argv, environ), 0)
        // exited but not reaped: poll for the zombie state instead of waiting, since waiting reaps
        let deadline = Date().addingTimeInterval(5)
        while !pid.isZombie() && Date() < deadline { usleep(5_000) }
        XCTAssertTrue(pid.isZombie())
        XCTAssertTrue(pid.isAlive(), "a zombie still exists to the kernel; isZombie is the separate question")
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        XCTAssertFalse(pid.isAlive())
    }
}
