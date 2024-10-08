import Cocoa
import Darwin

extension NSAppearance {
    func getThemeName() -> AppearanceThemePreference {
        if #available(macOS 10.14, *) {
            let appearance = NSApp.effectiveAppearance.name
            if appearance == .darkAqua || appearance == .vibrantDark {
                return .dark
            }
        }
        return .light
    }
}

extension NSColor {
    // periphery:ignore
    func toHex() -> String? {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = Int(rgbColor.redComponent * 255.0)
        let green = Int(rgbColor.greenComponent * 255.0)
        let blue = Int(rgbColor.blueComponent * 255.0)

        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    class var systemAccentColor: NSColor {
        if #available(macOS 10.14, *) {
            // dynamically adapts to changes in System Default; no need to listen to notifications
            return NSColor.controlAccentColor
        }
        return NSColor.blue
    }

    class var tableBorderColor: NSColor {
        // #4b4b4b
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 75/255, green: 75/255, blue: 75/255, alpha: 0.8)

        }
        // #e5e5e5
        return NSColor(srgbRed: 229/255, green: 229/255, blue: 229/255, alpha: 0.8)
    }

    class var tableBackgroundColor: NSColor {
        // #2b2b2b
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 43/255, green: 43/255, blue: 43/255, alpha: 0.8)

        }
        // #f2f2f2
        return NSColor(srgbRed: 242/255, green: 242/255, blue: 242/255, alpha: 0.8)
    }

    class var tableSeparatorColor: NSColor {
        // #353535
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 53/255, green: 53/255, blue: 53/255, alpha: 0.8)

        }
        // #e7e7e7
        return NSColor(srgbRed: 231/255, green: 231/255, blue: 231/255, alpha: 0.8)
    }

    class var tableHoverColor: NSColor {
        // #363636
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 54/255, green: 54/255, blue: 54/255, alpha: 0.8)

        }
        // #ebebeb
        return NSColor(srgbRed: 235/255, green: 235/255, blue: 235/255, alpha: 0.8)
    }
}

extension NSView {
    // constrain size to fittingSize
    func fit() {
        widthAnchor.constraint(equalToConstant: fittingSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: fittingSize.height).isActive = true
    }

    // constrain size to provided width and height
    func fit(_ width: CGFloat, _ height: CGFloat) {
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }
}

extension Collection {
    // forEach with each iteration run concurrently on the global queue
    func forEachAsync(fn: @escaping (Element) -> Void) {
        let group = DispatchGroup()
        for element in self {
            BackgroundWork.globalSemaphore.wait()
            BackgroundWork.mainQueueConcurrentWorkQueue.async(group: group) {
                group.enter()
                fn(element)
                BackgroundWork.globalSemaphore.signal()
                group.leave()
            }
        }
        group.wait()
    }

    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// allow using a closure for NSControl action, instead of selector
class SelectorWrapper<T> {
    let selector: Selector
    let closure: (T) -> Void

    init(withClosure closure: @escaping (T) -> Void) {
        self.selector = #selector(callClosure)
        self.closure = closure
    }

    @objc
    private func callClosure(sender: AnyObject) {
        closure(sender as! T)
    }
}

fileprivate var handle: Int = 0

typealias ActionClosure = (NSControl) -> Void

extension NSControl {
    var onAction: ActionClosure? {
        get {
            return nil
        }
        set {
            if let newValue = newValue {
                let selectorWrapper = SelectorWrapper<NSControl>(withClosure: newValue)
                objc_setAssociatedObject(self, &handle, selectorWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = selectorWrapper.selector
                target = selectorWrapper
            } else {
                action = nil
                target = nil
            }
        }
    }
}

// only assign if different; useful for performance
func assignIfDifferent<T: Equatable>(_ a: UnsafeMutablePointer<T>, _ b: T) {
    if a.pointee != b {
        a.pointee = b
    }
}

extension DispatchQoS {
    func toQualityOfService() -> QualityOfService {
        switch self {
            case .userInteractive: return .userInteractive
            case .userInitiated: return .userInitiated
            case .utility: return .utility
            case .background: return .background
            default: return .default
        }
    }
}

extension NSImage {
    // NSImage(named) caches/reuses NSImage objects; we force separate instances of images by using copy()
    static func initCopy(_ name: String) -> NSImage {
        return NSImage(named: name)!.copy() as! NSImage
    }

    static func initTemplateCopy(_ name: String) -> NSImage {
        let image = initCopy(name)
        image.isTemplate = true
        return image
    }

    // copy and resize an image using high quality interpolation
    static func initResizedCopy(_ name: String, _ width: CGFloat, _ height: CGFloat) -> NSImage {
        let original = initCopy(name)
        let img = NSImage(size: CGSize(width: width, height: height))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        original.draw(in: NSMakeRect(0, 0, width, height), from: NSMakeRect(0, 0, original.size.width, original.size.height), operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }
}

extension pid_t {
    func isZombie() -> Bool {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, self]
        sysctl(&mib, u_int(mib.count), &kinfo, &size, nil, 0)
        _ = withUnsafePointer(to: &kinfo.kp_proc.p_comm) {
            String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
        return kinfo.kp_proc.p_stat == SZOMB
    }
}

extension String {
    // convert a FourCharCode into a String
    init(_ fourCharCode: FourCharCode) { // or `OSType`, or `UInt32`
        self = NSFileTypeForHFSTypeCode(fourCharCode).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }
}

extension Int {
    func compare(_ otherNumber: Int) -> ComparisonResult {
        return (self as NSNumber).compare(otherNumber as NSNumber)
    }
}

extension Optional where Wrapped == String {
    func localizedStandardCompare(_ string: String?) -> ComparisonResult {
        return (self ?? "").localizedStandardCompare(string ?? "")
    }
}

extension NSWindow {
    func hideAppIfLastWindowIsClosed() {
        if (!NSApp.windows.contains { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.windowNumber != windowNumber}) {
            App.shared.hide(nil)
        }
    }
}
