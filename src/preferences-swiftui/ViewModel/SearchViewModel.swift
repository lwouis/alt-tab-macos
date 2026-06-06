import Cocoa
/// Manages search state for the Settings window. Delegates fuzzy matching to the existing
/// `SettingsSearch` implementation (pure Swift, no AppKit dependency) and publishes which
/// tabs are visible plus the current query text.
@available(macOS 13.0, *)
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var visibleTabIds: Set<String> = []
    @Published var firstMatchSectionId: String?

    private var visibleSectionIds: Set<String> = []
    private var allSectionIds: [String] = []

    /// Per-tab searchable keywords. Keep in sync with the actual `NSLocalizedString` labels
    /// rendered in each tab's view (AppearanceTabView, ControlsTabView, etc.).
    /// Each tab also exposes a `static var searchableKeywords: [String]` for reference.
    private let tabKeywords: [String: [String]] = [
        "appearance": [
            NSLocalizedString("Size", comment: ""), NSLocalizedString("Theme", comment: ""),
            NSLocalizedString("After keys are released", comment: ""), NSLocalizedString("Preview selected window", comment: ""),
            NSLocalizedString("Multiple screens", comment: ""), NSLocalizedString("Show on", comment: ""),
            NSLocalizedString("Animations", comment: ""), NSLocalizedString("Hide status icons", comment: ""),
            NSLocalizedString("Hide Space number labels", comment: ""), NSLocalizedString("Hide colored circles on mouse hover", comment: ""),
            NSLocalizedString("Show titles", comment: ""), NSLocalizedString("Title truncation", comment: ""),
            NSLocalizedString("Apparition delay of Switcher", comment: ""), NSLocalizedString("Fade out animation of Switcher", comment: ""),
            NSLocalizedString("Fade in animation of Preview", comment: ""), NSLocalizedString("Window Style", comment: ""),
            NSLocalizedString("Appearance", comment: ""),
        ],
        "controls": [
            NSLocalizedString("Hold", comment: ""), NSLocalizedString("Select next window", comment: ""),
            NSLocalizedString("Filtering", comment: ""), NSLocalizedString("Appearance", comment: ""),
            NSLocalizedString("Ordering & Grouping", comment: ""), NSLocalizedString("Show windows from applications", comment: ""),
            NSLocalizedString("Show windows from Spaces", comment: ""), NSLocalizedString("Show windows from screens", comment: ""),
            NSLocalizedString("Show minimized windows", comment: ""), NSLocalizedString("Show hidden windows", comment: ""),
            NSLocalizedString("Show fullscreen windows", comment: ""), NSLocalizedString("Show apps with no open window", comment: ""),
            NSLocalizedString("Group apps", comment: ""), NSLocalizedString("Group tabs", comment: ""),
            NSLocalizedString("Order windows by", comment: ""), NSLocalizedString("Gesture", comment: ""),
            NSLocalizedString("Shortcut", comment: ""), NSLocalizedString("Trigger", comment: ""),
            NSLocalizedString("Additional controls", comment: ""), NSLocalizedString("Shortcuts when active", comment: ""),
            NSLocalizedString("Cursor follows focus", comment: ""), NSLocalizedString("Trackpad haptic feedback", comment: ""),
            NSLocalizedString("Select windows using arrow keys", comment: ""), NSLocalizedString("Select windows using vim keys", comment: ""),
            NSLocalizedString("Select windows on mouse hover", comment: ""), NSLocalizedString("Remove override", comment: ""),
            NSLocalizedString("and press", comment: ""), NSLocalizedString("Size", comment: ""),
            NSLocalizedString("Theme", comment: ""), NSLocalizedString("After keys are released", comment: ""),
            NSLocalizedString("Preview selected window", comment: ""),
        ],
        "general": [
            NSLocalizedString("Start at login", comment: ""), NSLocalizedString("Menubar icon", comment: ""),
            NSLocalizedString("Language", comment: ""), NSLocalizedString("Updates policy", comment: ""),
            NSLocalizedString("Crash reports policy", comment: ""), NSLocalizedString("Capture windows in the background", comment: ""),
            NSLocalizedString("Check for updates", comment: ""), NSLocalizedString("Export settings", comment: ""),
            NSLocalizedString("Import settings", comment: ""), NSLocalizedString("Reset settings", comment: ""),
            NSLocalizedString("General", comment: ""), NSLocalizedString("Updates", comment: ""),
        ],
        "exceptions": [
            NSLocalizedString("Add a running app", comment: ""), NSLocalizedString("Add an app from disk", comment: ""),
            NSLocalizedString("Hide", comment: ""), NSLocalizedString("Ignore shortcuts", comment: ""),
            NSLocalizedString("Remove selected", comment: ""), NSLocalizedString("Add a pattern", comment: ""),
            NSLocalizedString("Bundle ID", comment: ""), NSLocalizedString("Behavior", comment: ""),
        ],
    ]

    private var allTabIds: [String] { ["appearance", "controls", "general", "exceptions"] }

    func applySearch() {
        let newVisible: Set<String>
        if SettingsSearch.isQueryEmpty(query) {
            newVisible = Set(allTabIds)
        } else {
            let matching = allTabIds.filter { tabId in
                guard let keywords = tabKeywords[tabId] else { return false }
                return keywords.contains { SettingsSearch.match(query, in: $0) != nil }
            }
            newVisible = Set(matching)
        }
        if visibleTabIds != newVisible {
            visibleTabIds = newVisible
        }
    }

    /// Whether a tab should be visible in the sidebar given the current query.
    func isTabVisible(_ id: String) -> Bool {
        if SettingsSearch.isQueryEmpty(query) { return true }
        return visibleTabIds.contains(id)
    }

    /// Whether the given text matches the current query.
    func textMatches(_ text: String) -> Bool {
        guard !SettingsSearch.isQueryEmpty(query) else { return false }
        return SettingsSearch.match(query, in: text) != nil
    }

    // MARK: - Section-level visibility (called by SearchableSection)

    func registerSection(_ id: String) {
        if !allSectionIds.contains(id) {
            allSectionIds.append(id)
        }
    }

    func updateSectionVisibility(_ id: String, isVisible: Bool) {
        if isVisible {
            visibleSectionIds.insert(id)
        } else {
            visibleSectionIds.remove(id)
        }
        recalcFirstMatch()
    }

    func clearSectionTracking() {
        visibleSectionIds.removeAll()
        allSectionIds.removeAll()
        firstMatchSectionId = nil
    }

    private func recalcFirstMatch() {
        guard !SettingsSearch.isQueryEmpty(query) else {
            firstMatchSectionId = nil
            return
        }
        firstMatchSectionId = allSectionIds.first { visibleSectionIds.contains($0) }
    }
}
