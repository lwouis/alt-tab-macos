import Cocoa

class Appearance {
    // size
    static var hideThumbnails = Bool(false)
    static var windowPadding = CGFloat(1000)
    static var windowCornerRadius = CGFloat(1000)
    static var cellCornerRadius = CGFloat(1000)
    static var edgeInsetsSize = CGFloat(1000)
    static var maxWidthOnScreen = CGFloat(1000)
    static var rowsCount = CGFloat(1000)
    static var iconSize = CGFloat(1000)
    static var fontHeight = CGFloat(1000)
    static var windowMinWidthInRow = CGFloat(1000)
    static var windowMaxWidthInRow = CGFloat(1000)

    // size: constants
    static let maxHeightOnScreen = CGFloat(0.8)
    static let interCellPadding = CGFloat(1)
    static let intraCellPadding = CGFloat(5)
    static let appIconLabelSpacing = CGFloat(2)

    // theme
    static var fontColor = NSColor.red
    static var imagesShadowColor = NSColor.red // for icon, thumbnail and windowless images
    static var material = NSVisualEffectView.Material.ultraDark
    static var highlightBorderWidth = CGFloat(3)

    // theme: constants
    static let enablePanelShadow = true
    static var highlightFocusedBackgroundColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.2) } }
    static var highlightHoveredBackgroundColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.1) } }
    static var highlightFocusedBorderColor: NSColor { get { NSColor.systemAccentColor } }
    static var highlightHoveredBorderColor: NSColor { get { NSColor.systemAccentColor.withAlphaComponent(0.7) } }

    // derived
    static var font: NSFont {
        if #available(macOS 26.0, *) {
            return NSFont.systemFont(ofSize: fontHeight, weight: currentStyle == .appIcons ? .semibold : .medium)
        }
        return NSFont.systemFont(ofSize: fontHeight)
    }

    private static var currentStyle: AppearanceStylePreference { Preferences.appearanceStyle }
    private static var currentSize: AppearanceSizePreference { Preferences.appearanceSize }
    static var currentTheme: AppearanceThemePreference {
        if Preferences.appearanceTheme == .system {
            return NSAppearance.current.getThemeName()
        } else {
            return Preferences.appearanceTheme
        }
    }

    static func update() {
        updateSize()
        updateTheme()
    }

    private static func updateSize() {
        let isHorizontalScreen = NSScreen.preferred.isHorizontal()
        maxWidthOnScreen = AppearanceTestable.comfortableWidth(NSScreen.preferred.physicalSize().map { $0.width })
        if currentStyle == .appIcons {
            appIconsSize()
        } else if currentStyle == .titles {
            titlesSize(isHorizontalScreen)
        } else {
            thumbnailsSize(isHorizontalScreen)
        }
    }

    private static func updateTheme() {
        highlightBorderWidth = currentStyle == .titles ? 2 : 3
        if currentTheme == .dark {
            darkTheme()
        } else {
            lightTheme()
        }
        // // for Liquid Glass, we don't want a shadow around the panel
        // if #available(macOS 26.0, *), currentStyle == .appIcons && LiquidGlassEffectView.canUsePrivateLiquidGlassLook() {
        //     enablePanelShadow = false
        // }
    }

    private static func thumbnailsSize(_ isHorizontalScreen: Bool) {
        hideThumbnails = false
        windowPadding = 18
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 12
        if #available(macOS 26.0, *) {
            windowPadding = 28
            windowCornerRadius = 43
            cellCornerRadius = 18
        }
        switch currentSize {
            case .small:
                rowsCount = isHorizontalScreen ? 5 : 8
                iconSize = 16
                fontHeight = 13
            case .medium:
                rowsCount = isHorizontalScreen ? 4 : 7
                iconSize = 26
                fontHeight = 14
            case .large:
                rowsCount = isHorizontalScreen ? 3 : 6
                iconSize = 28
                fontHeight = 16
        }
        let thumbnailsPanelRatio = (NSScreen.preferred.frame.width * maxWidthOnScreen) / (NSScreen.preferred.frame.height * maxHeightOnScreen)
        (windowMinWidthInRow, windowMaxWidthInRow) = AppearanceTestable.goodValuesForThumbnailsWidthMinMax(thumbnailsPanelRatio, rowsCount)
    }

    private static func appIconsSize() {
        hideThumbnails = true
        windowPadding = 25
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 5
        if #available(macOS 26.0, *) {
            edgeInsetsSize = 6
        }
        windowMinWidthInRow = 0.04
        windowMaxWidthInRow = 0.3
        rowsCount = 1
        switch currentSize {
            case .small:
                iconSize = 70
                fontHeight = 13
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 50
                    cellCornerRadius = 24
                }
            case .medium:
                iconSize = 110
                fontHeight = 14
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 55
                    cellCornerRadius = 35
                }
            case .large:
                windowPadding = 28
                iconSize = 150
                fontHeight = 16
                if #available(macOS 26.0, *) {
                    windowCornerRadius = 75
                    cellCornerRadius = 45
                }
        }
    }

    private static func titlesSize(_ isHorizontalScreen: Bool) {
        hideThumbnails = true
        windowPadding = 18
        windowCornerRadius = 23
        cellCornerRadius = 10
        edgeInsetsSize = 7
        windowMinWidthInRow = 0.6
        windowMaxWidthInRow = 0.9
        rowsCount = 1
        switch currentSize {
            case .small:
                iconSize = 18
                fontHeight = 13
            case .medium:
                iconSize = 24
                fontHeight = 14
            case .large:
                iconSize = 30
                fontHeight = 16
        }
    }

    private static func lightTheme() {
        fontColor = .black.withAlphaComponent(0.8)
        imagesShadowColor = .gray.withAlphaComponent(0.8)
        material = .mediumLight
    }

    private static func darkTheme() {
        fontColor = .white.withAlphaComponent(0.85)
        imagesShadowColor = .gray.withAlphaComponent(0.8)
        material = .dark
    }
}
