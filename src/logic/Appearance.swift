import Cocoa

struct AppearanceSizeParameters {
    var interCellPadding: CGFloat = 5
    var intraCellPadding: CGFloat = 1
    var edgeInsetsSize: CGFloat = 5
    var hideThumbnails: Bool = false
    var rowsCount: CGFloat = 0
    var windowMinWidthInRow: CGFloat = 0
    var windowMaxWidthInRow: CGFloat = 0
    var iconSize: CGFloat = 0
    var fontHeight: CGFloat = 0
    var maxWidthOnScreen: CGFloat = 0
    var maxHeightOnScreen: CGFloat = 0
}

class AppearanceSize {
    var style: AppearanceStylePreference
    var size: AppearanceSizePreference

    init(_ style: AppearanceStylePreference, _ size: AppearanceSizePreference) {
        self.style = style
        self.size = size
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
                appearance.iconSize = 25
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
                appearance.iconSize = 30
                appearance.fontHeight = 16
                if isVerticalScreen {
                    appearance.rowsCount = 6
                }
            }
        } else if style == .appIcons {
            appearance.hideThumbnails = true
            appearance.intraCellPadding = 5
            appearance.interCellPadding = 1
            appearance.edgeInsetsSize = 5
            appearance.fontHeight = 15
            appearance.maxWidthOnScreen = 95
            appearance.maxHeightOnScreen = 90
            if size == .small {
                appearance.rowsCount = 0
                appearance.windowMinWidthInRow = 5
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 68
            } else if size == .medium {
                appearance.rowsCount = 0
                appearance.windowMinWidthInRow = 6
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 98
            } else if size == .large {
                appearance.rowsCount = 0
                appearance.windowMinWidthInRow = 8
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 128
            }
        } else if style == .titles {
            appearance.hideThumbnails = true
            appearance.intraCellPadding = 5
            appearance.interCellPadding = 1
            appearance.edgeInsetsSize = 7
            appearance.rowsCount = 0
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
                appearance.fontHeight = 20
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
    var imageShadowColor: NSColor? = .gray       // for icon, thumbnail and windowless images
    var highlightFocusedBackgroundColor = NSColor.black.withAlphaComponent(0.5)
    var highlightHoveredBackgroundColor = NSColor.black.withAlphaComponent(0.3)
    var highlightFocusedBorderColor = NSColor.clear
    var highlightHoveredBorderColor = NSColor.clear
    var highlightBorderShadowColor = NSColor.clear
    var panelHasShadow = false
}

class AppearanceTheme {
    let themeName: AppearanceThemeName
    let appearanceHighVisibility = Preferences.appearanceHighVisibility

    init(_ theme: AppearanceThemePreference) {
        self.themeName = AppearanceTheme.transform(theme)
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
        if self.themeName == .light {
            appearance.material = .light
            appearance.fontColor = .black.withAlphaComponent(0.8)
            appearance.indicatedIconShadowColor = nil
            appearance.titleShadowColor = nil
            appearance.imageShadowColor = .lightGray.withAlphaComponent(0.8)
            appearance.highlightFocusedBackgroundColor = .lightGray.withAlphaComponent(0.7)
            appearance.highlightHoveredBackgroundColor = .lightGray.withAlphaComponent(0.4)
            appearance.highlightFocusedBorderColor = .clear
            appearance.highlightHoveredBorderColor = .clear
            appearance.panelHasShadow = false

            if appearanceHighVisibility {
                appearance.material = .mediumLight
                appearance.highlightFocusedBorderColor = .white.withAlphaComponent(0.7)
                appearance.highlightHoveredBorderColor = .white.withAlphaComponent(0.6)
                appearance.highlightBorderShadowColor = .black

                appearance.panelHasShadow = true
            }
        } else {
            appearance.material = .dark
            appearance.fontColor = .white.withAlphaComponent(0.9)
            appearance.indicatedIconShadowColor = .darkGray
            appearance.titleShadowColor = .darkGray
            appearance.imageShadowColor = .gray.withAlphaComponent(0.8)
            appearance.highlightFocusedBackgroundColor = .black.withAlphaComponent(0.5)
            appearance.highlightHoveredBackgroundColor = .black.withAlphaComponent(0.3)
            appearance.highlightFocusedBorderColor = .clear
            appearance.highlightHoveredBorderColor = .clear
            appearance.panelHasShadow = false

            if appearanceHighVisibility {
                appearance.material = .ultraDark
                appearance.highlightFocusedBorderColor = .black.withAlphaComponent(0.8)
                appearance.highlightHoveredBorderColor = .black.withAlphaComponent(0.6)
                appearance.highlightBorderShadowColor = .white
                appearance.panelHasShadow = true
            }
        }
        return appearance
    }
}

enum AppearanceThemeName: String {
    case light = "light"
    case dark = "dark"
}
