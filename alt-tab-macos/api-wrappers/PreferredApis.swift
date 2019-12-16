import Cocoa
import Foundation

enum WindowScreenshotApi {
    case CGWindowListCreateImage
    case CGSHWCaptureWindowList
    case CGSCaptureWindowsContentsToRectWithOptions
}

enum WindowDimensionsApi {
    case AXValueGetValue
    case SLSGetWindowBounds
}

enum FocusWindowApi {
    case AXUIElementPerformAction
    case _SLPSSetFrontProcessWithOptions
}

let cgsMainConnectionId = CGSMainConnectionID()

// This class wraps different public and private APIs that achieve similar functionality.
// It lets the user pick the API as a parameter, and thus the level of service they want
class PreferredApis {
    static func windowScreenshot(_ windowId: CGSWindowID, _ api: WindowScreenshotApi) -> CGImage {
        switch api {
        case .CGWindowListCreateImage:
            return CGWindowListCreateImage(.null, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .bestResolution])!
        case .CGSHWCaptureWindowList:
            var windowId_ = windowId
            let options = CGSWindowCaptureOptions(kCGSCaptureIgnoreGlobalClipShape | kCGSWindowCaptureNominalResolution)
            return (CGSHWCaptureWindowList(cgsMainConnectionId, &windowId_, 1, options)!.takeRetainedValue() as! Array<CGImage>).first!
        case .CGSCaptureWindowsContentsToRectWithOptions:
            var windowId_ = windowId
            var windowImage: Unmanaged<CGImage>?
            CGSCaptureWindowsContentsToRectWithOptions(cgsMainConnectionId, &windowId_, true, .zero, (1 << 8), &windowImage)
            return windowImage!.takeRetainedValue()
        }
    }

    static func windowDimensions(_ windowId: CGSWindowID?, _ axUiElement: AXUIElement?, _ api: WindowDimensionsApi) -> CGSize {
        switch api {
        case .AXValueGetValue:
            return AccessibilityApis.value(axUiElement!, kAXSizeAttribute, CGSize(), .cgSize)!
        case .SLSGetWindowBounds:
            var windowId_ = windowId!
            var frame = CGRect()
            SLSGetWindowBounds(cgsMainConnectionId, &windowId_, &frame);
            return frame.size
        }
    }

    static func focusWindow(_ axUiElement: AXUIElement, _ windowId: CGSWindowID?, _ ownerPid: Int32?, _ api: FocusWindowApi) -> Void {
        DispatchQueue.global(qos: .userInteractive).async {
            switch api {
            case .AXUIElementPerformAction:
                NSRunningApplication(processIdentifier: ownerPid!)?.activate(options: [.activateIgnoringOtherApps])
                AccessibilityApis.focus(axUiElement)
            case ._SLPSSetFrontProcessWithOptions:
                var elementConnection = UInt32.zero
                SLSGetWindowOwner(cgsMainConnectionId, windowId!, &elementConnection)
                var psn = ProcessSerialNumber()
                SLSGetConnectionPSN(elementConnection, &psn)
                _SLPSSetFrontProcessWithOptions(&psn, windowId!, SLPSMode(kCPSUserGenerated))
                window_manager_make_key_window(&psn, windowId!)
                AccessibilityApis.focus(axUiElement)
            }
        }
    }
}
