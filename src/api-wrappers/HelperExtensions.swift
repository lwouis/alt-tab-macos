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
            return NSColor(srgbRed: 75 / 255, green: 75 / 255, blue: 75 / 255, alpha: 0.8)
        }
        // #e5e5e5
        return NSColor(srgbRed: 229 / 255, green: 229 / 255, blue: 229 / 255, alpha: 0.8)
    }

    class var tableBackgroundColor: NSColor {
        // #2b2b2b
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 43 / 255, green: 43 / 255, blue: 43 / 255, alpha: 0.8)
        }
        // #f2f2f2
        return NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 0.8)
    }

    class var tableSeparatorColor: NSColor {
        // #353535
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 53 / 255, green: 53 / 255, blue: 53 / 255, alpha: 0.8)
        }
        // #e7e7e7
        return NSColor(srgbRed: 231 / 255, green: 231 / 255, blue: 231 / 255, alpha: 0.8)
    }

    class var tableHoverColor: NSColor {
        // #363636
        if NSAppearance.current.getThemeName() == .dark {
            return NSColor(srgbRed: 54 / 255, green: 54 / 255, blue: 54 / 255, alpha: 0.8)
        }
        // #ebebeb
        return NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 235 / 255, alpha: 0.8)
    }
}

extension NSView {
    // constrain size to fittingSize
    func fit() {
        addOrUpdateConstraint(widthAnchor, fittingSize.width)
        addOrUpdateConstraint(heightAnchor, fittingSize.height)
    }

    // constrain size to provided width and height
    func fit(_ width: CGFloat, _ height: CGFloat) {
        addOrUpdateConstraint(widthAnchor, width)
        addOrUpdateConstraint(heightAnchor, height)
    }

    func addOrUpdateConstraint(_ anchor: NSLayoutDimension, _ constant: CGFloat) {
        if let constraint = (constraints.first { $0.firstAnchor == anchor && $0.secondAnchor == nil }) {
            constraint.constant = constant
        } else {
            anchor.constraint(equalToConstant: constant).isActive = true
        }
    }

    func centerFrameInParent(x: Bool = false, y: Bool = false) {
        let selfSize = (self is NSTextField) ? (self as! NSTextField).fittingSize : frame.size
        let superviewSize = (superview! is NSTextField) ? (superview! as! NSTextField).fittingSize : superview!.frame.size
        if (x) {
            frame.origin.x = ((superviewSize.width - selfSize.width) / 2).rounded()
        }
        if (y) {
            let diff = superviewSize.height - selfSize.height
            // if there is no perfect centering, we biais top, as it's more aesthetic for ThumbnailView.label
            let diffWithBiasTop = diff.truncatingRemainder(dividingBy: 2) == 0 ? diff : diff - 1
            frame.origin.y = (diffWithBiasTop / 2).rounded()
        }
    }

    func setSubviews(_ views: [NSView]) {
        for view in views {
            normalizeSubview(view)
        }
        subviews = views
    }

    func addSubviews(_ views: [NSView]) {
        for view in views {
            normalizeSubview(view)
        }
        subviews = subviews + views
    }

    func setSubviewAbove(_ view: NSView) {
        normalizeSubview(view)
        addSubview(view, positioned: .above, relativeTo: nil)
    }

    private func normalizeSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// allow using a closure for NSControl action, instead of selector
class SelectorWrapper<T> {
    let selector: Selector
    let closure: (T) -> Void

    init(withClosure closure: @escaping (T) -> Void) {
        selector = #selector(callClosure)
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
            if let newValue {
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
    func appIconFixedSize(_ size: NSSize) -> CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // NSImage(named) caches/reuses NSImage objects; we force separate instances of images by using copy()
    static func initCopy(_ name: String) -> NSImage {
        return NSImage(named: name)!.copy() as! NSImage
    }
}

extension CGImage {
    func nsImage() -> NSImage {
        return NSImage(cgImage: self, size: size())
    }

    static func named(_ imageName: String) -> CGImage {
        let imageURL = Bundle.main.url(forResource: imageName, withExtension: nil)!
        let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
    }

    func size() -> NSSize {
        return NSSize(width: width, height: height)
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
        if (!NSApp.windows.contains { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.windowNumber != windowNumber }) {
            App.shared.hide(nil)
        }
    }
}

extension CaseIterable where Self: Equatable {
    var index: Int {
        return Self.allCases.distance(from: Self.allCases.startIndex, to: Self.allCases.firstIndex(of: self)!)
    }
    var indexAsString: String {
        return String(describing: self.index)
    }
}

class ModifierFlags {
    static var current: NSEvent.ModifierFlags {
        return NSEvent.modifierFlags
    }
}

extension NSPoint {
    static func +=(lhs: inout NSPoint, rhs: NSPoint) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }

    static func +(lhs: NSPoint, rhs: NSPoint) -> NSPoint {
        return NSPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func -(lhs: NSPoint, rhs: NSPoint) -> NSPoint {
        return NSPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func /(lhs: NSPoint, rhs: Int) -> NSPoint {
        return NSPoint(x: lhs.x / Double(rhs), y: lhs.y / Double(rhs))
    }
}

extension Optional {
    enum Error: Swift.Error {
        case unexpectedNil
    }

    // useful call multiple statements that could fail, and have a unique do-catch block to handle failures
    func unwrapOrThrow() throws -> Wrapped {
        if let self { return self } else { throw Error.unexpectedNil }
    }
}

extension DispatchTimeInterval {
    var toMilliseconds: Int {
        switch self {
            case .seconds(let s): return s / 1000
            case .milliseconds(let ms): return ms
            case .microseconds(let us): return us * 1000
            case .nanoseconds(let ns): return ns * 1_000_000
            default: return .max
        }
    }
}

extension NSRunningApplication {
    func debugId() -> String { "(pid:\(processIdentifier) \(bundleIdentifier ?? bundleURL?.absoluteString ?? executableURL?.absoluteString ?? localizedName))" }
}

// 250ms is similar to human delay in processing changes on screen
// See https://humanbenchmark.com/tests/reactiontime
let humanPerceptionDelay = DispatchTimeInterval.milliseconds(250)

extension NSTouch.Phase {
    var readable: String {
        switch self {
        case .began:      "began"
        case .moved:      "moved"
        case .stationary: "stationary"
        case .ended:      "ended"
        case .cancelled:  "cancelled"
        default:          "unknown"
        }
    }
}

/// this changes the behavior of interpolating optional values (e.g. "\(optionalValue)")
/// default is to return a compiler warning "string interpolation produces a debug description for an optional value; did you mean to make this explicit?"
/// instead, we either print the value, or print "nil"
extension String.StringInterpolation {
    mutating func appendInterpolation<T>(_ value: T?) {
        if let value {
            appendInterpolation(value)
        } else {
            appendLiteral("nil")
        }
    }
}
