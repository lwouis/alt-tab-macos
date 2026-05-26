import Cocoa
import ShortcutRecorder

// Stubs so ProBadgeView.swift compiles in the test target. The real Symbols
// enum and NSImage.fromSymbol live in TileFontIconView.swift and
// HelperExtensions.swift respectively, neither of which is in the test
// target's source membership. Tests never actually render an icon, so a
// minimal stub satisfying the signatures is enough — isTemplate = true
// matches the production contract that ProBadgeViewSegmentTests asserts on.
enum Symbols: String {
    case stub = ""
}

extension NSImage {
    static func fromSymbol(_ symbol: Symbols, pointSize: CGFloat, rotated180: Bool = false) -> NSImage {
        let image = NSImage()
        image.isTemplate = true
        return image
    }
}

// `LightLabel` and `ProBadgeView` live in the test target's source membership (they're pulled
// in by `ProBadgeViewSegmentTests`) but reference `Appearance` and `SettingsSearchIndex` —
// types not in the test target. Minimal stubs so the test target compiles. Tests never exercise
// these code paths; the stubs just satisfy the type checker.
enum SettingsSearchIndex {
    static func registerString(_ s: String?) {}
}

class Appearance {
    static var searchMatchHighlightColor: NSColor = .yellow
}

enum SearchKeyResult {
    case handled
    case passToField
    case passToShortcuts
}

class TilesViewMock {
    var isSearchEditing = false
    func handleSearchEditingKeyDown(_ event: NSEvent) -> SearchKeyResult { return .passToField }
}

class TilesPanelMock {
    var tilesView = TilesViewMock()
    var isKeyWindow = false
}

class App {
    class AppMock {
        var tilesPanel = TilesPanelMock()
    }
    static let app = AppMock()
    static let bundleIdentifier = "com.lwouis.alt-tab-macos"
}

class TilesPanel {
    static let shared = TilesPanel()
    var isKeyWindow: Bool {
        get { App.app.tilesPanel.isKeyWindow }
        set { App.app.tilesPanel.isKeyWindow = newValue }
    }
}

class TilesView {
    static var isSearchEditing: Bool {
        get { App.app.tilesPanel.tilesView.isSearchEditing }
        set { App.app.tilesPanel.tilesView.isSearchEditing = newValue }
    }

    static func handleSearchEditingKeyDown(_ event: NSEvent) -> SearchKeyResult {
        return App.app.tilesPanel.tilesView.handleSearchEditingKeyDown(event)
    }
}

class ControlsTab {
    static let defaultShortcuts = [
        "holdShortcut": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut", .global, .up, 0),
        "holdShortcut2": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut2", .global, .up, 1),
        "holdShortcut3": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut3", .global, .up, 2),
        "nextWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "⇥")!, "nextWindowShortcut", .global, .down),
        "nextWindowShortcut2": ATShortcut(Shortcut(keyEquivalent: "`")!, "nextWindowShortcut2", .global, .down),
        "→": ATShortcut(Shortcut(keyEquivalent: "→")!, "→", .local, .down),
        "←": ATShortcut(Shortcut(keyEquivalent: "←")!, "←", .local, .down),
        "↑": ATShortcut(Shortcut(keyEquivalent: "↑")!, "↑", .local, .down),
        "↓": ATShortcut(Shortcut(keyEquivalent: "↓")!, "↓", .local, .down),
//        "vimCycleRight": ATShortcut(Shortcut(keyEquivalent: "l")!, "vimCycleRight", .local, .down),
//        "vimCycleLeft": ATShortcut(Shortcut(keyEquivalent: "h")!, "vimCycleLeft", .local, .down),
//        "vimCycleUp": ATShortcut(Shortcut(keyEquivalent: "k")!, "vimCycleUp", .local, .down),
//        "vimCycleDown": ATShortcut(Shortcut(keyEquivalent: "j")!, "vimCycleDown", .local, .down),
        "focusWindowShortcut": ATShortcut(Shortcut(keyEquivalent: " ")!, "focusWindowShortcut", .local, .down),
        "previousWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "⇧")!, "previousWindowShortcut", .local, .down),
        "cancelShortcut": ATShortcut(Shortcut(keyEquivalent: "⎋")!, "cancelShortcut", .local, .down),
        "searchShortcut": ATShortcut(Shortcut(keyEquivalent: "s")!, "searchShortcut", .local, .down),
        "closeWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "w")!, "closeWindowShortcut", .local, .down),
        "minDeminWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "m")!, "minDeminWindowShortcut", .local, .down),
        "toggleFullscreenWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "f")!, "toggleFullscreenWindowShortcut", .local, .down),
        "quitAppShortcut": ATShortcut(Shortcut(keyEquivalent: "q")!, "quitAppShortcut", .local, .down),
        "hideShowAppShortcut": ATShortcut(Shortcut(keyEquivalent: "h")!, "hideShowAppShortcut", .local, .down),
    ]
    static var shortcuts = defaultShortcuts

    static func executeAction(_ action: String) {
        shortcutsActionsTriggered.append(action)
        if action.starts(with: "holdShortcut") {
            SwitcherSession.current = nil
        }
        if action.starts(with: "nextWindowShortcut") {
            let session = SwitcherSession.current ?? {
                let new = SwitcherSession()
                SwitcherSession.current = new
                return new
            }()
            session.shortcutIndex = Preferences.nameToIndex(action)
        }
    }

    static var shortcutsActionsTriggered: [String] = []
}

enum ShortcutActions {
    static func execute(_ id: String) {
        ControlsTab.executeAction(id)
    }
}

class KeyRepeatTimer {
    static func stopTimerForRepeatingKey(_ shortcutName: String) {
    }
}

class Logger {
    static func debug(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
    static func info(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
    static func warning(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
    static func error(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
}

class Preferences {
    static var shortcutStyle: ShortcutStylePreference = .focusOnRelease
    static var holdShortcut = ["⌥", "⌥", "⌥"]
    static let minShortcutCount = 1
    static let maxShortcutCount = 9

    static func indexToName(_ baseName: String, _ index: Int) -> String {
        return baseName + (index == 0 ? "" : String(index + 1))
    }

    static func nameToIndex(_ name: String) -> Int {
        guard let number = name.last?.wholeNumberValue else { return 0 }
        return number - 1
    }

    static func effectiveShortcutStyle(_ index: Int) -> ShortcutStylePreference {
        return shortcutStyle
    }
}

enum ShortcutStylePreference: CaseIterable {
    case focusOnRelease
    case doNothingOnRelease
    case searchOnRelease
}

class ModifierFlags {
    static var current: NSEvent.ModifierFlags = []
}
