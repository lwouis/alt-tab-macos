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
            case .threeFingerHorizontalSwipe: return NSLocalizedString("Horizontal Swipe with Three Fingers", comment: "")
            case .threeFingerVerticalSwipe: return NSLocalizedString("Vertical Swipe with Three Fingers", comment: "")
            case .fourFingerHorizontalSwipe: return NSLocalizedString("Horizontal Swipe with Four Fingers", comment: "")
            case .fourFingerVerticalSwipe: return NSLocalizedString("Vertical Swipe with Four Fingers", comment: "")
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
    case japanese
    case chineseSimplified
    case chineseTraditional
    case korean

    var localizedString: String {
        switch self {
            case .systemDefault:
                return NSLocalizedString("System Default", comment: "")
            case .arabic:
                return "العربية"
            case .bulgarian:
                return "Български"
            case .bengali:
                return "বাংলা"
            case .catalan:
                return "Català"
            case .czech:
                return "Čeština"
            case .danish:
                return "Dansk"
            case .german:
                return "Deutsch"
            case .greek:
                return "Ελληνικά"
            case .english:
                return "English"
            case .spanish:
                return "Español"
            case .estonian:
                return "Eesti keel"
            case .persian:
                return "فارسی"
            case .finnish:
                return "Suomi"
            case .french:
                return "Français"
            case .irish:
                return "Gaeilge"
            case .galician:
                return "Galego"
            case .hebrew:
                return "עִבְרִית"
            case .hindi:
                return "हिन्दी"
            case .croatian:
                return "Hrvatski"
            case .hungarian:
                return "Magyar"
            case .indonesian:
                return "Bahasa Indonesia"
            case .icelandic:
                return "Íslenska"
            case .italian:
                return "Italiano"
            case .japanese:
                return "日本語"
            case .javanese:
                return "Basa Jawa"
            case .kannada:
                return "ಕನ್ನಡ"
            case .korean:
                return "한국어"
            case .kurdish:
                return "Kurdî"
            case .lithuanian:
                return "Lietuvių kalba"
            case .luxembourgish:
                return "Lëtzebuergesch"
            case .malayalam:
                return "മലയാളം"
            case .norwegianBokmal:
                return "Norsk Bokmål"
            case .dutch:
                return "Nederlands"
            case .norwegianNynorsk:
                return "Norsk Nynorsk"
            case .polish:
                return "Polski"
            case .portuguese:
                return "Português"
            case .portugueseBrasil:
                return "Português (Brasil)"
            case .romanian:
                return "Limba română"
            case .russian:
                return "Русский"
            case .slovak:
                return "Slovenčina"
            case .slovenian:
                return "Slovenščina"
            case .albanian:
                return "Shqip"
            case .serbian:
                return "Српски / Srpski"
            case .swedish:
                return "Svenska"
            case .tamil:
                return "தமிழ்"
            case .thai:
                return "ภาษาไทย"
            case .turkish:
                return "Türkçe"
            case .ukrainian:
                return "Українська"
            case .uzbek:
                return "Oʻzbekcha"
            case .vietnamese:
                return "Tiếng Việt"
            case .chineseSimplified:
                return "简体中文"
            case .chineseTraditional:
                return "繁體中文"
        }
    }

    var appleLanguageCode: String? {
        switch self {
            case .systemDefault:
                return nil
            case .arabic:
                return "ar"
            case .bulgarian:
                return "bg"
            case .bengali:
                return "bn"
            case .catalan:
                return "ca"
            case .czech:
                return "cs"
            case .danish:
                return "da"
            case .german:
                return "de"
            case .greek:
                return "el"
            case .english:
                return "en"
            case .spanish:
                return "es"
            case .estonian:
                return "et"
            case .persian:
                return "fa"
            case .finnish:
                return "fi"
            case .french:
                return "fr"
            case .irish:
                return "ga"
            case .galician:
                return "gl"
            case .hebrew:
                return "he"
            case .hindi:
                return "hi"
            case .croatian:
                return "hr"
            case .hungarian:
                return "hu"
            case .indonesian:
                return "id"
            case .icelandic:
                return "is"
            case .italian:
                return "it"
            case .japanese:
                return "ja"
            case .javanese:
                return "jv"
            case .kannada:
                return "kn"
            case .korean:
                return "ko"
            case .kurdish:
                return "ku"
            case .lithuanian:
                return "lt"
            case .luxembourgish:
                return "lb"
            case .malayalam:
                return "ml"
            case .norwegianBokmal:
                return "nb"
            case .dutch:
                return "nl"
            case .norwegianNynorsk:
                return "nn"
            case .polish:
                return "pl"
            case .portuguese:
                return "pt"
            case .portugueseBrasil:
                return "pt-BR"
            case .romanian:
                return "ro"
            case .russian:
                return "ru"
            case .slovak:
                return "sk"
            case .slovenian:
                return "sl"
            case .albanian:
                return "sq"
            case .serbian:
                return "sr"
            case .swedish:
                return "sv"
            case .tamil:
                return "ta"
            case .thai:
                return "th"
            case .turkish:
                return "tr"
            case .ukrainian:
                return "uk"
            case .uzbek:
                return "uz"
            case .vietnamese:
                return "vi"
            case .chineseSimplified:
                return "zh-CN"
            case .chineseTraditional:
                return "zh-TW"
        }
    }
}

enum ShortcutStylePreference: CaseIterable, MacroPreference {
    case focusOnRelease
    case doNothingOnRelease

    var localizedString: LocalizedString {
        switch self {
            case .focusOnRelease: return NSLocalizedString("Focus selected window", comment: "")
            case .doNothingOnRelease: return NSLocalizedString("Do nothing", comment: "")
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

// we can't reuse ShowHowPreference because the order of cases matters for serialization
enum ShowHowPreference2: CaseIterable, MacroPreference {
    case showAtTheEnd
    case hide

    var localizedString: LocalizedString {
        switch self {
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

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All apps", comment: "")
            case .active: return NSLocalizedString("Active app", comment: "")
        }
    }
}

enum SpacesToShowPreference: CaseIterable, MacroPreference {
    case all
    case visible

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All Spaces", comment: "")
            case .visible: return NSLocalizedString("Visible Spaces", comment: "")
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

    var localizedString: LocalizedString {
        switch self {
            case .small: return NSLocalizedString("Small", comment: "")
            case .medium: return NSLocalizedString("Medium", comment: "")
            case .large: return NSLocalizedString("Large", comment: "")
        }
    }

    var symbolName: String {
        switch self {
            case .small: return "moonphase.waning.gibbous.inverse"
            case .medium: return "moonphase.last.quarter.inverse"
            case .large: return "moonphase.waning.crescent.inverse"
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

enum AppearanceVisibilityPreference: CaseIterable, SfSymbolMacroPreference {
    case normal
    case high
    case highest

    var localizedString: LocalizedString {
        switch self {
            case .normal: return NSLocalizedString("Normal", comment: "")
            case .high: return NSLocalizedString("High", comment: "")
            case .highest: return NSLocalizedString("Highest", comment: "")
        }
    }

    var symbolName: String {
        switch self {
            case .normal: return "eye"
            case .high: return "eyeglasses"
            case .highest: return "binoculars.fill"
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

enum BlacklistHidePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenNoOpenWindow = "2"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenNoOpenWindow: return NSLocalizedString("When no open window", comment: "")
        }
    }
}

enum BlacklistIgnorePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
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
