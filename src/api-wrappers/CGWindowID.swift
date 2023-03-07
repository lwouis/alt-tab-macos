import Cocoa

extension CGWindowID {
    func title() -> String? {
        cgProperty("kCGSWindowTitle", String.self)
    }

    func level() throws -> CGWindowLevel {
        var level = CGWindowLevel(0)
        CGSGetWindowLevel(cgsMainConnectionId, self, &level)
        // in some weird cases, a window can spawn with level == 1, which is not even a publicly listed level
        if level == 1 {
            throw AxError.runtimeError
        }
        return level
    }

    func spaces() -> [CGSSpaceID] {
        return CGSCopySpacesForWindows(cgsMainConnectionId, CGSSpaceMask.all.rawValue, [self] as CFArray) as! [CGSSpaceID]
    }

    func screenshot(_ bestResolution: Bool = false) -> CGImage? {
        // CGSHWCaptureWindowList
        var windowId_ = self
        let list = CGSHWCaptureWindowList(cgsMainConnectionId, &windowId_, 1, [.ignoreGlobalClipShape, bestResolution ? .bestResolution : .nominalResolution]).takeRetainedValue() as! [CGImage]
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
