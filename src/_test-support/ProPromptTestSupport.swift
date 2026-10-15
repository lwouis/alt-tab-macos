import Cocoa

// The production coordinator, host, popover content, buttons and anchor run in this target.
// Persistence, unrelated windows and desktop services are replaced; no test starts the app,
// changes license defaults, contacts checkout or presents a native window.
class ProTransitionState {
    static let suite = "com.lwouis.alt-tab-macos.tests.ProPromptFlow"
    static let defaults = UserDefaults(suiteName: suite)!
    var value = ProTransitionManagerTestable.State.fresh()
    var onboardingInProgress = false
    var rememberedAppearanceStyle: Int?
    var rememberedShortcutStyle: Int?
    var messages = 0
    var intents = [ProJourneyFeature]()
    var hasSeenWelcome: Bool { get { value.hasSeenWelcome } set { value.hasSeenWelcome = newValue } }
    var hasSeenDay4Tour: Bool { get { value.hasSeenDay4Tour } set { value.hasSeenDay4Tour = newValue } }
    var day4TourDeferred: Bool { get { value.day4TourDeferred } set { value.day4TourDeferred = newValue } }
    var freePassUsed: Bool { get { value.freePassUsed } set { value.freePassUsed = newValue } }
    var hasSeenFullUpgrade: Bool { get { value.hasSeenFullUpgrade } set { value.hasSeenFullUpgrade = newValue } }
    var hasSeenProactiveDay15: Bool { get { value.hasSeenProactiveDay15 } set { value.hasSeenProactiveDay15 = newValue } }
    var userOptedOut: Bool { get { value.userOptedOut } set { value.userOptedOut = newValue } }
    var hasTriggeredPostExpirationSwitcher: Bool {
        get { value.hasTriggeredPostExpirationSwitcher }
        set { value.hasTriggeredPostExpirationSwitcher = newValue }
    }
    func snapshot(licenseState: LicenseState, daysSinceTrialStart: Int, clock: Clock) -> ProTransitionManagerTestable.State { value }
    func recordIntent(_ feature: ProJourneyFeature) { intents.append(feature) }
    func recordMessage() { messages += 1 }
    func messageShownToday(_ now: Date) -> Bool { value.messageShownToday }
    func onProLockEngaged() {}
    func onProUnlocked() {}
    func resetAll() { value = .fresh() }
}

extension App {
    static var hideUiCount = 0
    static func hideUi() {
        hideUiCount += 1
        SwitcherSession.current = nil
    }
    static func resetPreferencesDependentComponents() {}
}

enum AppearanceStylePreference: CaseIterable { case thumbnails, appIcons, titles }
extension Preferences {
    static var appearanceStyle: AppearanceStylePreference { .thumbnails }
    static func effectiveAppearanceStyle(_ index: Int) -> AppearanceStylePreference { appearanceStyle }
}

enum ProGatedPreferences {
    struct Gate { func isStoredValuePro() -> Bool { false } }
    static func forPreferenceKey(_ key: String) -> Gate? { nil }
}

enum QaLifecycle {
    static let enabled = false
    static var actions = [String]()
}

enum ScreenLockEvents { static var isScreenLocked = false }
enum ContextMenuEvents { static var isMenuOpen = false }
enum Menubar {
    static var statusItem: NSStatusItem?
    static func menubarIconCallback(_ sender: Any?) {}
}
enum Applications { static let frontmostPid: pid_t = 0 }
enum Windows {
    struct Application { let pid: pid_t }
    struct Window { let application: Application; let isFullscreen: Bool }
    static let list = [Window]()
}
class SearchDiscoveryHint {
    static let shared = SearchDiscoveryHint()
    func cancel() {}
}
class PermissionsWindow: NSWindow {}
class FeedbackWindow: NSWindow {}
enum Day1WelcomeLetterPopover {
    static func show() {}
    static func close() {}
}
class Day15FullUpgradeWindow: ProPromptWindow {
    static var shared: Day15FullUpgradeWindow?
    static func show(for reason: HardGateReason?) {}
}
class Day35FinalWindow: ProPromptWindow {
    static var shared: Day35FinalWindow?
    static func show() {}
}
enum Day4TourPopover { static func show() {} }

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
