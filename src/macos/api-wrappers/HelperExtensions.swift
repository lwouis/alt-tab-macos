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

    /// Whether *this* appearance is a dark one (unlike `getThemeName()`, which always reads
    /// `NSApp.effectiveAppearance`). Used by the dynamic-color provider so AppKit can resolve a
    /// color for whatever appearance a view is drawing in.
    var isDarkMode: Bool {
        if #available(macOS 10.14, *) {
            return bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return false
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

    /// A color that resolves itself per-appearance, so AppKit re-renders it automatically on a
    /// Dark/Light switch with no event observing and no manual repaint (as long as it's drawn by a
    /// view that re-resolves `NSColor`s, e.g. `NSBox`, rather than baked into `layer.backgroundColor`
    /// via `.cgColor`). Below 10.15 there's no dynamic-provider API, so it resolves once for the
    /// current app appearance — fine, since 10.13 has no Dark mode and 10.14 is vanishingly rare.
    private static func dynamicAppearanceColor(light: NSColor, dark: NSColor) -> NSColor {
        if #available(macOS 10.15, *) {
            return NSColor(name: nil) { $0.isDarkMode ? dark : light }
        }
        if #available(macOS 10.14, *) {
            return NSApp.effectiveAppearance.isDarkMode ? dark : light
        }
        return light
    }

    class var tableBorderColor: NSColor {
        dynamicAppearanceColor(
            light: NSColor(srgbRed: 229 / 255, green: 229 / 255, blue: 229 / 255, alpha: 0.8),  // #e5e5e5
            dark: NSColor(srgbRed: 75 / 255, green: 75 / 255, blue: 75 / 255, alpha: 0.8))       // #4b4b4b
    }

    class var tableBackgroundColor: NSColor {
        dynamicAppearanceColor(
            light: NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 0.8),  // #f2f2f2
            dark: NSColor(srgbRed: 43 / 255, green: 43 / 255, blue: 43 / 255, alpha: 0.8))       // #2b2b2b
    }

    class var tableSeparatorColor: NSColor {
        dynamicAppearanceColor(
            light: NSColor(srgbRed: 231 / 255, green: 231 / 255, blue: 231 / 255, alpha: 0.8),  // #e7e7e7
            dark: NSColor(srgbRed: 53 / 255, green: 53 / 255, blue: 53 / 255, alpha: 0.8))       // #353535
    }

    class var tableHoverColor: NSColor {
        dynamicAppearanceColor(
            light: NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 235 / 255, alpha: 0.8),  // #ebebeb
            dark: NSColor(srgbRed: 54 / 255, green: 54 / 255, blue: 54 / 255, alpha: 0.8))       // #363636
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

extension NSView {
    /// Wrap this view in a container that adds top padding above it. Used as a window's
    /// `contentView` when the window has `.fullSizeContentView` — the content view extends
    /// behind the traffic-light buttons, so the actual content needs a top inset to avoid
    /// overlapping them.
    func wrappedWithTitlebarPadding(_ padding: CGFloat = 10) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: wrapper.topAnchor, constant: padding),
            leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }
}

extension NSImage {
    // NSImage(named) caches/reuses NSImage objects; we force separate instances of images by using copy()
    static func initCopy(_ name: String) -> NSImage {
        return NSImage(named: name)!.copy() as! NSImage
    }

    /// Render an SF Symbol from the bundled `SF Pro Text` subset font as a template NSImage.
    /// Tint at the call site via `NSImageView.contentTintColor` (macOS 10.14+) or by drawing
    /// into a tinted container. The image is rasterised at `pointSize`; for crisp Retina output,
    /// pass the displayed point size — AppKit handles @2x via the backing scale.
    ///
    /// The image is cropped to the glyph's ink bounds (the actual visible pixels), not the
    /// font's typographic box. This makes `NSSegmentedControl` and similar containers center
    /// the glyph correctly — math symbols like `+`/`−` sit on the math axis, which doesn't
    /// match the typographic midline, so a typographic-box image renders visibly off-centre.
    ///
    /// `rotated180` flips the glyph 180° around the image centre — used e.g. for the override
    /// indicator where the upright `arrow.triangle.branch` glyph reads better pointing
    /// downward ("this value branches to other shortcuts").
    static func fromSymbol(_ symbol: Symbols, pointSize: CGFloat, rotated180: Bool = false) -> NSImage {
        let font = NSFont(name: "SF Pro Text", size: pointSize)!
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let attrStr = NSAttributedString(string: symbol.rawValue, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let inkBounds = CTLineGetImageBounds(line, nil)
        let imageSize = NSSize(width: ceil(inkBounds.width), height: ceil(inkBounds.height))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            if rotated180 {
                ctx.translateBy(x: imageSize.width / 2, y: imageSize.height / 2)
                ctx.rotate(by: .pi)
                ctx.translateBy(x: -imageSize.width / 2, y: -imageSize.height / 2)
            }
            ctx.translateBy(x: -inkBounds.origin.x, y: -inkBounds.origin.y)
            CTLineDraw(line, ctx)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
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

    static func allNamed(_ imageName: String) -> [CGImage] {
        let imageURL = Bundle.main.url(forResource: imageName, withExtension: nil)!
        let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil)!
        let count = CGImageSourceGetCount(imageSource)
        return (0..<count).compactMap { CGImageSourceCreateImageAtIndex(imageSource, $0, nil) }
    }

    static func bestMatch(_ images: [CGImage], for size: NSSize) -> CGImage {
        let targetPx = Int(size.width.rounded())
        return images.filter { $0.width >= targetPx }.min(by: { $0.width < $1.width })
            ?? images.max(by: { $0.width < $1.width })!
    }

    func size() -> NSSize {
        return NSSize(width: width, height: height)
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

    /// Safe replacement for `setFrameAutosaveName`: that call doesn't just register a name, it
    /// immediately applies the frame persisted under "NSWindow Frame <name>". A corrupt persisted
    /// frame makes that apply throw and aborts the app (FeedbackWindow crash f481d5b0). Drop the bad
    /// value first so AppKit never sees it. Returns whether a valid saved frame is present.
    @discardableResult
    func setFrameAutosaveNameSafely(_ name: NSWindow.FrameAutosaveName) -> Bool {
        let key = "NSWindow Frame \(name)"
        let saved = UserDefaults.standard.string(forKey: key)
        let valid = saved.map { Self.isValidPersistedFrame($0) } ?? false
        if saved != nil && !valid {
            Logger.debug { "Dropping corrupt persisted frame for \(key): \(saved)" }
            UserDefaults.standard.removeObject(forKey: key)
        }
        setFrameAutosaveName(name)
        return valid
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
