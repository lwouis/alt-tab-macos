import Cocoa
import Foundation

extension CGWindowID {
    func AXUIElementApplication(_ ownerPid: pid_t) -> AXUIElement {
        return AXUIElementCreateApplication(ownerPid)
    }

    func AXUIElementOfOtherSpaceWindow(_ axApp: AXUIElement) -> AXUIElement? {
        CGSAddWindowsToSpaces(cgsMainConnectionId, [self], [Spaces.currentSpaceId])
        let axWindow = axApp.window(self)
        CGSRemoveWindowsFromSpaces(cgsMainConnectionId, [self], [Spaces.currentSpaceId])
        return axWindow
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
}

//class Testt {
//    static var sampleCgImage: CGImage? = nil
//}
