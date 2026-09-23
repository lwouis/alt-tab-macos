import XCTest

/// Drives `StapledTicket.park` / `restore` against a fake bundle in a temporary folder. See StapledTicketSpecs.md.
final class StapledTicketTests: XCTestCase {
    private var bundle: URL!
    private let ticket = Data("s8ch".utf8) + Data([1, 0, 0, 0, 0xF0, 0x05])

    override func setUpWithError() throws {
        bundle = FileManager.default.temporaryDirectory.appendingPathComponent("StapledTicketTests-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Resources/en.lproj"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: contents.path)
        try? FileManager.default.removeItem(at: bundle)
    }

    private var contents: URL { bundle.appendingPathComponent("Contents") }
    private var stapled: URL { StapledTicket.stapledUrl(bundle) }
    private var parked: URL { StapledTicket.parkedUrl(bundle) }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// The release shape: the ticket where `stapler` put it goes to the path the seal omits, bytes intact.
    func testParkMovesTheTicketToTheUnsealedPath() throws {
        try ticket.write(to: stapled)
        XCTAssertEqual(StapledTicket.park(bundle), .moved)
        XCTAssertFalse(exists(stapled))
        XCTAssertEqual(try Data(contentsOf: parked), ticket)
    }

    func testRestorePutsTheTicketBackWhereStaplerPutIt() throws {
        try ticket.write(to: stapled)
        _ = StapledTicket.park(bundle)
        XCTAssertEqual(StapledTicket.restore(bundle), .moved)
        XCTAssertFalse(exists(parked))
        XCTAssertEqual(try Data(contentsOf: stapled), ticket)
    }

    /// Debug and QA builds are not notarized, so they have nothing to move and must not log a failure.
    func testABundleWithoutTicketHasNothingToDo() {
        XCTAssertEqual(StapledTicket.park(bundle), .nothingToDo)
        XCTAssertEqual(StapledTicket.restore(bundle), .nothingToDo)
    }

    /// Creating `en.lproj` would add a language to the app, so without it the ticket stays stapled.
    func testParkNeverCreatesTheLanguageFolder() throws {
        try FileManager.default.removeItem(at: parked.deletingLastPathComponent())
        try ticket.write(to: stapled)
        XCTAssertEqual(StapledTicket.park(bundle), .nothingToDo)
        XCTAssertTrue(exists(stapled))
        XCTAssertFalse(exists(parked.deletingLastPathComponent()))
    }

    /// A future build could ship a real `locversion.plist`; parking must not replace it.
    func testParkNeverOverwritesAFileAlreadyAtTheParkingPath() throws {
        let plist = Data("<plist/>".utf8)
        try plist.write(to: parked)
        try ticket.write(to: stapled)
        XCTAssertEqual(StapledTicket.park(bundle), .nothingToDo)
        XCTAssertEqual(try Data(contentsOf: parked), plist)
        XCTAssertEqual(try Data(contentsOf: stapled), ticket)
    }

    /// Only a ticket is ever moved into the conventional path, so a real `locversion.plist` stays put.
    func testRestoreIgnoresAFileThatIsNotATicket() throws {
        try Data("<plist/>".utf8).write(to: parked)
        XCTAssertEqual(StapledTicket.restore(bundle), .nothingToDo)
        XCTAssertFalse(exists(stapled))
    }

    func testRestoreNeverOverwritesAStapledTicket() throws {
        try ticket.write(to: stapled)
        try ticket.write(to: parked)
        XCTAssertEqual(StapledTicket.restore(bundle), .nothingToDo)
        XCTAssertTrue(exists(stapled))
        XCTAssertTrue(exists(parked))
    }

    /// A crash or forced exit skips the restore. The next launch finds nothing to park and the next quit
    /// restores the ticket, so the bundle heals itself on the following normal quit.
    func testATicketLeftParkedByACrashIsRestoredAtTheNextQuit() throws {
        try ticket.write(to: stapled)
        XCTAssertEqual(StapledTicket.park(bundle), .moved)
        XCTAssertEqual(StapledTicket.park(bundle), .nothingToDo)
        XCTAssertEqual(StapledTicket.restore(bundle), .moved)
        XCTAssertEqual(try Data(contentsOf: stapled), ticket)
    }

    /// An install AltTab cannot write to (another account's, a read-only volume) keeps its ticket stapled.
    func testAReadOnlyBundleKeepsItsTicketStapled() throws {
        try ticket.write(to: stapled)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: contents.path)
        XCTAssertEqual(StapledTicket.park(bundle), .failed(EACCES))
        XCTAssertTrue(exists(stapled))
    }
}
