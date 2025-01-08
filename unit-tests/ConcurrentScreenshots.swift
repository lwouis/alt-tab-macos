//import XCTest
//
//import Cocoa
//import ScreenCaptureKit
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
//    static var window: SCWindow!
//    static var config: SCStreamConfiguration!
//
//    static func cleanup(_ expectation: XCTestExpectation) {
//        let timePassedInSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
//        print("cleanup", timePassedInSeconds)
//        expectation.fulfill()
//    }
//
//    static func start(_ expectation1: XCTestExpectation, _ expectation2: XCTestExpectation) {
//        pickWindowToScreenshot()
//        setup()
//        startTime = DispatchTime.now().uptimeNanoseconds
//        screenshotManyWindowsAsync(batchId, expectation1)
//        batchId += 1
//        screenshotManyWindowsAsync(batchId, expectation2)
//        batchId += 1
//    }
//
//    static func setup() {
//        if #available(macOS 14.0, *) {
//            SCShareableContent.getWithCompletionHandler { content, error in
//                window = (content?.windows.first { $0.windowID == wid })!
//            }
//            config = SCStreamConfiguration()
//            config.captureResolution = .best
//        }
//    }
//
//    static func pickWindowToScreenshot() {
//        let windows = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as! [CGWindow]
//        let window = windows.first { ($0[kCGWindowName] as? String) == "~" }
//        wid = window?[kCGWindowNumber] as? CGWindowID
//    }
//
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
//    static func screenshotManyWindowsAsync(_ batchId: Int, _ expectation: XCTestExpectation) {
//        (0..<100).forEach { _ in dispatchGroup.enter() }
//        dispatchGroup.notify(queue: .main) {
//            cleanup(expectation)
//        }
//        print("orchestrator start \(batchId)")
//        for taskId in 0..<100 {
//            DispatchQueue(label: "test", qos: .userInteractive).async {
//                //                Task {
//                print("task start \(batchId) \(taskId)")
//                screenshot()
//                print("task stop \(batchId) \(taskId)")
//                //                }
//            }
//        }
//        print("orchestrator stop \(batchId)")
//    }
//
//    static func privateApi() {
//        var windowId_ = wid!
//        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution]).takeRetainedValue() as! [CGImage]
//        print(list.first != nil)
//        dispatchGroup.leave()
//    }
//
//    static func publicApi() {
//        let image = CGWindowListCreateImage(.null, .optionIncludingWindow, wid!, [.boundsIgnoreFraming, .bestResolution])
//        print(image != nil)
//        dispatchGroup.leave()
//    }
//
//    static func screenCaptureKit() {
//        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
//        config.width = Int(window.frame.width)
//        config.height = Int(window.frame.height)
//        if #available(macOS 14.0, *) {
//            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: config) { image, _ in
//                print(image != nil)
//                dispatchGroup.leave()
//            }
//        }
//    }
//
//    // CGSHWCaptureWindowList: 1.9
//    // CGWindowListCreateImage: 1.6
//    // SCScreenshotManager.captureImage: 4.5
//    static func screenshot() {
//        //Thread.sleep(forTimeInterval: 10)//Double(Int.random(in: 1...5)))
////        privateApi()
////         publicApi()
//        screenCaptureKit()
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
////        fulfillment(of: [expectation1, expectation2], timeout: 100, enforceOrder: false)
//        wait(for: [expectation1, expectation2], timeout: 100)
////    }
//    }
//}
