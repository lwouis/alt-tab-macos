import Cocoa
/// Manages search state for the Settings window. Delegates fuzzy matching to the existing
/// `SettingsSearch` implementation (pure Swift, no AppKit dependency) and publishes which
/// tabs are visible plus the current query text.
@available(macOS 13.0, *)
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var visibleTabIds: Set<String> = []

    /// Per-tab searchable keywords, mirrored from the `searchableKeywords` property on each
    /// tab's type. Used as a lightweight pre-filter before the tab view is even loaded.
    private let tabKeywords: [String: [String]] = [
        "appearance": [
            "Size", "Theme", "After keys are released", "Preview selected window",
            "Multiple screens", "Show on", "Customize", "Animations", "Hide status icons",
            "Hide Space number", "colored circles",
        ],
        "controls": [
            "Hold", "Select next window", "Filtering", "Appearance", "Ordering & Grouping",
            "Show windows from", "minimized", "hidden", "fullscreen", "Group apps", "Group tabs",
            "Order windows by", "Gesture", "Shortcut", "Arrow keys", "Vim keys",
        ],
        "general": [
            "Start at login", "Menubar icon", "Language", "Updates policy", "Crash reports",
            "Capture windows in the background", "Check for updates", "Export settings",
            "Import settings", "Reset settings",
        ],
        "exceptions": [
            "Add a running app", "Add an app from disk", "Hide", "Ignore shortcuts",
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
}
