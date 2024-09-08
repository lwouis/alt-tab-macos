import Cocoa

struct AppearanceSizeParameters {
    var windowPadding = CGFloat(18)
    var interCellPadding = CGFloat(5)
    var intraCellPadding = CGFloat(1)
    var edgeInsetsSize = CGFloat(5)
    var cellCornerRadius = CGFloat(10)
    var windowCornerRadius = CGFloat(23)
    var hideThumbnails = Bool(false)
    var rowsCount = CGFloat(0)
    var windowMinWidthInRow = CGFloat(0)
    var windowMaxWidthInRow = CGFloat(0)
    var iconSize = CGFloat(0)
    var fontHeight = CGFloat(0)
    var maxWidthOnScreen = CGFloat(0)
    var maxHeightOnScreen = CGFloat(0)
}

class AppearanceSize {
    var style: AppearanceStylePreference
    var size: AppearanceSizePreference
    var visibility: AppearanceVisibilityPreference

    init(_ style: AppearanceStylePreference,
         _ size: AppearanceSizePreference,
         _ visibility: AppearanceVisibilityPreference) {
        self.style = style
        self.size = size
        self.visibility = visibility
    }

    func getParameters() -> AppearanceSizeParameters {
        var appearance = AppearanceSizeParameters()
        let isVerticalScreen = NSScreen.preferred().ratio() < 1
        if style == .thumbnails {
            appearance.hideThumbnails = false
            appearance.intraCellPadding = 5
            appearance.interCellPadding = 1
            appearance.edgeInsetsSize = 12
            appearance.maxWidthOnScreen = 90
            appearance.maxHeightOnScreen = 80
            if size == .small {
                appearance.rowsCount = 5
                appearance.windowMinWidthInRow = 8
                appearance.windowMaxWidthInRow = 90
                appearance.iconSize = 30
                appearance.fontHeight = 14
                if isVerticalScreen {
                    appearance.rowsCount = 8
                }
            } else if size == .medium {
                appearance.rowsCount = 4
                appearance.windowMinWidthInRow = 10
                appearance.windowMaxWidthInRow = 90
                appearance.iconSize = 30
                appearance.fontHeight = 15
                if isVerticalScreen {
                    appearance.rowsCount = 7
                }
            } else if size == .large {
                appearance.rowsCount = 3
                appearance.windowMinWidthInRow = 10
                appearance.windowMaxWidthInRow = 90
                appearance.iconSize = 40
                appearance.fontHeight = 18
                if isVerticalScreen {
                    appearance.rowsCount = 6
                }
            }
            if visibility == .highest {
                appearance.edgeInsetsSize = 12
                appearance.cellCornerRadius = 12
            }
        } else if style == .appIcons {
            appearance.hideThumbnails = true
            appearance.windowPadding = 25
            appearance.intraCellPadding = 5
            appearance.interCellPadding = 1
            appearance.edgeInsetsSize = 5
            appearance.rowsCount = 1
            appearance.fontHeight = 15
            appearance.maxWidthOnScreen = 95
            appearance.maxHeightOnScreen = 90
            if size == .small {
                appearance.windowMinWidthInRow = 4
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 88
            } else if size == .medium {
                appearance.windowMinWidthInRow = 4
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 128
            } else if size == .large {
                appearance.windowPadding = 28
                appearance.windowMinWidthInRow = 4
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 168
                appearance.fontHeight = 20
            }
        } else if style == .titles {
            appearance.hideThumbnails = true
            appearance.intraCellPadding = 5
            appearance.interCellPadding = 1
            appearance.edgeInsetsSize = 7
            appearance.rowsCount = 1
            appearance.windowMinWidthInRow = 60
            appearance.windowMaxWidthInRow = 90
            appearance.maxWidthOnScreen = 60
            appearance.maxHeightOnScreen = 80
            if isVerticalScreen {
                appearance.maxWidthOnScreen = 85
            }
            if size == .small {
                appearance.iconSize = 25
                appearance.fontHeight = 13
            } else if size == .medium {
                appearance.iconSize = 30
                appearance.fontHeight = 15
            } else if size == .large {
                appearance.iconSize = 40
                appearance.fontHeight = 18
            }
        }
        return appearance
    }
}

struct AppearanceThemeParameters {
    var material = NSVisualEffectView.Material.dark
    var fontColor = NSColor.white
    var indicatedIconShadowColor: NSColor? = .darkGray
    var titleShadowColor: NSColor? = .darkGray
    var imageShadowColor: NSColor? = .gray // for icon, thumbnail and windowless images
    var highlightMaterial = NSVisualEffectView.Material.selection
    var highlightFocusedAlphaValue = 1.0
    var highlightHoveredAlphaValue = 0.8
    var highlightFocusedBackgroundColor = NSColor.black.withAlphaComponent(0.5)
    var highlightHoveredBackgroundColor = NSColor.black.withAlphaComponent(0.3)
    var highlightFocusedBorderColor = NSColor.clear
    var highlightHoveredBorderColor = NSColor.clear
    var highlightBorderShadowColor = NSColor.clear
    var highlightBorderWidth = CGFloat(0)
    var enablePanelShadow = false
}

class AppearanceTheme {
    let themeName: AppearanceThemeName
    let appearanceStyle: AppearanceStylePreference
    var visibility: AppearanceVisibilityPreference

    init(_ appearanceStyle: AppearanceStylePreference,
         _ theme: AppearanceThemePreference,
         _ visibility: AppearanceVisibilityPreference) {
        self.appearanceStyle = appearanceStyle
        self.visibility = visibility
        themeName = AppearanceTheme.transform(theme)
    }

    static func transform(_ theme: AppearanceThemePreference) -> AppearanceThemeName {
        switch theme {
        case .light:
            return AppearanceThemeName.light
        case .dark:
            return AppearanceThemeName.dark
        case .system:
            return NSAppearance.current.getThemeName()
        }
    }

    func getParameters() -> AppearanceThemeParameters {
        var appearance = AppearanceThemeParameters()
        if themeName == .light {
            appearance.material = .light
            appearance.fontColor = .black.withAlphaComponent(0.8)
            appearance.indicatedIconShadowColor = nil
            appearance.titleShadowColor = nil
            appearance.imageShadowColor = .lightGray.withAlphaComponent(0.4)
            appearance.highlightMaterial = .mediumLight
            appearance.highlightFocusedBackgroundColor = .lightGray.withAlphaComponent(0.7)
            appearance.highlightHoveredBackgroundColor = .lightGray.withAlphaComponent(0.5)
            appearance.enablePanelShadow = false

            if visibility == .high || visibility == .highest {
                appearance.material = .mediumLight
                appearance.imageShadowColor = .lightGray.withAlphaComponent(0.4)
                appearance.highlightFocusedBorderColor = .lightGray.withAlphaComponent(0.9)
                appearance.highlightHoveredBorderColor = .lightGray.withAlphaComponent(0.8)
                appearance.highlightBorderShadowColor = .black.withAlphaComponent(0.5)
                appearance.highlightBorderWidth = 1
                appearance.enablePanelShadow = true
            }
            if visibility == .highest {
                appearance.highlightFocusedAlphaValue = 0.4
                appearance.highlightHoveredAlphaValue = 0.2
                appearance.highlightFocusedBackgroundColor = .lightGray.withAlphaComponent(0.4)
                appearance.highlightHoveredBackgroundColor = .lightGray.withAlphaComponent(0.3)
                appearance.highlightFocusedBorderColor = NSColor.systemAccentColor
                appearance.highlightHoveredBorderColor = NSColor.systemAccentColor.withAlphaComponent(0.8)
                appearance.highlightBorderWidth = appearanceStyle == .titles ? 2 : 4
            }
        } else {
            appearance.material = .dark
            appearance.fontColor = .white.withAlphaComponent(0.9)
            appearance.indicatedIconShadowColor = .darkGray
            appearance.titleShadowColor = .darkGray
            appearance.imageShadowColor = .gray.withAlphaComponent(0.8)
            appearance.highlightMaterial = .ultraDark
            appearance.highlightFocusedBackgroundColor = .black.withAlphaComponent(0.6)
            appearance.highlightHoveredBackgroundColor = .black.withAlphaComponent(0.5)
            appearance.enablePanelShadow = false

            if visibility == .high || visibility == .highest {
                appearance.material = .ultraDark
                appearance.imageShadowColor = .gray.withAlphaComponent(0.4)
                appearance.highlightFocusedBackgroundColor = .gray.withAlphaComponent(0.6)
                appearance.highlightHoveredBackgroundColor = .gray.withAlphaComponent(0.4)
                appearance.highlightFocusedBorderColor = .gray.withAlphaComponent(0.8)
                appearance.highlightHoveredBorderColor = .gray.withAlphaComponent(0.7)
                appearance.highlightBorderShadowColor = .white.withAlphaComponent(0.5)
                appearance.highlightBorderWidth = 1
                appearance.enablePanelShadow = true
            }
            if visibility == .highest {
                appearance.highlightFocusedAlphaValue = 0.4
                appearance.highlightHoveredAlphaValue = 0.2
                appearance.highlightFocusedBackgroundColor = .black.withAlphaComponent(0.4)
                appearance.highlightHoveredBackgroundColor = .black.withAlphaComponent(0.2)
                appearance.highlightFocusedBorderColor = NSColor.systemAccentColor
                appearance.highlightHoveredBorderColor = NSColor.systemAccentColor.withAlphaComponent(0.8)
                appearance.highlightBorderWidth = appearanceStyle == .titles ? 2 : 4
            }
        }
        return appearance
    }
}

enum AppearanceThemeName: String {
    case light
    case dark
}
