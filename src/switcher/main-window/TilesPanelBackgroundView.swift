protocol EffectView: NSView {
    func updateAppearance()
    /// Where `TilesView` places its content (scroll view, search field, empty-state label).
    /// For `NSVisualEffectView` that's the view itself; for `NSGlassEffectView` it's `contentView`,
    /// the only place Apple guarantees rendering for embedded views.
    var hostView: NSView { get }
}

@available(macOS 26.0, *)
extension NSGlassEffectView: EffectView {
    func updateAppearance() {
        cornerRadius = Appearance.windowCornerRadius
    }

    var hostView: NSView { contentView! }
}

class FrostedGlassEffectView: NSVisualEffectView, EffectView {
    var hostView: NSView { self }

    convenience init() {
        self.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        updateAppearance()
    }

    func updateAppearance() {
        material = Appearance.material
        updateRoundedCorners(Appearance.windowCornerRadius)
    }

    /// using layer!.cornerRadius works but the corners are aliased; this custom approach gives smooth rounded corners
    /// see https://stackoverflow.com/a/29386935/2249756
    private func updateRoundedCorners(_ cornerRadius: CGFloat) {
        if cornerRadius == 0 {
            maskImage = nil
        } else {
            let edgeLength = 2.0 * cornerRadius + 1.0
            let mask = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
                let bezierPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.black.set()
                bezierPath.fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
            mask.resizingMode = .stretch
            maskImage = mask
        }
    }
}

/// The App Icons style uses the private `set_variant:` on `NSGlassEffectView` to get the macOS
/// Cmd-Tab-like clear glass look. `style = .clear` alone renders nearly fully transparent, so the
/// variant is what makes the panel visible. Lives here as a free helper (no NSGlassEffectView subclass).
enum LiquidGlass {
    private static let setVariantSelector = NSSelectorFromString("set_variant:")
    private typealias SetVariantFn = @convention(c) (AnyObject, Selector, Int) -> Void

    static let canUsePrivateLook: Bool = {
        if #available(macOS 26.0, *) {
            return class_getInstanceMethod(object_getClass(NSGlassEffectView()), setVariantSelector) != nil
        }
        return false
    }()

    @available(macOS 26.0, *)
    static func applyClearVariant(_ view: NSGlassEffectView) {
        guard let method = class_getInstanceMethod(object_getClass(view), setVariantSelector) else { return }
        let f = unsafeBitCast(method_getImplementation(method), to: SetVariantFn.self)
        f(view, setVariantSelector, 3)
    }
}

enum EffectViewKind {
    case frosted
    case liquidGlassRegular
    case liquidGlassClear
}

func requiredEffectViewKind() -> EffectViewKind {
    if #available(macOS 26.0, *) {
        if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .appIcons,
           LiquidGlass.canUsePrivateLook {
            return .liquidGlassClear
        }
        return .liquidGlassRegular
    }
    return .frosted
}

@available(macOS 26.0, *)
private func makeGlassEffectView(clear: Bool) -> NSGlassEffectView {
    let glass = NSGlassEffectView()
    glass.style = clear ? .clear : .regular
    if clear {
        LiquidGlass.applyClearVariant(glass)
    }
    // NSGlassEffectView only renders views embedded in `contentView`; this single host holds the
    // scroll view, search field and empty-state label so they all sit inside the glass.
    glass.contentView = NSView()
    glass.updateAppearance()
    // without this, there are weird shadows around the corners (most visible with .regular glass)
    glass.wantsLayer = true
    glass.layer!.masksToBounds = true
    return glass
}

func makeEffectView(for kind: EffectViewKind) -> EffectView {
    if #available(macOS 26.0, *) {
        switch kind {
            case .liquidGlassClear:
                return makeGlassEffectView(clear: true)
            case .liquidGlassRegular:
                if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .appIcons {
                    Logger.error {
                        let os = ProcessInfo.processInfo.operatingSystemVersion
                        return "Private API set_variant is no longer available. macOS version: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                    }
                }
                return makeGlassEffectView(clear: false)
            case .frosted:
                break
        }
    }
    return FrostedGlassEffectView()
}
