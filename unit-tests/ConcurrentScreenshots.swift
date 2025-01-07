//import XCTest
//
//import Cocoa
//
//@_silgen_name("CGSMainConnectionID")
//func CGSMainConnectionID() -> CGSConnectionID
//
//let CGS_CONNECTION = CGSMainConnectionID()
//typealias CGSConnectionID = UInt32
//typealias CGSSpaceID = UInt64
//
//struct CGSWindowCaptureOptions: OptionSet {
//    let rawValue: UInt32
//    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
//    // on a retina display, 1px is spread on 4px, so nominalResolution is 1/4 of bestResolution
//    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
//    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
//}
//
//@_silgen_name("CGSHWCaptureWindowList")
//func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: inout CGWindowID, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> Unmanaged<CFArray>
//
//typealias CGWindow = [CFString: Any]
//
//class Playground {
//    static var batchId = 0
//    static var startTime: UInt64!
//    static var wid: CGWindowID!
//    static let dispatchGroup = DispatchGroup()
//    static let dispatchSemaphore = DispatchSemaphore(value: 8)
//    // DispatchQueue.global()
//    //     1: 21.4
//    //     2: 11.2
//    //     3: 8.1
//    //     5: 6.5 // 3.2
//    //     8: 5.9  // 3.1
//    //     10: 5.5 // 3.0
//    //     15: 5.2 // 3.3
//    //     20: 5.2
//    //     30: 5.2
//    //     40: 5.2
//    //     50: 5.6
//    //     60: 10.7
//    //     no-cap: 93 // 93.3
//    // custom-concurrent-queue no-cap: 91.3
//    // custom DispatchQueue (serial)
//    //     no-cap: 5.1 // 3.2
//    //     no-cap qos:.userInteractive: 6.0
//    //     no-cap qos:.userInteractive autoreleaseFrequency:.inherit: 6.0
//    //     no-cap qos:.userInteractive autoreleaseFrequency:.workItem: 5.9
//    //     no-cap qos:.userInteractive autoreleaseFrequency:.never: 6.3
//    // no second queue. Only 1 global() queue in dispatchTasksThenCleanup: 11 // 3.3
//    // no second queue. Only 1 DispatchQueue (serial) in dispatchTasksThenCleanup: 12.2
//
//    static func dispatchTasksThenCleanup(_ batchId: Int,  _ expectation: XCTestExpectation) {
//        DispatchQueue.init(label: "test").async {
//            print("orchestrator start \(batchId)")
//            for taskId in 0..<100 {
////                dispatchSemaphore.wait()
////                DispatchQueue.global().async {
//                    defer {
////                        dispatchSemaphore.signal()
//                        dispatchGroup.leave()
//                    }
//                    dispatchGroup.enter()
//                    print("task start \(batchId) \(taskId)")
//                    task(batchId, taskId)
//                    print("task stop \(batchId) \(taskId)")
////                }
//            }
//            dispatchGroup.notify(queue: .main) {
//                cleanup(expectation)
//            }
//            print("orchestrator stop \(batchId)")
//        }
//    }
//
//    static func start(_ expectation1: XCTestExpectation, _ expectation2: XCTestExpectation) {
//        let windows = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as! [CGWindow]
//        let window = windows.first { ($0[kCGWindowName] as? String) == "~" }
//        wid = window?[kCGWindowNumber] as? CGWindowID
//        startTime = DispatchTime.now().uptimeNanoseconds
//        dispatchTasksThenCleanup(batchId, expectation1)
//        batchId += 1
//        dispatchTasksThenCleanup(batchId, expectation2)
//        batchId += 1
//    }
//
//    static func task(_ batchId: Int, _ taskId: Int) {
//        //Thread.sleep(forTimeInterval: 10)//Double(Int.random(in: 1...5)))
//        let _ = screenshot()
//    }
//
//    static func cleanup(_ expectation: XCTestExpectation) {
//        let timePassedInSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
//        print("cleanup", timePassedInSeconds)
//        expectation.fulfill()
//    }
//
//    static func screenshot() -> CGImage? {
//        print("CGSHWCaptureWindowList start")
//        var windowId_ = wid!
//        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution]).takeRetainedValue() as! [CGImage]
//        print(list.first != nil)
//        return list.first
////        let windowId_ = wid!
////        let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowId_, [.boundsIgnoreFraming, .bestResolution])
////        print(image != nil)
////        return image
//    }
//}
//
//final class ConcurrentScreenshots: XCTestCase {
//    func testBench() throws {
////        let options = XCTMeasureOptions()
////        options.iterationCount = 1
////        self.measure(options: options) {
//        let expectation1 = XCTestExpectation()
//        let expectation2 = XCTestExpectation()
//        Playground.start(expectation1, expectation2)
//        wait(for: [expectation1, expectation2], timeout: 100)
////    }
//    }
//}
