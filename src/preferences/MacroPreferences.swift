enum MenubarIconPreference: CaseIterable, MacroPreference {
    case outlined
    case filled
    case colored

    var localizedString: LocalizedString {
        switch self {
            // these spaces are different from each other; they have to be unique
            case .outlined: return " "
            case .filled: return " "
            case .colored: return " "
        }
    }
}

enum GesturePreference: CaseIterable, MacroPreference {
    case disabled
    case threeFingerHorizontalSwipe
    case threeFingerVerticalSwipe
    case fourFingerHorizontalSwipe
    case fourFingerVerticalSwipe

    var localizedString: LocalizedString {
        switch self {
            case .disabled: return NSLocalizedString("Disabled", comment: "")
            case .threeFingerHorizontalSwipe: return NSLocalizedString("3-finger Horizontal Swipe", comment: "")
            case .threeFingerVerticalSwipe: return NSLocalizedString("3-finger Vertical Swipe", comment: "")
            case .fourFingerHorizontalSwipe: return NSLocalizedString("4-finger Horizontal Swipe", comment: "")
            case .fourFingerVerticalSwipe: return NSLocalizedString("4-finger Vertical Swipe", comment: "")
        }
    }

    func isHorizontal() -> Bool {
        return self == .threeFingerHorizontalSwipe || self == .fourFingerHorizontalSwipe
    }

    func isThreeFinger() -> Bool {
        return self == .threeFingerHorizontalSwipe || self == .threeFingerVerticalSwipe
    }
}

enum LanguagePreference: CaseIterable, MacroPreference {
    case systemDefault
    case indonesian
    case german
    case english
    case spanish
    case french
    case italian
    case dutch
    case polish
    case portugueseBrasil
    case swedish
    case vietnamese
    case turkish
    case russian
    case hebrew
    case arabic
    case thai
    case japanese
    case chineseSimplified
    case chineseTraditional
    case chineseHongKong
    case korean

    private static let metadata: [LanguagePreference: (name: String, code: String?)] = [
        .systemDefault: (NSLocalizedString("System Default", comment: ""), nil),
        .arabic: ("العربية", "ar"),
        .german: ("Deutsch", "de"),
        .english: ("English", "en"),
        .spanish: ("Español", "es"),
        .hebrew: ("עִבְרִית", "he"),
        .french: ("Français", "fr"),
        .indonesian: ("Bahasa Indonesia", "id"),
        .italian: ("Italiano", "it"),
        .japanese: ("日本語", "ja"),
        .korean: ("한국어", "ko"),
        .dutch: ("Nederlands", "nl"),
        .polish: ("Polski", "pl"),
        .portugueseBrasil: ("Português (Brasil)", "pt-BR"),
        .russian: ("Русский", "ru"),
        .swedish: ("Svenska", "sv"),
        .thai: ("ภาษาไทย", "th"),
        .turkish: ("Türkçe", "tr"),
        .vietnamese: ("Tiếng Việt", "vi"),
        .chineseSimplified: ("简体中文", "zh-CN"),
        .chineseTraditional: ("繁體中文", "zh-TW"),
        .chineseHongKong: ("繁體中文 (香港)", "zh-HK"),
    ]

    var localizedString: String {
        Self.metadata[self]!.name
    }

    var appleLanguageCode: String? {
        Self.metadata[self]!.code
    }
}

enum ShortcutStylePreference: CaseIterable, SfSymbolMacroPreference {
    case focusOnRelease
    case doNothingOnRelease
    case searchOnRelease

    var localizedString: LocalizedString {
        switch self {
            case .focusOnRelease: return NSLocalizedString("Focus", comment: "")
            case .doNothingOnRelease: return NSLocalizedString("Hold", comment: "")
            case .searchOnRelease: return NSLocalizedString("Search", comment: "")
        }
    }

    var symbol: Symbols {
        switch self {
            case .focusOnRelease: return .cursorarrowRays
            case .doNothingOnRelease: return .pauseRectangle
            case .searchOnRelease: return .magnifyingglass
        }
    }
}

enum ShowHowPreference: CaseIterable, MacroPreference {
    case show
    case hide
    case showAtTheEnd

    var localizedString: LocalizedString {
        switch self {
            case .show: return NSLocalizedString("Show", comment: "")
            case .showAtTheEnd: return NSLocalizedString("Show at the end", comment: "")
            case .hide: return NSLocalizedString("Hide", comment: "")
        }
    }
}

enum WindowOrderPreference: CaseIterable, MacroPreference {
    case recentlyFocused
    case recentlyCreated
    case alphabetical
    case space

    var localizedString: LocalizedString {
        switch self {
            case .recentlyFocused: return NSLocalizedString("Recently Focused First", comment: "")
            case .recentlyCreated: return NSLocalizedString("Recently Created First", comment: "")
            case .alphabetical: return NSLocalizedString("Alphabetical Order", comment: "")
            case .space: return NSLocalizedString("Space Order", comment: "")
        }
    }
}

enum AppsToShowPreference: CaseIterable, MacroPreference {
    case all
    case active
    case nonActive

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All apps", comment: "")
            case .active: return NSLocalizedString("Active app", comment: "")
            case .nonActive: return NSLocalizedString("Non-active apps", comment: "")
        }
    }
}

enum SpacesToShowPreference: CaseIterable, MacroPreference {
    case all
    case visible
    case nonVisible

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All Spaces", comment: "")
            case .visible: return NSLocalizedString("Visible Spaces", comment: "")
            case .nonVisible: return NSLocalizedString("Non-visible Spaces", comment: "")
        }
    }
}

enum ScreensToShowPreference: CaseIterable, MacroPreference {
    case all
    case showingAltTab

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All screens", comment: "")
            case .showingAltTab: return NSLocalizedString("Screen showing AltTab", comment: "")
        }
    }
}

enum ShowOnScreenPreference: CaseIterable, MacroPreference {
    case active
    case includingMouse
    case includingMenubar

    var localizedString: LocalizedString {
        switch self {
            case .active: return NSLocalizedString("Active screen", comment: "")
            case .includingMouse: return NSLocalizedString("Screen including mouse", comment: "")
            case .includingMenubar: return NSLocalizedString("Screen including menu bar", comment: "")
        }
    }
}

enum TitleTruncationPreference: CaseIterable, MacroPreference {
    case start
    case middle
    case end

    var localizedString: LocalizedString {
        switch self {
            case .start: return NSLocalizedString("Start", comment: "")
            case .middle: return NSLocalizedString("Middle", comment: "")
            case .end: return NSLocalizedString("End", comment: "")
        }
    }
}

enum GroupAppsPreference: CaseIterable, MacroPreference {
    case mainWindow
    case allWindows

    var localizedString: LocalizedString {
        switch self {
            case .mainWindow: return NSLocalizedString("Show main window", comment: "")
            case .allWindows: return NSLocalizedString("Show all windows", comment: "")
        }
    }
}

/// Mirrors `showTabsAsWindows` as a 2-case enum so the per-shortcut UI renders a dropdown rather
/// than a switch. Persistence is by index (`"0"` / `"1"`), so `singleWindow` MUST stay at index 0
/// and `separateWindows` at index 1 — the migration that converts the old `"true"`/`"false"` Bool
/// strings relies on that mapping (true → separateWindows = "1", false → singleWindow = "0").
enum GroupTabsPreference: CaseIterable, MacroPreference {
    case singleWindow
    case separateWindows

    var localizedString: LocalizedString {
        switch self {
            case .singleWindow: return NSLocalizedString("Show single window for all tabs", comment: "")
            case .separateWindows: return NSLocalizedString("Show separate window for each tab", comment: "")
        }
    }
}

enum CursorFollowFocus: CaseIterable, MacroPreference {
    case never
    case always
    case differentScreen

    var localizedString: LocalizedString {
        switch self {
            case .never: return NSLocalizedString("Never", comment: "")
            case .always: return NSLocalizedString("Always", comment: "")
            case .differentScreen: return NSLocalizedString("Only on different screen", comment: "")
        }
    }
}

enum ShowTitlesPreference: CaseIterable, MacroPreference {
    case windowTitle
    case appName
    case appNameAndWindowTitle

    var localizedString: LocalizedString {
        switch self {
            case .windowTitle: return NSLocalizedString("Window Title", comment: "")
            case .appName: return NSLocalizedString("Application Name", comment: "")
            case .appNameAndWindowTitle: return NSLocalizedString("Application Name - Window Title", comment: "")
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .windowTitle: return WidthHeightImage(name: "show_running_windows")
            case .appName: return WidthHeightImage(name: "show_running_applications")
            case .appNameAndWindowTitle: return WidthHeightImage(name: "show_running_applications_windows")
        }
    }
}

enum AppearanceStylePreference: CaseIterable, ImageMacroPreference {
    case thumbnails
    case appIcons
    case titles

    var localizedString: LocalizedString {
        switch self {
            case .thumbnails: return NSLocalizedString("Thumbnails", comment: "")
            case .appIcons: return NSLocalizedString("App Icons", comment: "")
            case .titles: return NSLocalizedString("Titles", comment: "")
        }
    }

    var image: WidthHeightImage {
        let width = CGFloat(150)
        let height = width / 1.6
        switch self {
            case .thumbnails: return WidthHeightImage(width: width, height: height, name: "thumbnails")
            case .appIcons: return WidthHeightImage(width: width, height: height, name: "app_icons")
            case .titles: return WidthHeightImage(width: width, height: height, name: "titles")
        }
    }
}

enum AppearanceSizePreference: CaseIterable, SfSymbolMacroPreference {
    case small
    case medium
    case large
    case auto

    var localizedString: LocalizedString {
        switch self {
            case .small: return NSLocalizedString("Small", comment: "")
            case .medium: return NSLocalizedString("Medium", comment: "")
            case .large: return NSLocalizedString("Large", comment: "")
            case .auto: return NSLocalizedString("Auto", comment: "")
        }
    }

    var symbol: Symbols {
        switch self {
            case .small: return .moonphaseWaningGibbousInverse
            case .medium: return .moonphaseLastQuarterInverse
            case .large: return .moonphaseWaningCrescentInverse
            case .auto: return .sparkles
        }
    }
}

enum ThemePreference: CaseIterable, ImageMacroPreference {
    case macOs
    case windows10

    var localizedString: LocalizedString {
        switch self {
            case .macOs: return " macOS"
            case .windows10: return "❖ Windows 10"
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .macOs: return WidthHeightImage(name: "macos")
            case .windows10: return WidthHeightImage(name: "windows10")
        }
    }

    // periphery:ignore
    var themeParameters: ThemeParameters {
        switch self {
            case .macOs: return ThemeParameters(label: localizedString, cellCornerRadius: 10, windowCornerRadius: 23)
            case .windows10: return ThemeParameters(label: localizedString, cellCornerRadius: 0, windowCornerRadius: 0)
        }
    }
}

enum AppearanceThemePreference: CaseIterable, SfSymbolMacroPreference {
    case light
    case dark
    case system

    var localizedString: LocalizedString {
        switch self {
            case .light: return NSLocalizedString("Light", comment: "")
            case .dark: return NSLocalizedString("Dark", comment: "")
            case .system: return NSLocalizedString("System", comment: "")
        }
    }

    var symbol: Symbols {
        switch self {
            case .light: return .sunMax
            case .dark: return .moonFill
            case .system: return .laptopcomputer
        }
    }
}

enum UpdatePolicyPreference: CaseIterable, MacroPreference {
    case manual
    case autoCheck
    case autoInstall

    var localizedString: LocalizedString {
        switch self {
            case .manual: return NSLocalizedString("Don’t check for updates periodically", comment: "")
            case .autoCheck: return NSLocalizedString("Check for updates periodically", comment: "")
            case .autoInstall: return NSLocalizedString("Auto-install updates periodically", comment: "")
        }
    }
}

enum CrashPolicyPreference: CaseIterable, MacroPreference {
    case never
    case ask
    case always

    var localizedString: LocalizedString {
        switch self {
            case .never: return NSLocalizedString("Never send crash reports", comment: "")
            case .ask: return NSLocalizedString("Ask whether to send crash reports", comment: "")
            case .always: return NSLocalizedString("Always send crash reports", comment: "")
        }
    }
}

enum ExceptionHidePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenNoOpenWindow = "2"
    case windowTitleContains = "3"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenNoOpenWindow: return NSLocalizedString("When no open window", comment: "")
            case .windowTitleContains: return NSLocalizedString("Window title contains", comment: "")
        }
    }
}

enum ExceptionIgnorePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenFullscreen = "2"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenFullscreen: return NSLocalizedString("When fullscreen", comment: "")
        }
    }
}

// MacroPreference are collection of values derived from a single key
// we don't want to store every value in UserDefaults as the user could change them and contradict the macro
protocol MacroPreference {
    var localizedString: LocalizedString { get }
}

protocol SfSymbolMacroPreference: MacroPreference {
    var symbol: Symbols { get }
}

protocol ImageMacroPreference: MacroPreference {
    var image: WidthHeightImage { get }
}

struct WidthHeightImage {
    var width: CGFloat
    var height: CGFloat
    var name: String

    init(width: CGFloat = 80, height: CGFloat = 50, name: String) {
        self.width = width
        self.height = height
        self.name = name
    }
}

// periphery:ignore
struct ThemeParameters {
    let label: String
    let cellCornerRadius: CGFloat
    let windowCornerRadius: CGFloat
}

typealias LocalizedString = String
