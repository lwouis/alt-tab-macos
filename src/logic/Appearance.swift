import Cocoa

class Appearance {
    // size
    static var windowPadding = CGFloat(18)
    static var interCellPadding = CGFloat(5)
    static var intraCellPadding = CGFloat(1)
    static var edgeInsetsSize = CGFloat(5)
    static var cellCornerRadius = CGFloat(10)
    static var windowCornerRadius = CGFloat(23)
    static var hideThumbnails = Bool(false)
    static var rowsCount = CGFloat(0)
    static var windowMinWidthInRow = CGFloat(0)
    static var windowMaxWidthInRow = CGFloat(0)
    static var iconSize = CGFloat(0)
    static var fontHeight = CGFloat(0)
    static var maxWidthOnScreen = CGFloat(0.8)
    static var maxHeightOnScreen = CGFloat(0.8)
    
    // theme
    static var material = NSVisualEffectView.Material.dark
    static var fontColor = NSColor.white
    static var indicatedIconShadowColor: NSColor? = .darkGray
    static var titleShadowColor: NSColor? = .darkGray
    static var imageShadowColor: NSColor? = .gray // for icon, thumbnail and windowless images
    static var highlightMaterial = NSVisualEffectView.Material.selection
    static var highlightFocusedAlphaValue = 1.0
    static var highlightHoveredAlphaValue = 0.8
    static var highlightFocusedBackgroundColor = NSColor.black.withAlphaComponent(0.5)
    static var highlightHoveredBackgroundColor = NSColor.black.withAlphaComponent(0.3)
    static var highlightFocusedBorderColor = NSColor.clear
    static var highlightHoveredBorderColor = NSColor.clear
    static var highlightBorderShadowColor = NSColor.clear
    static var highlightBorderWidth = CGFloat(0)
    static var enablePanelShadow = false

    // derived
    static var font: NSFont { NSFont.systemFont(ofSize: fontHeight) }

    private static var currentStyle: AppearanceStylePreference { Preferences.appearanceStyle }
    private static var currentSize: AppearanceSizePreference { Preferences.appearanceSize }
    private static var currentTheme: AppearanceThemePreference {
        if Preferences.appearanceTheme == .system {
            return NSAppearance.current.getThemeName()
        } else {
            return Preferences.appearanceTheme
        }
    }
    private static var currentVisibility: AppearanceVisibilityPreference { Preferences.appearanceVisibility }

    static func update() {
        updateSize()
        updateTheme()
    }

    private static func updateSize() {
        let screen = NSScreen.preferred()
        let isHorizontalScreen = screen.isHorizontal()
        maxWidthOnScreen = comfortableWidth(screen.physicalSize()!.width)
        if currentStyle == .appIcons {
            appIconsSize()
        } else if currentStyle == .titles {
            titlesSize(isHorizontalScreen)
        } else {
            thumbnailsSize(isHorizontalScreen)
        }
    }

    private static func updateTheme() {
        if currentTheme == .dark {
            darkTheme()
        } else {
            lightTheme()
        }
    }

    private static func thumbnailsSize(_ isHorizontalScreen: Bool) {
        hideThumbnails = false
        windowPadding = 18
        cellCornerRadius = 10
        windowCornerRadius = 23
        intraCellPadding = 5
        interCellPadding = 1
        edgeInsetsSize = 12
        switch currentSize {
        case .small:
            rowsCount = isHorizontalScreen ? 5 : 8
            iconSize = 20
            fontHeight = 12
        case .medium:
            rowsCount = isHorizontalScreen ? 4 : 7
            iconSize = 30
            fontHeight = 13
        case .large:
            rowsCount = isHorizontalScreen ? 3 : 6
            iconSize = 32
            fontHeight = 16
        }
        (windowMinWidthInRow, windowMaxWidthInRow) = goodValuesForThumbnailsWidthMinMax()
        if currentVisibility == .highest {
            edgeInsetsSize = 10
            cellCornerRadius = 12
        }
    }

    private static func appIconsSize() {
        hideThumbnails = true
        windowPadding = 25
        cellCornerRadius = 10
        windowCornerRadius = 23
        intraCellPadding = 5
        interCellPadding = 1
        edgeInsetsSize = 5
        windowMinWidthInRow = 0.04
        windowMaxWidthInRow = 0.3
        rowsCount = 1
        switch currentSize {
        case .small:
            iconSize = 88
            fontHeight = 13
        case .medium:
            iconSize = 128
            fontHeight = 15
        case .large:
            windowPadding = 28
            iconSize = 168
            fontHeight = 17
        }
    }

    private static func titlesSize(_ isHorizontalScreen: Bool) {
        hideThumbnails = true
        windowPadding = 18
        cellCornerRadius = 10
        windowCornerRadius = 23
        intraCellPadding = 5
        interCellPadding = 1
        edgeInsetsSize = 7
        maxWidthOnScreen = isHorizontalScreen ? 0.6 : 0.8
        windowMinWidthInRow = 0.6
        windowMaxWidthInRow = 0.9
        rowsCount = 1
        switch currentSize {
        case .small:
            iconSize = 20
            fontHeight = 13
        case .medium:
            iconSize = 26
            fontHeight = 14
        case .large:
            iconSize = 32
            fontHeight = 16
        }
    }

    private static func lightTheme() {
        fontColor = .black.withAlphaComponent(0.8)
        titleShadowColor = nil
        indicatedIconShadowColor = nil
        imageShadowColor = .lightGray.withAlphaComponent(0.4)
        highlightMaterial = .mediumLight
        switch currentVisibility {
        case .normal:
            material = .light
            highlightFocusedBackgroundColor = .lightGray.withAlphaComponent(0.7)
            highlightHoveredBackgroundColor = .lightGray.withAlphaComponent(0.5)
            enablePanelShadow = false
            highlightFocusedAlphaValue = 1.0
            highlightHoveredAlphaValue = 0.8
            highlightFocusedBorderColor = NSColor.clear
            highlightHoveredBorderColor = NSColor.clear
            highlightBorderShadowColor = NSColor.clear
            highlightBorderWidth = 0
        case .high:
            material = .mediumLight
            highlightFocusedBackgroundColor = .lightGray.withAlphaComponent(0.7)
            highlightHoveredBackgroundColor = .lightGray.withAlphaComponent(0.5)
            enablePanelShadow = true
            highlightFocusedAlphaValue = 1.0
            highlightHoveredAlphaValue = 0.8
            highlightFocusedBorderColor = .lightGray.withAlphaComponent(0.9)
            highlightHoveredBorderColor = .lightGray.withAlphaComponent(0.8)
            highlightBorderShadowColor = .black.withAlphaComponent(0.5)
            highlightBorderWidth = 1

        case .highest:
            material = .mediumLight
            highlightFocusedBackgroundColor = .lightGray.withAlphaComponent(0.4)
            highlightHoveredBackgroundColor = .lightGray.withAlphaComponent(0.3)
            enablePanelShadow = true
            highlightFocusedAlphaValue = 0.4
            highlightHoveredAlphaValue = 0.2
            highlightFocusedBorderColor = NSColor.systemAccentColor
            highlightHoveredBorderColor = NSColor.systemAccentColor.withAlphaComponent(0.8)
            highlightBorderShadowColor = .black.withAlphaComponent(0.5)
            highlightBorderWidth = currentStyle == .titles ? 2 : 4
        }
    }

    private static func darkTheme() {
        fontColor = .white.withAlphaComponent(0.9)
        indicatedIconShadowColor = .darkGray
        titleShadowColor = .darkGray
        highlightMaterial = .ultraDark
        switch currentVisibility {
        case .normal:
            material = .dark
            imageShadowColor = .gray.withAlphaComponent(0.8)
            highlightFocusedBackgroundColor = .black.withAlphaComponent(0.6)
            highlightHoveredBackgroundColor = .black.withAlphaComponent(0.5)
            enablePanelShadow = false
            highlightFocusedAlphaValue = 1.0
            highlightHoveredAlphaValue = 0.8
            highlightFocusedBorderColor = NSColor.clear
            highlightHoveredBorderColor = NSColor.clear
            highlightBorderShadowColor = NSColor.clear
            highlightBorderWidth = 0
        case .high:
            material = .ultraDark
            imageShadowColor = .gray.withAlphaComponent(0.4)
            highlightFocusedBackgroundColor = .gray.withAlphaComponent(0.6)
            highlightHoveredBackgroundColor = .gray.withAlphaComponent(0.4)
            enablePanelShadow = true
            highlightFocusedAlphaValue = 1.0
            highlightHoveredAlphaValue = 0.8
            highlightFocusedBorderColor = .gray.withAlphaComponent(0.8)
            highlightHoveredBorderColor = .gray.withAlphaComponent(0.7)
            highlightBorderShadowColor = .white.withAlphaComponent(0.5)
            highlightBorderWidth = 1
        case .highest:
            material = .ultraDark
            imageShadowColor = .gray.withAlphaComponent(0.4)
            highlightFocusedBackgroundColor = .black.withAlphaComponent(0.4)
            highlightHoveredBackgroundColor = .black.withAlphaComponent(0.2)
            enablePanelShadow = true
            highlightFocusedAlphaValue = 0.4
            highlightHoveredAlphaValue = 0.2
            highlightFocusedBorderColor = NSColor.systemAccentColor
            highlightHoveredBorderColor = NSColor.systemAccentColor.withAlphaComponent(0.8)
            highlightBorderShadowColor = .white.withAlphaComponent(0.5)
            highlightBorderWidth = currentStyle == .titles ? 2 : 4
        }
    }

    // calculate windowMinWidthInRow and windowMaxWidthInRow such that:
    // * fullscreen windows fill their tile vertically
    // * narrow windows have enough width that a few words can be read from their title
    private static func goodValuesForThumbnailsWidthMinMax() -> (CGFloat, CGFloat) {
        let aspectRatio = NSScreen.preferred().ratio()
        let minRatio: CGFloat
        let maxRatio: CGFloat
        if aspectRatio >= 1 {
            minRatio = 0.7 / (aspectRatio * rowsCount)
            maxRatio = 1.5 / (aspectRatio * rowsCount)
        } else {
            minRatio = 1.3 / rowsCount
            maxRatio = 2.1 / rowsCount
        }
        // Make sure the values are clamped between some reasonable bounds
        return (max(0.09, minRatio), min(0.3, maxRatio))
    }

    // How wide should the ThumbnailsPanel be, for comfortable viewing?
    // * a comfortable field-of-view is 50-60 degrees
    // * people sit at various distances from the screen. We can't know how far they sit
    // * most people will seat far enough so that they can view the whole width of the screen
    // * some people use wide-screen or TV monitors. Those people tend to be too close to the screen, since they need to use keyboard and mouse on their desk
    // Let's use this heuristic: let's assume that people can view 60cm comfortably. Bigger screens can only show parts of AltTab
    // Let's clamp at 96% so there are 2% margins
    private static func comfortableWidth(_ physicalWidth: Double) -> Double {
        return min(0.96, 600.0 / physicalWidth)
    }

    /// Used for tuning. This is the latest output:
    ///   Width | Screen model
    ///    96% | 11" Laptop: MacBook Air 11"
    ///    96% | 13" Laptop: MacBook Air 13"
    ///    96% | 14" Laptop: MacBook Pro 14"
    ///    96% | 15" Laptop: MacBook Pro 15"
    ///    96% | 16" Laptop: MacBook Pro 16"
    ///    96% | 19" Monitor: Apple Studio Display 19"
    ///    96% | 20" Monitor: Apple Cinema Display 20"
    ///    96% | 21" Monitor: LG 21:9 UltraWide
    ///    96% | 22" Monitor: ASUS 22" Full HD
    ///    96% | 24" Monitor: Dell P2419H
    ///    96% | 27" Monitor: LG 27UK850-W
    ///    91% | 30" Monitor: BenQ PD3200U
    ///    84% | 32" Monitor: BenQ EW3270U
    ///    75% | 34" UltraWide Monitor: LG 34UC79G-B
    ///    84% | 32" TV: Samsung UE32T5300
    ///    67% | 40" TV: Samsung Q60B
    ///    63% | 43" TV: LG 43UN7300
    ///    54% | 50" TV: Samsung TU8000
    ///    50% | 55" TV: LG OLED55CXPUA
    ///    45% | 60" TV: Vizio 60-inch 4K
    private static func printCoverageTable() {
        let screens = [
            // screen model, width, height
            ("11\" Laptop: MacBook Air 11\"", 255.7, 178.6),
            ("13\" Laptop: MacBook Air 13\"", 304.1, 197.8),
            ("14\" Laptop: MacBook Pro 14\"", 311.0, 221.1),
            ("15\" Laptop: MacBook Pro 15\"", 344.4, 233.0),
            ("16\" Laptop: MacBook Pro 16\"", 358.4, 245.9),
            ("19\" Monitor: Apple Studio Display 19\"", 403, 236),
            ("20\" Monitor: Apple Cinema Display 20\"", 440, 268),
            ("21\" Monitor: LG 21:9 UltraWide", 470, 290),
            ("22\" Monitor: ASUS 22\" Full HD", 485, 290),
            ("24\" Monitor: Dell P2419H", 531.3, 298.6),
            ("27\" Monitor: LG 27UK850-W", 596.8, 336.4),
            ("30\" Monitor: BenQ PD3200U", 657.5, 376.3),
            ("32\" Monitor: BenQ EW3270U", 711.5, 398.9),
            ("34\" UltraWide Monitor: LG 34UC79G-B", 798.5, 336.5),
            ("32\" TV: Samsung UE32T5300", 715, 406),
            ("40\" TV: Samsung Q60B", 889, 510),
            ("43\" TV: LG 43UN7300", 956, 551),
            ("50\" TV: Samsung TU8000", 1110, 630),
            ("55\" TV: LG OLED55CXPUA", 1210, 715),
            ("60\" TV: Vizio 60-inch 4K", 1320, 750),
        ]
        print("Width | Screen model")
        for screen in screens {
            let percent = comfortableWidth(screen.1)
            print("\(String(format: "%4.0f%", percent * 100))% | \(screen.0)")
        }
    }
}
