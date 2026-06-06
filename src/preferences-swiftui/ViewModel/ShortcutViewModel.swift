import Cocoa
import SwiftUI
/// Per-shortcut observable state for the Controls tab editor. Each row in the shortcut sidebar
/// maps to one `ShortcutViewModel` identified by its `index` (0 ..< shortcutCount).
/// The gesture row uses `Preferences.gestureIndex`.
@available(macOS 13.0, *)
final class ShortcutViewModel: ObservableObject, Identifiable {
    let index: Int
    let isGesture: Bool

    /// The key prefix used for `indexToName` lookups. For gestures, we use "nextWindowGesture"
    /// (which has no index suffix); for shortcuts we use the index-qualified base names.
    var triggerKeyBase: String {
        isGesture ? "nextWindowGesture" : ""
    }

    var holdShortcutKey: String {
        Preferences.indexToName("holdShortcut", index)
    }

    var nextWindowShortcutKey: String {
        Preferences.indexToName("nextWindowShortcut", index)
    }

    var gestureKey: String {
        "nextWindowGesture"
    }

    init(index: Int, isGesture: Bool = false) {
        self.index = index
        self.isGesture = isGesture || index >= Preferences.maxShortcutCount
    }

    /// Localised display title for the sidebar row.
    var title: String {
        if isGesture {
            return NSLocalizedString("Gesture", comment: "")
        }
        return String(format: NSLocalizedString("Shortcut %d", comment: ""), index + 1)
    }

    /// Summary text shown in the sidebar row (e.g. "⌥ + ⇥" or gesture name).
    var summary: String {
        if isGesture {
            return Preferences.nextWindowGesture.localizedString
        }
        let hold = CachedUserDefaults.shortcut(holdShortcutKey)
        let next = CachedUserDefaults.shortcut(nextWindowShortcutKey)
        if let h = hold?.description, let n = next?.description, !h.isEmpty, !n.isEmpty {
            return "\(h) + \(n)"
        }
        return hold?.description ?? next?.description ?? ""
    }

    // MARK: - Indexed key helpers

    func indexedKey(_ baseName: String) -> String {
        Preferences.indexToName(baseName, index)
    }

    func macroBinding<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        forBaseName baseName: String, _ allCases: [T]
    ) -> Binding<T> {
        let key = indexedKey(baseName)
        return Binding(
            get: { CachedUserDefaults.macroPref(key, allCases) },
            set: { newValue in
                Preferences.set(key, newValue.indexAsString)
            }
        )
    }

    func boolBinding(forBaseName baseName: String) -> Binding<Bool> {
        let key = indexedKey(baseName)
        return Binding(
            get: { CachedUserDefaults.bool(key) },
            set: { Preferences.set(key, String($0)) }
        )
    }

    func hasOverride(_ baseName: String) -> Bool {
        Preferences.hasOverride(baseName, index)
    }

    func removeOverride(_ baseName: String) {
        Preferences.removeOverride(baseName, index)
    }
}
