import Cocoa

class StatusIconsView: FlippedView {
    struct Icon {
        var symbol: String
        var tooltip: String?
        var visible = false
    }

    static let spaceIdx = 0
    static let hiddenIdx = 1
    static let fullscreenIdx = 2
    static let minimizedIdx = 3

    private static let defaultSymbols: [(Symbols, String?)] = [
        (.circledNumber0, nil),
        (.circledSlashSign, NSLocalizedString("App is hidden", comment: "")),
        (.circledPlusSign, NSLocalizedString("Window is fullscreen", comment: "")),
        (.circledMinusSign, NSLocalizedString("Window is minimized", comment: "")),
    ]

    var icons: [Icon]
    private let attrs: [NSAttributedString.Key: Any]
    private var visibleCount = 0
    private var tooltipsDirty = true
    /// Single-character cell size, cached at init for the layout cache
    let iconCellSize: NSSize

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: NSRect) {
        let font = NSFont(name: "SF Pro Text", size: (Appearance.fontHeight * 0.85).rounded())!
        let paragraphStyle = TileFontIconView.paragraphStyle
        attrs = [.font: font, .foregroundColor: Appearance.fontColor, .paragraphStyle: paragraphStyle]
        icons = Self.defaultSymbols.map { Icon(symbol: $0.0.rawValue, tooltip: $0.1) }
        let measure = NSAttributedString(string: Symbols.circledNumber0.rawValue, attributes: attrs)
        iconCellSize = measure.size()
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    var totalWidth: CGFloat { CGFloat(visibleCount) * TilesView.layoutCache.iconWidth }

    func update(isHidden: Bool, isFullscreen: Bool, isMinimized: Bool, showSpace: Bool) {
        icons[Self.hiddenIdx].visible = isHidden
        icons[Self.fullscreenIdx].visible = isFullscreen
        icons[Self.minimizedIdx].visible = isMinimized
        icons[Self.spaceIdx].visible = showSpace
        visibleCount = icons.count(where: { $0.visible })
    }

    func setSpaceStar() {
        icons[Self.spaceIdx].symbol = Symbols.circledStar.rawValue
        icons[Self.spaceIdx].tooltip = NSLocalizedString("Window is on every Space", comment: "")
    }

    func setSpaceNumber(_ number: Int) {
        let (base, offset) = number <= 9
            ? (Symbols.circledNumber0.rawValue, number * 2)
            : (Symbols.circledNumber10.rawValue, number - 10)
        icons[Self.spaceIdx].symbol = String(UnicodeScalar(Int(base.unicodeScalars.first!.value) + offset)!)
        icons[Self.spaceIdx].tooltip = String(format: NSLocalizedString("Window is on Space %d", comment: ""), number)
    }

    var spaceVisible: Bool { icons[Self.spaceIdx].visible }

    func layoutIcons(hWidth: CGFloat, hHeight: CGFloat, edgeInsets: CGFloat) {
        let indicatorSpace = totalWidth
        assignIfDifferent(&frame.size.width, indicatorSpace)
        assignIfDifferent(&frame.size.height, hHeight)
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        assignIfDifferent(&frame.origin.x, isLTR ? edgeInsets + hWidth - indicatorSpace : edgeInsets)
        assignIfDifferent(&frame.origin.y, edgeInsets)
        tooltipsDirty = true
        needsDisplay = true
    }

    func ensureTooltipsInstalled() {
        guard tooltipsDirty else { return }
        tooltipsDirty = false
        removeAllToolTips()
        let iconWidth = TilesView.layoutCache.iconWidth
        let iconHeight = TilesView.layoutCache.iconHeight
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        let yOffset = ((frame.height - iconHeight) / 2).rounded()
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? frame.width - offset : offset - iconWidth
            if let tooltip = icon.tooltip {
                _ = addToolTip(NSRect(x: x, y: yOffset, width: iconWidth, height: iconHeight), owner: tooltip as NSString, userData: nil)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard visibleCount > 0 else { return }
        let iconWidth = TilesView.layoutCache.iconWidth
        let iconHeight = TilesView.layoutCache.iconHeight
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        let yOffset = ((frame.height - iconHeight) / 2).rounded()
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? frame.width - offset : offset - iconWidth
            icon.symbol.draw(at: NSPoint(x: x, y: yOffset), withAttributes: attrs)
        }
    }
}
