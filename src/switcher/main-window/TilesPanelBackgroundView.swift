@available(macOS 26.0, *)
class LiquidGlassEffectView: NSGlassEffectView, EffectView {
    private typealias SetVariantType = @convention(c) (AnyObject, Selector, Int) -> Void
    private static let setVariantSelector = NSSelectorFromString("set_variant:")

    private static let canUsePrivateLiquidGlassLookCached: Bool = {
        let method = class_getInstanceMethod(object_getClass(NSGlassEffectView()), setVariantSelector)
        return method != nil
    }()

    static func canUsePrivateLiquidGlassLook() -> Bool { canUsePrivateLiquidGlassLookCached }

    convenience init(_ clear: Bool) {
        self.init()
        if clear {
            style = .clear
            safeSetVariant(3)
        } else {
            style = .regular
        }
        updateAppearance()
        wantsLayer = true
        // without this, there are weird shadows around the corners
        layer!.masksToBounds = true
    }

    func safeSetVariant(_ value: Int) {
        if let method = class_getInstanceMethod(object_getClass(self), LiquidGlassEffectView.setVariantSelector) {
            let methodImplementation = method_getImplementation(method)
            let f = unsafeBitCast(methodImplementation, to: SetVariantType.self)
            f(self, LiquidGlassEffectView.setVariantSelector, value)
        }
    }

    func updateAppearance() {
        cornerRadius = Appearance.windowCornerRadius
    }
}

class FrostedGlassEffectView: NSVisualEffectView, EffectView {
    convenience init(_: Int?) {
        self.init()
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

protocol EffectView: NSView {
    func updateAppearance()
}

enum EffectViewKind {
    case frosted
    case liquidGlassRegular
    case liquidGlassClear
}

func requiredEffectViewKind() -> EffectViewKind {
    if #available(macOS 26.0, *) {
        if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .appIcons,
           LiquidGlassEffectView.canUsePrivateLiquidGlassLook() {
            return .liquidGlassClear
        }
        return .liquidGlassRegular
    }
    return .frosted
}

func makeEffectView(for kind: EffectViewKind) -> EffectView {
    if #available(macOS 26.0, *) {
        switch kind {
            case .liquidGlassClear:
                Logger.debug { "Creating LiquidGlassEffectView(true)" }
                return LiquidGlassEffectView(true)
            case .liquidGlassRegular:
                if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .appIcons {
                    Logger.error {
                        let os = ProcessInfo.processInfo.operatingSystemVersion
                        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                        return "Private API set_variant is no longer available. macOS version: \(version))"
                    }
                }
                Logger.debug { "Creating LiquidGlassEffectView(false)" }
                return LiquidGlassEffectView(false)
            case .frosted:
                break
        }
    }
    Logger.debug { "Creating FrostedGlassEffectView(nil)" }
    return FrostedGlassEffectView(nil)
}

func makeAppropriateEffectView() -> EffectView {
    makeEffectView(for: requiredEffectViewKind())
}
