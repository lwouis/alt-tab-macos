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
        let appearance = NSApp.effectiveAppearance.name
        return appearance == .darkAqua || appearance == .vibrantDark ? .dark : .light
    }

    /// Whether *this* appearance is a dark one (unlike `getThemeName()`, which always reads
    /// `NSApp.effectiveAppearance`). Used by the dynamic-color provider so AppKit can resolve a
    /// color for whatever appearance a view is drawing in.
    var isDarkMode: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSColor {
    /// Dynamically adapts to changes in System Settings; no need to listen to notifications.
    class var systemAccentColor: NSColor {
        NSColor.controlAccentColor
    }

    /// A color that resolves itself per-appearance, so AppKit re-renders it automatically on a
    /// Dark/Light switch with no event observing and no manual repaint (as long as it's drawn by a
    /// view that re-resolves `NSColor`s, e.g. `NSBox`, rather than baked into `layer.backgroundColor`
    /// via `.cgColor`).
    private static func dynamicAppearanceColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDarkMode ? dark : light }
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

    func addSubviews(_ views: [NSView]) {
        subviews = subviews + views
    }

    /// Observe key / resign-key on this view's CURRENT window. Call from `viewDidMoveToWindow` and store
    /// the returned tokens: that override fires again on every window change, so the previous window's
    /// observers have to be dropped first (hence `replacing:`) or they outlive the window they watch.
    func observeWindowKeyChanges(replacing previous: [NSObjectProtocol], _ onChange: @escaping () -> Void) -> [NSObjectProtocol] {
        previous.forEach { NotificationCenter.default.removeObserver($0) }
        guard let window else { return [] }
        return [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in onChange() }
        }
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
    /// Tint at the call site via `NSImageView.contentTintColor` or by drawing into a tinted
    /// container. The image is rasterised at `pointSize`; for crisp Retina output, pass the
    /// displayed point size — AppKit handles @2x via the backing scale.
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
}

extension CGImage {
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

extension String {
    // convert a FourCharCode into a String
    init(_ fourCharCode: FourCharCode) { // or `OSType`, or `UInt32`
        self = NSFileTypeForHFSTypeCode(fourCharCode).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }
}

/// Whether AltTab's non-switcher windows may take key focus. They are only ever flipped together,
/// while the switcher's panel is ordered out: a window taking key focus there would steal it from the
/// app the user is switching to (`App.hideTilesPanelWithoutChangingKeyWindow`).
enum SecondaryWindows {
    static var canBecomeKey = true
}

extension NSTextView {
    /// A read-only, selectable text view sized to one settings column, for the Markdown-rendered
    /// panes. Text checking is off: these are static documents, so the checker would only ever
    /// underline product names.
    static func makeReadOnlyMarkdownView(_ columnWidth: CGFloat) -> NSTextView {
        let textView = NSTextView()
        textView.textContainer!.widthTracksTextView = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.drawsBackground = false
        textView.isSelectable = true
        textView.isEditable = false
        textView.enabledTextCheckingTypes = 0
        textView.frame.size.width = columnWidth
        return textView
    }
}

extension NSPanel {
    /// The chrome AltTab's two floating panels (the switcher and the window preview) share.
    /// `.canJoinAllSpaces` matters because triggering AltTab before or during a Space transition
    /// otherwise only brings the panel over once the transition ends. The `.unknown` accessibility
    /// subrole is what keeps these panels out of AltTab's own thumbnails.
    func applyFloatingPanelChrome() {
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        collectionBehavior = .canJoinAllSpaces
        setAccessibilitySubrole(.unknown)
    }
}

extension NSSearchField {
    /// The switcher's search field and the settings sidebar's look the same and both want every
    /// keystroke rather than a debounced one. `controlSize` tracks the OS: macOS 26 draws search
    /// fields as a taller pill, and 13 through 15 as the `.large` bezel.
    func applySearchStyle() {
        placeholderString = NSLocalizedString("Search", comment: "")
        sendsSearchStringImmediately = true
        sendsWholeSearchString = true
        bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) {
            controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            controlSize = .large
        }
    }
}

extension NotificationCenter {
    /// Drop a stored observer token. Nilling the token matters as much as the removal: the
    /// re-subscribe guards elsewhere read `observer == nil` to decide whether to observe again.
    func removeObserver(_ observer: inout NSObjectProtocol?) {
        guard let token = observer else { return }
        removeObserver(token)
        observer = nil
    }
}

extension NSWindow {
    /// The chrome every secondary window shares: a title that only shows in the Window menu and in
    /// Mission Control, and a window that survives both being closed and the app deactivating.
    /// `hiddenTitlebar` is what makes the content extend under the traffic lights; the Debug window
    /// keeps a real titlebar because it is resizable.
    func applySecondaryWindowChrome(_ title: String, hiddenTitlebar: Bool = true) {
        self.title = title
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        if hiddenTitlebar {
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
        }
    }

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

extension Optional {
    enum Error: Swift.Error {
        case unexpectedNil
    }

    // useful call multiple statements that could fail, and have a unique do-catch block to handle failures
    func unwrapOrThrow() throws -> Wrapped {
        if let self { return self } else { throw Error.unexpectedNil }
    }
}

extension NSRunningApplication {
    func debugId() -> String { "(pid:\(processIdentifier) \(bundleIdentifier ?? bundleURL?.absoluteString ?? executableURL?.absoluteString ?? localizedName))" }
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

    /// Create an event tap and put it on `runLoop`. `tapCreate` returns nil when the Accessibility
    /// permission isn't granted, and every input tap we install is load-bearing, so that case restarts
    /// the app rather than running on with a dead tap.
    static func createTapOrRestart(tap: CGEventTapLocation, options: CGEventTapOptions, eventsOfInterest: CGEventMask,
                                   callback: @escaping CGEventTapCallBack, runLoop: CFRunLoop?) -> CFMachPort? {
        guard let port = CGEvent.tapCreate(tap: tap, place: .headInsertEventTap, options: options,
            eventsOfInterest: eventsOfInterest, callback: callback, userInfo: nil) else {
            App.restart()
            return nil
        }
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        return port
    }

    /// macOS disables taps on sleep and on a callback timeout (#5723). Put one back in the stream if we
    /// still want it on. Returns whether it re-enabled, so each caller logs its own wording.
    static func reEnableTapIfNeeded(_ port: CFMachPort?, wanted: Bool) -> Bool {
        guard let port, wanted, !CGEvent.tapIsEnabled(tap: port) else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}
