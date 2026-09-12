import Cocoa

struct ShortcutAction {
    let id: String
    let perform: () -> Void
}

enum ShortcutActions {
    static let all: [ShortcutAction] = [
        ShortcutAction(id: "focusWindowShortcut", perform: { App.focusTarget() }),
        ShortcutAction(id: "previousWindowShortcut", perform: { App.previousWindowShortcutWithRepeatingKey() }),
        ShortcutAction(id: "→", perform: { App.cycleSelection(.right) }),
        ShortcutAction(id: "←", perform: { App.cycleSelection(.left) }),
        ShortcutAction(id: "↑", perform: { App.cycleSelection(.up) }),
        ShortcutAction(id: "↓", perform: { App.cycleSelection(.down) }),
        ShortcutAction(id: "vimCycleRight", perform: { App.cycleSelection(.right) }),
        ShortcutAction(id: "vimCycleLeft", perform: { App.cycleSelection(.left) }),
        ShortcutAction(id: "vimCycleUp", perform: { App.cycleSelection(.up) }),
        ShortcutAction(id: "vimCycleDown", perform: { App.cycleSelection(.down) }),
        ShortcutAction(id: "cancelShortcut", perform: {
            guard let session = SwitcherSession.current else { return }
            let entry: SearchEntryStyle = Preferences.effectiveShortcutStyle(session.shortcutIndex) == .searchOnRelease ? .startedInSearch : .toggledMidSession
            switch SearchModeResolver.escape(mode: TilesView.searchMode, entry: entry) {
                case .exitSearch: TilesView.disableSearchMode()
                case .closeSwitcher: App.hideUi()
            }
        }),
        ShortcutAction(id: "closeWindowShortcut", perform: { onSelectedWindow { $0.close() } }),
        ShortcutAction(id: "minDeminWindowShortcut", perform: { onSelectedWindow { $0.minDemin() } }),
        ShortcutAction(id: "toggleFullscreenWindowShortcut", perform: { onSelectedWindow { $0.toggleFullscreen() } }),
        ShortcutAction(id: "quitAppShortcut", perform: { onSelectedWindow { $0.application.quit() } }),
        ShortcutAction(id: "hideShowAppShortcut", perform: { onSelectedWindow { $0.application.hideOrShow() } }),
        ShortcutAction(id: "searchShortcut", perform: {
            guard SwitcherSession.isActive else { return }
            TilesView.toggleSearchModeFromShortcut()
        }),
    ]

    /// Acting on a tile is a commitment to THAT window, so from here the selection follows it by id rather
    /// than being re-derived as the default pick. Every one of these actions reorders the list under the
    /// open switcher — fullscreen moves the window to its own Space, minimize/hide/quit move the MRU — and
    /// the default pick means "the second visible window", so it stayed on the SLOT while the window the
    /// user aimed at slid out of it. Live: F fullscreened the selected window, the list reordered, and a
    /// second F to undo fullscreened a different app's window instead (measured live).
    private static func onSelectedWindow(_ act: (Window) -> Void) {
        guard let window = Windows.selectedWindow() else { return }
        SwitcherSession.current?.userPickedSelection = true
        act(window)
    }

    private static let byId: [String: ShortcutAction] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func find(_ id: String) -> ShortcutAction? {
        byId[id]
    }

    static func execute(_ id: String) {
        // Gate *pressing* a Pro-only shortcut slot (index >= 1). Without this, configured Cmd+Tab
        // variants past the first keep working after Day15 lock. Mirrors the `.search` gate in
        // `TilesView` and the slot-add gate in `addShortcutSlot()`.
        if id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut") {
            let index = Preferences.nameToIndex(id)
            if index >= 1 {
                if !ProFeature.extraShortcut(index: index).attemptUse() { return }
            }
        }
        if let action = find(id) {
            action.perform()
            return
        }
        if id.hasPrefix("holdShortcut") {
            App.focusTarget()
            return
        }
        if id.hasPrefix("nextWindowShortcut") {
            App.showUiOrCycleSelection(Preferences.nameToIndex(id), false)
        }
    }
}
