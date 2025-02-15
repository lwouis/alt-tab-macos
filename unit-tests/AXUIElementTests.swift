//import XCTest
//
//final class ImageScalingTests: XCTestCase {
//    /// average: 0.021
//    func testWindowsByBruteForce1000() throws {
//        measure(options: options) {
//            let _ = windowsByBruteForce(721)
//        }
//    }
//
//    /// average: 0.042
//    func testWindowsByBruteForceData() throws {
//        measure(options: options) {
//            let _ = windowsByBruteForceData(721)
//        }
//    }
//
//    /// average: 0.040
//    /// average: 0.019 without CFDataCreate
//    func testWindowsByBruteForceUint8() throws {
//        measure(options: options) {
//            var pid = pid_t(721)
//            let _ = windowsByBruteForceUint8(&pid)
//        }
//    }
//
//    func testRangeToBruteForce() {
//        // all windows is empty
//        XCTAssertEqual(Windows.rangeToBruteForce([], []), nil)
//        XCTAssertEqual(Windows.rangeToBruteForce([], [2, 3]), nil)
//        // all windows are known
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 3, 4, 5]), nil)
//        // no known window helps us narrow the range
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], []), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [3]), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [3, 4]), [nil, nil])
//        // some known windows are not in allWindows
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [1]), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [6]), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [1, 2, 3]), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [1, 2, 3, 4, 5, 6]), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 3, 4, 5, 6]), [nil, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [1, 2, 3, 4, 5]), [nil, nil])
//        // only start is narrowed
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2]), [2, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 4]), [2, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 3]), [3, nil])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 3, 4]), [4, nil])
//        // only end is narrowed
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [5]), [nil, 5])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [3, 5]), [nil, 5])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [4, 5]), [nil, 4])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [3, 4, 5]), [nil, 3])
//        // start and end are narrowed
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 5]), [2, 5])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 3, 5]), [3, 5])
//        XCTAssertEqual(Windows.rangeToBruteForce([2, 3, 4, 5], [2, 4, 5]), [2, 4])
//    }
//
//    private var options: XCTMeasureOptions = {
//        let o = XCTMeasureOptions()
//        o.iterationCount = 10
//        return o
//    }()
//}
//
//class Windows {
////    static func CGWindowIDRangeToAXUIElementIDRange(_ range: [CGWindowID?]) -> Range<AXUIElementID> {
//////        print(range)
////        var start = AXUIElementID(0)
////        var end = AXUIElementID(1000)
////        if let startCGWindowID = range[0],
////           let startAXUIElementID = (Windows.list.first { $0.cgWindowId == startCGWindowID }!.axUiElement.id()) {
////            start = startAXUIElementID
////        }
////        if let endCGWindowID = range[1],
////           let endAXUIElementID = (Windows.list.first { $0.cgWindowId == endCGWindowID }!.axUiElement.id()) {
////            end = endAXUIElementID
////        } else {
////            end = start + 1000
////        }
////        let range2 = start..<end
//////        print(range2)
////        return range2
////    }
//
//    static func rangeToBruteForce(_ allWindowIds: [CGWindowID], _ knownWindowIds: [CGWindowID]) -> [CGWindowID?]? {
//        if allWindowIds.isEmpty {
//            return nil
//        }
//        if knownWindowIds.isEmpty {
//            return [nil, nil]
//        }
//        let allSorted = allWindowIds.sorted()
//        let knownSorted = knownWindowIds.sorted()
//        if knownSorted.first! < allSorted.first! || knownSorted.last! > allSorted.last! {
//            Logger.error("we track some windows, yet they are not returned by CGWindowListCopyWindowInfo")
//            return [nil, nil]
//        }
//        if allSorted.count == knownSorted.count {
//            var same = true
//            for i in 0..<allSorted.count {
//                if allSorted[i] != knownSorted[i] {
//                    same = false
//                }
//            }
//            if same {
//                return nil
//            }
//        }
//        var startIsShared = knownSorted.first! == allSorted.first!
//        let endIsShared = knownSorted.last! == allSorted.last!
//        if !startIsShared && !endIsShared {
//            return [nil, nil]
//        }
//        var start: CGWindowID? = nil
//        var end: CGWindowID? = endIsShared ? allSorted.last! : nil
//        for windowId in allSorted {
//            if startIsShared {
//                if knownSorted.contains(windowId) {
//                    start = windowId
//                } else {
//                    startIsShared = false
//                }
//            }
//            if endIsShared {
//                if knownSorted.contains(windowId) {
//                    if windowId < end! {
//                        end = windowId
//                    }
//                } else {
//                    end = allSorted.last!
//                }
//            }
//        }
//        return [start, end]
//    }
//}
//
//func windowsByBruteForce(_ pid: pid_t) -> [AXUIElement] {
//    // we use this to call _AXUIElementCreateWithRemoteToken; we reuse the object for performance
//    // tests showed that this remoteToken is 20 bytes: 4 + 4 + 4 + 8; the order of bytes matters
//    var remoteToken = Data(count: 20)
//    remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
//    remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
//    remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
//    var axWindows = [AXUIElement]()
//    // we iterate to 1000 as a tradeoff between performance, and missing windows of long-lived processes
//    for axUiElementId: AXUIElementID in 0..<1000 {
//        remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axUiElementId) { Data($0) })
//        if let axUiElement = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue(),
//           let subrole = try? axUiElement.subrole(),
//           [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
//            axWindows.append(axUiElement)
//        }
//    }
//    return axWindows
//}
//
//func windowsByBruteForceData(_ pid: pid_t) -> [AXUIElement] {
//    // we use this to call _AXUIElementCreateWithRemoteToken; we reuse the object for performance
//    // tests showed that this remoteToken is 20 bytes: 4 + 4 + 4 + 8; the order of bytes matters
//    var remoteToken = Data(count: 20)
//    remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
//    remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
//    remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
//    let axWindows = [AXUIElement]()
//    // we iterate to 1000 as a tradeoff between performance, and missing windows of long-lived processes
//    for axUiElementId: AXUIElementID in 0..<100000 {
//        remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axUiElementId) { Data($0) })
////        if let axUiElement = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue(),
////           let subrole = try? axUiElement.subrole(),
////           [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
////            axWindows.append(axUiElement)
////        }
//    }
//    return axWindows
//}
//
//func windowsByBruteForceUint8(_ pid: inout pid_t) -> [AXUIElement] {
//    // we use this to call _AXUIElementCreateWithRemoteToken; we reuse the object for performance
//    // tests showed that this remoteToken is 20 bytes: 4 + 4 + 4 + 8; the order of bytes matters
//    var tid = Int32(0x636f636f)
//    var remoteToken = [UInt8](repeating: 0, count: 20)
//    var dataCursor = 0
//    memcpy(&remoteToken[dataCursor], &pid, MemoryLayout<UInt32>.size)
//    dataCursor += MemoryLayout<UInt32>.size
//    memset(&remoteToken[dataCursor], 0, MemoryLayout<UInt32>.size)
//    dataCursor += MemoryLayout<UInt32>.size
//    memcpy(&remoteToken[dataCursor], &tid, MemoryLayout<Int32>.size)
//    dataCursor += MemoryLayout<Int32>.size
//    let axWindows = [AXUIElement]()
//    // we iterate to 1000 as a tradeoff between performance, and missing windows of long-lived processes
//    for var axUiElementId: AXUIElementID in 0..<100000 {
//        memcpy(&remoteToken[dataCursor], &axUiElementId, MemoryLayout<AXUIElementID>.size);
//        let _ = CFDataCreate(kCFAllocatorDefault, remoteToken, remoteToken.count)
////           let axUiElement = _AXUIElementCreateWithRemoteToken(cfdata)?.takeRetainedValue(),
////           let subrole = try? axUiElement.subrole(),
////           [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
////            axWindows.append(axUiElement)
//    }
//    return axWindows
//}
//
//typealias AXUIElementID = UInt
//
//enum AxError: Error {
//    case runtimeError
//}
//
//@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
//func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?
//
//extension AXUIElement {
//    func axCallWhichCanThrow<T>(_ result: AXError, _ successValue: inout T) throws -> T? {
//        switch result {
//            case .success: return successValue
//            // .cannotComplete can happen if the app is unresponsive; we throw in that case to retry until the call succeeds
//            case .cannotComplete: throw AxError.runtimeError
//            // for other errors it's pointless to retry
//            default: return nil
//        }
//    }
//
//    func attribute<T>(_ key: String, _ _: T.Type) throws -> T? {
//        var value: AnyObject?
//        return try axCallWhichCanThrow(AXUIElementCopyAttributeValue(self, key as CFString, &value), &value) as? T
//    }
//
//    func subrole() throws -> String? {
//        return try attribute(kAXSubroleAttribute, String.self)
//    }
//}