import Cocoa
import Darwin
import Carbon.HIToolbox.Events

class NoAnimationDelegate: NSObject, CALayerDelegate {
    static let shared = NoAnimationDelegate()
    func action(for layer: CALayer, forKey event: String) -> (any CAAction)? { NSNull() }
}

func noAnimation<T: CALayer>(_ make: () -> T) -> T {
    let layer = make()
    layer.delegate = NoAnimationDelegate.shared
    return layer
}

func caTransaction(_ body: () -> Void) {
    CATransaction.begin()
    defer { CATransaction.commit() }
    CATransaction.setDisableActions(true)
    body()
}

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

extension CALayer {
    func centerInSuperlayer(x: Bool = false, y: Bool = false) {
        guard let superlayer else { return }
        if x { frame.origin.x = ((superlayer.bounds.width - frame.width) / 2).rounded() }
        if y { frame.origin.y = ((superlayer.bounds.height - frame.height) / 2).rounded() }
    }

    func applyShadow(_ shadow: NSShadow?) {
        guard let shadow else { shadowOpacity = 0; return }
        shadowColor = shadow.shadowColor?.cgColor
        shadowOffset = shadow.shadowOffset
        shadowRadius = shadow.shadowBlurRadius
        shadowOpacity = 1.0
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
            frame.origin.y = (diff / 2).rounded()
        }
    }

    func setSubviews(_ views: [NSView]) {
        subviews = views
    }

    func addSubviews(_ views: [NSView]) {
        subviews = subviews + views
    }

    func setSubviewAbove(_ view: NSView) {
        addSubview(view, positioned: .above, relativeTo: nil)
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
    // NSImage(named) caches/reuses NSImage objects; we force separate instances of images by using copy()
    static func initCopy(_ name: String) -> NSImage {
        return NSImage(named: name)!.copy() as! NSImage
    }

    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(in: rect, from: NSRect(origin: .zero, size: self.size), operation: .destinationIn, fraction: 1.0)
            return true
        }
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

    func isFullyTransparent() -> Bool {
        guard ![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo),
              let provider = dataProvider, let data = provider.data, let ptr = CFDataGetBytePtr(data)
        else { return false }
        let length = CFDataGetLength(data)
        guard length >= 4 else { return true }
        if length / 4 <= 256 { return scanAlphaBytes(ptr, length, 3, 4, length / 4) }
        if bytesPerRow > 0 && width > 0 && height > 0 { return scanSampleGrid(ptr, length) }
        return scanFlatSamples(ptr, length)
    }

    private func scanSampleGrid(_ ptr: UnsafePointer<UInt8>, _ length: Int) -> Bool {
        let rowStep = max((height - 1) / 9, 1)
        let colStep = max((width - 1) / 19, 1)
        var row = 0
        while row < height {
            if !scanSampleRow(ptr, length, row, colStep) { return false }
            row += rowStep
        }
        if !scanSampleRow(ptr, length, height - 1, colStep) { return false }
        if !scanSampleColumn(ptr, length, width - 1, rowStep) { return false }
        return scanPinnedPoints(ptr, length)
    }

    private func scanSampleRow(_ ptr: UnsafePointer<UInt8>, _ length: Int, _ row: Int, _ colStep: Int) -> Bool {
        var col = 0
        while col < width {
            if !sampleAlpha(ptr, length, row, col) { return false }
            col += colStep
        }
        return sampleAlpha(ptr, length, row, width - 1)
    }

    private func scanSampleColumn(_ ptr: UnsafePointer<UInt8>, _ length: Int, _ col: Int, _ rowStep: Int) -> Bool {
        var row = 0
        while row < height {
            if !sampleAlpha(ptr, length, row, col) { return false }
            row += rowStep
        }
        return sampleAlpha(ptr, length, height - 1, col)
    }

    private func scanPinnedPoints(_ ptr: UnsafePointer<UInt8>, _ length: Int) -> Bool {
        let lastRow = height - 1
        let lastCol = width - 1
        for rowIndex in 0...4 {
            let row = (lastRow * rowIndex) / 4
            for colIndex in 0...4 {
                let col = (lastCol * colIndex) / 4
                guard sampleAlpha(ptr, length, row, col) else { return false }
            }
        }
        return true
    }

    private func sampleAlpha(_ ptr: UnsafePointer<UInt8>, _ length: Int, _ row: Int, _ col: Int) -> Bool {
        let byteOffset = row * bytesPerRow + col * 4 + 3
        return byteOffset >= length || ptr[byteOffset] == 0
    }

    private func scanAlphaBytes(_ ptr: UnsafePointer<UInt8>, _ length: Int, _ start: Int, _ step: Int, _ count: Int) -> Bool {
        var offset = start
        for _ in 0..<count {
            guard offset < length else { return true }
            if ptr[offset] != 0 { return false }
            offset += step
        }
        return true
    }

    private func scanFlatSamples(_ ptr: UnsafePointer<UInt8>, _ length: Int) -> Bool {
        let step = max((length / 4) / 200, 1) * 4
        var offset = 3
        while offset < length {
            if ptr[offset] != 0 { return false }
            offset += step
        }
        return true
    }
}

extension CVPixelBuffer {
    func size() -> NSSize {
        NSSize(
            width: CVPixelBufferGetWidth(self),
            height: CVPixelBufferGetHeight(self)
        )
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

extension CGEvent {
    func toNSEvent() -> NSEvent? {
        if Thread.isMainThread {
            return NSEvent(cgEvent: self)
        }
        // conversion has to happen on the main-thread, or appkit will crash
        var nsEvent: NSEvent?
        DispatchQueue.main.sync {
            nsEvent = NSEvent(cgEvent: self)
        }
        return nsEvent
    }
}
