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

    // fullscreen has multiple windows
    // e.g. Notes.app has a toolbar window and a main window
    // We need to composite these window images
    func fullScreenshot(_ win: Window) -> CGImage? {
        var height: CGFloat = 0;
        var width: CGFloat = 0;
        var imageMap = [(CGWindow, CGImage)]()
        var maxWidthWindowId: CGWindowID = 0
        let screen = Spaces.spaceFrameMap.first { $0.0 == win.spaceId }!.1
        var windowsInSpaces = Spaces.windowsInSpaces([win.spaceId]) // The returned windows are sorted from highest to lowest according to the z-index
        var windowsToCapture: [CGWindow] = []
        // find current app's window in the fullscreen space
        for item in windowsInSpaces {
            let cgWin = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionIncludingWindow], item) as! [CGWindow]
            guard cgWin.first!.isNotMenubarOrOthers(),
                  cgWin.first!.ownerPID() == win.application.runningApplication.processIdentifier,
                  cgWin.first!.bounds() != nil,
                  let bounds = CGRect(dictionaryRepresentation: cgWin.first!.bounds()!), bounds.height > 0, bounds.width > 0 else { continue }
            windowsToCapture.append(cgWin.first!)
        }
        // Drawing images from lowest to highest base on the z-index
        windowsToCapture = windowsToCapture.reversed()
        for item in windowsToCapture {
            let bounds = CGRect(dictionaryRepresentation: item.bounds()!)
            if width < bounds!.width {
                maxWidthWindowId = item.id()!
            }
            var windowId = item.id()!
            let list = CGSHWCaptureWindowList(cgsMainConnectionId, &windowId, 1, [.ignoreGlobalClipShape, .nominalResolution]).takeRetainedValue() as! [CGImage]
            imageMap.append((item, list.first!))
        }
        let bytesPerRow = imageMap.first { $0.0.id()! == maxWidthWindowId }!.1.bytesPerRow
        var context = CGContext.init(data: nil,
                width: Int(screen.frame.width),
                height: Int(screen.frame.height),
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: imageMap.first!.1.colorSpace!,
                bitmapInfo: imageMap.first!.1.bitmapInfo.rawValue)
        // composite these window images
        for item in imageMap {
            let bounds = CGRect(dictionaryRepresentation: item.0.bounds()!)
            // Convert the coordinate system, the origin of window is top-left, the image is bottom-left
            // so we need to convert y-index
            context?.draw(item.1, in: CGRect.init(x: bounds!.origin.x, y: screen.frame.height - bounds!.height - bounds!.origin.y, width: bounds!.width, height: bounds!.height))
        }
        return context?.makeImage()
    }

    func screenshot(_ win: Window) -> CGImage? {
        var windowId_ = self
        if win.isFullscreen {
            return fullScreenshot(win)
        } else {
            let list = CGSHWCaptureWindowList(cgsMainConnectionId, &windowId_, 1, [.ignoreGlobalClipShape, .nominalResolution]).takeRetainedValue() as! [CGImage]
            return list.first
        }

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
