import XCTest

final class PreferencesPersistenceProbeTests: XCTestCase {
    private func facts(_ suite: String, exists: Bool, isSymlink: Bool, isWritable: Bool) -> PreferencesPersistenceProbe.SuiteFacts {
        PreferencesPersistenceProbe.SuiteFacts(suiteName: suite, plistPath: "/Users/x/Library/Preferences/\(suite).plist", exists: exists, isSymlink: isSymlink, isWritable: isWritable)
    }

    func testEmptyIsOk() {
        XCTAssertEqual(PreferencesPersistenceProbe.verdict([]), .ok)
    }

    func testAbsentFilesAreOk() {
        // Fresh install: no plist on disk yet. Even with a stray isWritable=false, absent must be OK.
        let f = [
            facts("a", exists: false, isSymlink: false, isWritable: true),
            facts("b", exists: false, isSymlink: true, isWritable: false),
        ]
        XCTAssertEqual(PreferencesPersistenceProbe.verdict(f), .ok)
    }

    func testWritableRegularFilesAreOk() {
        let f = [
            facts("a", exists: true, isSymlink: false, isWritable: true),
            facts("b", exists: true, isSymlink: false, isWritable: true),
        ]
        XCTAssertEqual(PreferencesPersistenceProbe.verdict(f), .ok)
    }

    func testSymlinkIsBroken() {
        let f = [facts("a", exists: true, isSymlink: true, isWritable: true)]
        XCTAssertEqual(PreferencesPersistenceProbe.verdict(f),
            .broken(symlinkedPaths: ["/Users/x/Library/Preferences/a.plist"], unwritablePaths: []))
    }

    func testUnwritableRegularFileIsBroken() {
        let f = [facts("a", exists: true, isSymlink: false, isWritable: false)]
        XCTAssertEqual(PreferencesPersistenceProbe.verdict(f),
            .broken(symlinkedPaths: [], unwritablePaths: ["/Users/x/Library/Preferences/a.plist"]))
    }

    func testSymlinkWinsOverWritability() {
        // A symlink whose link node also reports non-writable is classified as symlinked only.
        let f = [facts("a", exists: true, isSymlink: true, isWritable: false)]
        XCTAssertEqual(PreferencesPersistenceProbe.verdict(f),
            .broken(symlinkedPaths: ["/Users/x/Library/Preferences/a.plist"], unwritablePaths: []))
    }

    func testMixedSuitesReportSeparately() {
        let f = [
            facts("ok", exists: true, isSymlink: false, isWritable: true),
            facts("link", exists: true, isSymlink: true, isWritable: true),
            facts("root", exists: true, isSymlink: false, isWritable: false),
            facts("absent", exists: false, isSymlink: false, isWritable: true),
        ]
        XCTAssertEqual(PreferencesPersistenceProbe.verdict(f),
            .broken(symlinkedPaths: ["/Users/x/Library/Preferences/link.plist"],
                    unwritablePaths: ["/Users/x/Library/Preferences/root.plist"]))
    }
}
