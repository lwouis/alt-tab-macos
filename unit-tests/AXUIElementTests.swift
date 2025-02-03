//import XCTest
//
//final class ImageScalingTests: XCTestCase {
//    /// 20ms
//    func testWindowsByBruteForce() throws {
//        measure(options: options) {
//            let _ = windowsByBruteForce(41414)
//        }
//    }
//
//    private var options: XCTMeasureOptions = {
//        let o = XCTMeasureOptions()
//        o.iterationCount = 10
//        return o
//    }()
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