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
    case javanese
    case catalan
    case danish
    case german
    case estonian
    case english
    case spanish
    case french
    case irish
    case galician
    case croatian
    case italian
    case kurdish
    case lithuanian
    case romanian
    case luxembourgish
    case hungarian
    case dutch
    case norwegianBokmal
    case norwegianNynorsk
    case uzbek
    case polish
    case portuguese
    case portugueseBrasil
    case albanian
    case slovak
    case slovenian
    case finnish
    case swedish
    case vietnamese
    case turkish
    case icelandic
    case czech
    case greek
    case belarusian
    case bulgarian
    case russian
    case serbian
    case ukrainian
    case hebrew
    case arabic
    case persian
    case hindi
    case bengali
    case tamil
    case kannada
    case malayalam
    case thai
    case burmese
    case japanese
    case chineseSimplified
    case chineseTraditional
    case chineseHongKong
    case korean

    private static let metadata: [LanguagePreference: (name: String, code: String?)] = [
        .systemDefault: (NSLocalizedString("System Default", comment: ""), nil),
        .arabic: ("العربية", "ar"),
        .belarusian: ("Беларуская мова", "be"),
        .bulgarian: ("Български", "bg"),
        .bengali: ("বাংলা", "bn"),
        .catalan: ("Català", "ca"),
        .czech: ("Čeština", "cs"),
        .danish: ("Dansk", "da"),
        .german: ("Deutsch", "de"),
        .greek: ("Ελληνικά", "el"),
        .english: ("English", "en"),
        .spanish: ("Español", "es"),
        .estonian: ("Eesti keel", "et"),
        .persian: ("فارسی", "fa"),
        .finnish: ("Suomi", "fi"),
        .french: ("Français", "fr"),
        .irish: ("Gaeilge", "ga"),
        .galician: ("Galego", "gl"),
        .hebrew: ("עִבְרִית", "he"),
        .hindi: ("हिन्दी", "hi"),
        .croatian: ("Hrvatski", "hr"),
        .hungarian: ("Magyar", "hu"),
        .indonesian: ("Bahasa Indonesia", "id"),
        .icelandic: ("Íslenska", "is"),
        .italian: ("Italiano", "it"),
        .burmese: ("မြန်မာဘာသာ", "my"),
        .japanese: ("日本語", "ja"),
        .javanese: ("Basa Jawa", "jv"),
        .kannada: ("ಕನ್ನಡ", "kn"),
        .korean: ("한국어", "ko"),
        .kurdish: ("Kurdî", "ku"),
        .lithuanian: ("Lietuvių", "lt"),
        .luxembourgish: ("Lëtzebuergesch", "lb"),
        .malayalam: ("മലയാളം", "ml"),
        .norwegianBokmal: ("Norsk Bokmål", "nb"),
        .dutch: ("Nederlands", "nl"),
        .norwegianNynorsk: ("Norsk Nynorsk", "nn"),
        .polish: ("Polski", "pl"),
        .portuguese: ("Português", "pt"),
        .portugueseBrasil: ("Português (Brasil)", "pt-BR"),
        .romanian: ("Română", "ro"),
        .russian: ("Русский", "ru"),
        .slovak: ("Slovenčina", "sk"),
        .slovenian: ("Slovenščina", "sl"),
        .albanian: ("Shqip", "sq"),
        .serbian: ("Српски", "sr"),
        .swedish: ("Svenska", "sv"),
        .tamil: ("தமிழ்", "ta"),
        .thai: ("ภาษาไทย", "th"),
        .turkish: ("Türkçe", "tr"),
        .ukrainian: ("Українська", "uk"),
        .uzbek: ("Oʻzbekcha", "uz"),
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

enum ShortcutStylePreference: CaseIterable, MacroPreference {
    case focusOnRelease
    case doNothingOnRelease
    case searchOnRelease

    var localizedString: LocalizedString {
        switch self {
            case .focusOnRelease: return NSLocalizedString("Focus selected window", comment: "")
            case .doNothingOnRelease: return NSLocalizedString("Keep open", comment: "")
            case .searchOnRelease: return NSLocalizedString("Keep open and search", comment: "")
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

enum ShowAppsOrWindowsPreference: CaseIterable, MacroPreference {
    case applications
    case windows

    var localizedString: LocalizedString {
        switch self {
            case .applications: return NSLocalizedString("Applications", comment: "")
            case .windows: return NSLocalizedString("Windows", comment: "")
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

enum AlignThumbnailsPreference: CaseIterable, ImageMacroPreference {
    case leading
    case center

    var localizedString: LocalizedString {
        switch self {
            case .leading: return NSLocalizedString("Leading", comment: "")
            case .center: return NSLocalizedString("Center", comment: "")
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .leading: return WidthHeightImage(name: "align_thumbnails_leading")
            case .center: return WidthHeightImage(name: "align_thumbnails_center")
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

    var symbolName: String {
        switch self {
            case .small: return "moonphase.waning.gibbous.inverse"
            case .medium: return "moonphase.last.quarter.inverse"
            case .large: return "moonphase.waning.crescent.inverse"
            case .auto: return "sparkles"
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

    var symbolName: String {
        switch self {
            case .light: return "sun.max"
            case .dark: return "moon.fill"
            case .system: return "laptopcomputer"
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
    var symbolName: String { get }
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
