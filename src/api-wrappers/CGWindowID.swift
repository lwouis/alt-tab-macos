import Cocoa

extension CGWindowID {
    func title() -> String? {
        cgProperty("kCGSWindowTitle", String.self)
    }

    func level() -> CGWindowLevel {
        var level = CGWindowLevel(0)
        CGSGetWindowLevel(CGS_CONNECTION, self, &level)
        return level
    }

    func spaces() -> [CGSSpaceID] {
        return CGSCopySpacesForWindows(CGS_CONNECTION, CGSSpaceMask.all.rawValue, [self] as CFArray) as! [CGSSpaceID]
    }

    func screenshot() -> CGImage? {
        // we use CGSHWCaptureWindowList because it can screenshot minimized windows, which CGWindowListCreateImage can't
        var windowId_ = self
        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]).takeRetainedValue() as! [CGImage]
        return list.first
//        // CGWindowListCreateImage
//        return CGWindowListCreateImage(.null, .optionIncludingWindow, self, [.boundsIgnoreFraming, .bestResolution])
//
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
        CGSCopyWindowProperty(CGS_CONNECTION, self, key as CFString, &value)
        return value as? T
    }
}
