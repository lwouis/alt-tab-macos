import Cocoa

class WindowlessAppIndicator: NSView {
    struct AppearanceParameter {
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
    }

    var cornerRadius: CGFloat!

    convenience init(parameter: AppearanceParameter = WindowlessAppIndicator.getAppearanceParameter(),
                     tooltip: String? = nil) {
        self.init(frame: .zero)
        frame.size.width = parameter.width
        frame.size.height = parameter.height
        cornerRadius = parameter.cornerRadius
        toolTip = tooltip
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Appearance.fontColor.withAlphaComponent(0.5).setFill()
        let rectPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        rectPath.fill()
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    static func getAppearanceParameter() -> AppearanceParameter {
        let style = Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex)
        if style == .thumbnails || style == .appIcons {
            if Appearance.resolvedSize == .large {
                return AppearanceParameter(width: 12, height: 5, cornerRadius: 2)
            }
            return AppearanceParameter(width: 10, height: 5, cornerRadius: 2)
        }
        if Appearance.resolvedSize == .large {
            return AppearanceParameter(width: 8, height: 3, cornerRadius: 1)
        }
        return AppearanceParameter(width: 6, height: 3, cornerRadius: 1)
    }
}
