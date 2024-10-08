import Cocoa

class WindowlessAppIndicator: NSView {
    struct AppearanceParameter {
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
    }

    var color: NSColor!
    var cornerRadius: CGFloat!

    convenience init(color: NSColor = Appearance.fontColor.withAlphaComponent(0.5),
                     parameter: AppearanceParameter = WindowlessAppIndicator.getAppearanceParameter(),
                     tooltip: String? = nil) {
        self.init(frame: .zero)
        self.color = color
        self.frame.size.width = parameter.width
        self.frame.size.height = parameter.height
        self.cornerRadius = parameter.cornerRadius
        self.toolTip = tooltip
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()

        let rectPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        rectPath.fill()
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    static func getAppearanceParameter() -> AppearanceParameter {
        if Preferences.appearanceStyle == .thumbnails || Preferences.appearanceStyle == .appIcons {
            if Preferences.appearanceSize == .large {
                return AppearanceParameter(width: 12, height: 5, cornerRadius: 2)
            }
            return AppearanceParameter(width: 10, height: 5, cornerRadius: 2)
        }
        if Preferences.appearanceSize == .large {
            return AppearanceParameter(width: 8, height: 3, cornerRadius: 1)
        }
        return AppearanceParameter(width: 6, height: 3, cornerRadius: 1)
    }

}
