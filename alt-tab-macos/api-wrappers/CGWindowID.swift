import Cocoa
import Foundation

extension CGWindowID {
    func title() -> String? {
        return cgProperty("kCGSWindowTitle", String.self)
    }

    func screenshot() -> CGImage? {
        // CGSHWCaptureWindowList
        var windowId_ = self
        let options: CGSWindowCaptureOptions = [.captureIgnoreGlobalClipShape, .windowCaptureNominalResolution]
        let list = CGSHWCaptureWindowList(cgsMainConnectionId, &windowId_, 1, options) as! [CGImage]
        return list.first

//        // CGWindowListCreateImage
//        return CGWindowListCreateImage(.null, .optionIncludingWindow, self, [.boundsIgnoreFraming, .bestResolution])

//        // CGSCaptureWindowsContentsToRectWithOptions
//        var windowId_ = self
//        if Testt.sampleCgImage == nil {
//            Testt.sampleCgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, self, [.boundsIgnoreFraming, .bestResolution])!
//        }
//        var image = Testt.sampleCgImage!
//        CGSCaptureWindowsContentsToRectWithOptions(cgsMainConnectionId, &windowId_, true, .zero, [.windowCaptureNominalResolution, .captureIgnoreGlobalClipShape], &image)
//        return image
    }

    private func cgProperty<T>(_ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        CGSCopyWindowProperty(cgsMainConnectionId, self, key as CFString, &value)
        return value as? T
    }
}

//class Testt {
//    static var sampleCgImage: CGImage? = nil
//}
