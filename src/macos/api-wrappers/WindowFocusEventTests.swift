import CoreGraphics
import XCTest

final class WindowFocusEventTests: XCTestCase {
    private func records(windowId: CGWindowID = 0x1234_5678) -> [[UInt8]] {
        var records = [[UInt8]]()
        WindowFocusEvent.post(windowId: windowId) { pointer in
            records.append(Array(UnsafeBufferPointer(start: pointer, count: WindowFocusEvent.bufferSize)))
        }
        return records
    }

    private func read<T>(_ record: [UInt8], at offset: Int, as type: T.Type) -> T {
        record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: type) }
    }

    func testEveryFocusPostsADownFollowedByAnUp() {
        let events = records()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map { read($0, at: 0x08, as: UInt32.self) }, [1, 2])
    }

    func testGlobalAndWindowCoordinatesAreFiniteAndOutsideContent() {
        for record in records() {
            for offset in [0x10, 0x20] {
                let point = read(record, at: offset, as: CGPoint.self)
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                XCTAssertEqual(point, CGPoint(x: 300_000, y: 300_000))
            }
        }
    }

    func testBothEdgesTargetTheSameWindow() {
        for record in records() {
            XCTAssertEqual(read(record, at: 0x3C, as: UInt32.self), 0x1234_5678)
            XCTAssertEqual(record[0x3A], 0x10)
        }
    }

    func testRecordLengthKeepsTheWindowServerReadPaddingZeroed() {
        for record in records() {
            XCTAssertEqual(record.count, 0x100)
            XCTAssertEqual(read(record, at: 0x04, as: UInt32.self), 0xF8)
            XCTAssertTrue(record[0xF8 ..< 0x100].allSatisfy { $0 == 0 })
        }
    }

    func testReleaseChangesOnlyTheEventType() {
        let events = records()
        var release = events[1]
        release[0x08] = events[0][0x08]
        XCTAssertEqual(release, events[0])
    }

    func testUnsignedWindowIdIsNotTruncated() {
        for record in records(windowId: UInt32.max) {
            XCTAssertEqual(read(record, at: 0x3C, as: UInt32.self), UInt32.max)
        }
    }

    func testNextFocusStartsWithANewMouseDown() {
        let first = records(windowId: 1)
        let second = records(windowId: 2)
        XCTAssertEqual(first.map { $0[0x08] }, [1, 2])
        XCTAssertEqual(second.map { $0[0x08] }, [1, 2])
        XCTAssertEqual(read(second[0], at: 0x3C, as: UInt32.self), 2)
    }
}
