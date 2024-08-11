import Cocoa

extension NSAppearance {

    func getThemeName() -> AppearanceThemeName {
        if #available(macOS 10.14, *) {
            let appearance = NSApp.effectiveAppearance.name
            if appearance == .darkAqua || appearance == .vibrantDark {
                return .dark
            }
        }
        return .light
    }
}

enum AppearanceThemeName: String {
    case light = "light"
    case dark = "dark"
}

struct AppearanceModelSizeParameters {
    var interCellPadding: CGFloat
    var intraCellPadding: CGFloat
    var hideThumbnails: Bool = false
    var rowsCount: CGFloat
    var windowMinWidthInRow: CGFloat
    var windowMaxWidthInRow: CGFloat
    var iconSize: CGFloat
    var fontHeight: CGFloat
    var maxWidthOnScreen: CGFloat
    var maxHeightOnScreen: CGFloat

    init(interCellPadding: CGFloat = 5,
         intraCellPadding: CGFloat = 5,
         hideThumbnails: Bool = false,
         rowsCount: CGFloat = 0,
         windowMinWidthInRow: CGFloat = 0,
         windowMaxWidthInRow: CGFloat = 0,
         iconSize: CGFloat = 0,
         fontHeight: CGFloat = 0,
         maxWidthOnScreen: CGFloat = 0,
         maxHeightOnScreen: CGFloat = 0) {
        self.interCellPadding = interCellPadding
        self.intraCellPadding = intraCellPadding
        self.hideThumbnails = hideThumbnails
        self.rowsCount = rowsCount
        self.windowMinWidthInRow = windowMinWidthInRow
        self.windowMaxWidthInRow = windowMaxWidthInRow
        self.iconSize = iconSize
        self.fontHeight = fontHeight
        self.maxWidthOnScreen = maxWidthOnScreen
        self.maxHeightOnScreen = maxHeightOnScreen
    }
}

class AppearanceModelSize {
    var model: AppearanceModelPreference
    var size: AppearanceSizePreference

    init(_ model: AppearanceModelPreference,
         _ size: AppearanceSizePreference) {
        self.model = model
        self.size = size
    }

    func getParameters() -> AppearanceModelSizeParameters {
        var appearance = AppearanceModelSizeParameters()
        let isVerticalScreen = NSScreen.preferred().ratio() < 1
        if model == AppearanceModelPreference.thumbnails {
            appearance.hideThumbnails = false
            appearance.intraCellPadding = 12
            appearance.interCellPadding = 3
            if size == AppearanceSizePreference.small {
                appearance.rowsCount = 5
                appearance.windowMinWidthInRow = 8
                appearance.windowMaxWidthInRow = 90
                appearance.iconSize = 25
                appearance.fontHeight = 15
                appearance.maxWidthOnScreen = 90
                appearance.maxHeightOnScreen = 80
                if isVerticalScreen {
                    appearance.rowsCount = 8
                }
            } else if size == AppearanceSizePreference.medium {
                appearance.rowsCount = 4
                appearance.windowMinWidthInRow = 10
                appearance.windowMaxWidthInRow = 90
                appearance.iconSize = 30
                appearance.fontHeight = 15
                appearance.maxWidthOnScreen = 90
                appearance.maxHeightOnScreen = 80
                if isVerticalScreen {
                    appearance.rowsCount = 7
                }
            } else if size == AppearanceSizePreference.large {
                appearance.rowsCount = 3
                appearance.windowMinWidthInRow = 10
                appearance.windowMaxWidthInRow = 90
                appearance.iconSize = 30
                appearance.fontHeight = 15
                appearance.maxWidthOnScreen = 90
                appearance.maxHeightOnScreen = 80
                if isVerticalScreen {
                    appearance.rowsCount = 6
                }
            }
        } else if model == AppearanceModelPreference.appIcons {
            appearance.hideThumbnails = true
            appearance.intraCellPadding = 5
            appearance.interCellPadding = 3
            appearance.fontHeight = 0
            appearance.maxWidthOnScreen = 95
            appearance.maxHeightOnScreen = 90
            if size == AppearanceSizePreference.small {
                appearance.rowsCount = 0
                appearance.windowMinWidthInRow = 5
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 68
            } else if size == AppearanceSizePreference.medium {
                appearance.rowsCount = 0
                appearance.windowMinWidthInRow = 6
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 98
            } else if size == AppearanceSizePreference.large {
                appearance.rowsCount = 0
                appearance.windowMinWidthInRow = 8
                appearance.windowMaxWidthInRow = 30
                appearance.iconSize = 128
            }
        } else if model == AppearanceModelPreference.titles {
            appearance.hideThumbnails = true
            appearance.intraCellPadding = 8
            appearance.interCellPadding = 3
            appearance.rowsCount = 0
            appearance.windowMinWidthInRow = 70
            appearance.windowMaxWidthInRow = 90
            appearance.maxWidthOnScreen = 60
            appearance.maxHeightOnScreen = 80
            if isVerticalScreen {
                appearance.maxWidthOnScreen = 85
            }
            if size == AppearanceSizePreference.small {
                appearance.iconSize = 25
                appearance.fontHeight = 13
            } else if size == AppearanceSizePreference.medium {
                appearance.iconSize = 30
                appearance.fontHeight = 15
            } else if size == AppearanceSizePreference.large {
                appearance.iconSize = 40
                appearance.fontHeight = 20
            }
        }
        return appearance
    }
}

struct AppearanceThemeParameters {
    var material: NSVisualEffectView.Material = .dark
    var fontColor: NSColor = .white
    var indicatedIconShadowColor: NSColor? = NSColor.darkGray
    var titleShadowColor: NSColor? = NSColor.darkGray
    var imageShadowColor: NSColor? = NSColor.gray       // for icon, thumbnail and windowless images
    var highlightFocusedBackgroundColor = NSColor.black.withAlphaComponent(0.5)
    var highlightHoveredBackgroundColor = NSColor.black.withAlphaComponent(0.3)
    var highlightBorderColor = NSColor.white
}

class AppearanceTheme {

    let themeName: AppearanceThemeName

    init(_ theme: AppearanceThemePreference) {
        self.themeName = AppearanceTheme.transform(theme)
    }

    static func transform(_ theme: AppearanceThemePreference) -> AppearanceThemeName {
        switch theme {
            case .light:
                return AppearanceThemeName.light
            case .dark:
                return AppearanceThemeName.dark
            case .automatic:
                return NSAppearance.current.getThemeName()
        }
    }

    func getParameters() -> AppearanceThemeParameters {
        var appearance = AppearanceThemeParameters()
        if self.themeName == .light {
            appearance.material = .light
            appearance.fontColor = NSColor.black.withAlphaComponent(0.8)
            appearance.indicatedIconShadowColor = nil
            appearance.titleShadowColor = nil
            appearance.imageShadowColor = NSColor.lightGray.withAlphaComponent(0.8)
            appearance.highlightFocusedBackgroundColor = NSColor.lightGray.withAlphaComponent(0.6)
            appearance.highlightHoveredBackgroundColor = NSColor.lightGray.withAlphaComponent(0.2)
            appearance.highlightBorderColor = NSColor.black.withAlphaComponent(0.8)
        } else {
            appearance.material = .dark
            appearance.fontColor = NSColor.white
            appearance.indicatedIconShadowColor = NSColor.darkGray
            appearance.titleShadowColor = NSColor.darkGray
            appearance.imageShadowColor = NSColor.gray
            appearance.highlightFocusedBackgroundColor = NSColor.black.withAlphaComponent(0.5)
            appearance.highlightHoveredBackgroundColor = NSColor.black.withAlphaComponent(0.2)
            appearance.highlightBorderColor = NSColor.white
        }
        return appearance
    }
}
