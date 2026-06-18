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
        ShortcutAction(id: "closeWindowShortcut", perform: { Windows.selectedWindow()?.close() }),
        ShortcutAction(id: "minDeminWindowShortcut", perform: { Windows.selectedWindow()?.minDemin() }),
        ShortcutAction(id: "toggleFullscreenWindowShortcut", perform: { Windows.selectedWindow()?.toggleFullscreen() }),
        ShortcutAction(id: "quitAppShortcut", perform: { Windows.selectedWindow()?.application.quit() }),
        ShortcutAction(id: "hideShowAppShortcut", perform: { Windows.selectedWindow()?.application.hideOrShow() }),
        ShortcutAction(id: "searchShortcut", perform: {
            guard SwitcherSession.isActive else { return }
            TilesView.toggleSearchModeFromShortcut()
        }),
    ]

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
