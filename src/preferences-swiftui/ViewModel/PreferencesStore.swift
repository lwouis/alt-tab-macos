import Cocoa
import SwiftUI
import ShortcutRecorder
/// Bridges the existing `Preferences` / `CachedUserDefaults` / `PreferenceDefinition` data layer
/// into SwiftUI by exposing a `refreshToken` that toggles on every write, plus `Binding` factory
/// methods that read through the existing Pro-gating, caching, and migration stack.
@available(macOS 13.0, *)
final class PreferencesStore: ObservableObject {
    @Published var refreshToken = UUID()

    // MARK: - Bool bindings

    func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { CachedUserDefaults.bool(key) },
            set: { newValue in
                Preferences.set(key, String(newValue))
                self.refreshToken = UUID()
            }
        )
    }

    // MARK: - Int bindings

    func intBinding(for key: String) -> Binding<Int> {
        Binding(
            get: { CachedUserDefaults.int(key) },
            set: { newValue in
                Preferences.set(key, String(newValue))
                self.refreshToken = UUID()
            }
        )
    }

    // MARK: - Macro preference bindings (non-gated)

    func macroBinding<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        for key: String, _ allCases: [T]
    ) -> Binding<T> {
        Binding(
            get: { CachedUserDefaults.macroPref(key, allCases) },
            set: { newValue in
                Preferences.set(key, newValue.indexAsString)
                self.refreshToken = UUID()
            }
        )
    }

    // MARK: - Pro-gated macro preference bindings

    func proGatedBinding<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        _ definition: PreferenceDefinition<T>
    ) -> Binding<T> {
        Binding(
            get: { definition.read() },
            set: { newValue in
                Preferences.set(definition.key, newValue.indexAsString)
                self.refreshToken = UUID()
            }
        )
    }

    // MARK: - Shortcut bindings

    func shortcutBinding(for key: String) -> Binding<Shortcut?> {
        Binding(
            get: { CachedUserDefaults.shortcut(key) },
            set: { newValue in
                // Preserve string representation for storage
                let stringRep = newValue.flatMap { ShortcutManager.stringify($0) }
                Preferences.setShortcut(key, newValue, stringRepresentation: stringRep)
                self.refreshToken = UUID()
            }
        )
    }

    // MARK: - Shortcut count

    var shortcutCount: Int {
        Preferences.shortcutCount
    }

    var shortcutCountBinding: Binding<Int> {
        Binding(
            get: { Preferences.shortcutCount },
            set: { Preferences.set("shortcutCount", String($0)) }
        )
    }

    // MARK: - Override helpers

    func hasOverride(_ baseName: String, _ index: Int) -> Bool {
        Preferences.hasOverride(baseName, index)
    }

    func removeOverride(_ baseName: String, _ index: Int) {
        Preferences.removeOverride(baseName, index)
        refreshToken = UUID()
    }

    func overrideIndices(for baseName: String, globalKey: String) -> [Int] {
        Preferences.shortcutIndicesWithDifferentValue(baseName, globalKey: globalKey)
    }
}

// MARK: - Shortcut stringification helper

private enum ShortcutManager {
    /// Convert a Shortcut to its string representation matching `Preferences.shortcutStorage`.
    /// We reuse the existing storage format: ["string": "...", "secureData": ...].
    static func stringify(_ shortcut: Shortcut) -> String? {
        // The existing code uses Preferences.shortcutStorage for writing; we need the inverse.
        // For the initial implementation, we use keyEquivalent-based storage.
        guard shortcut.keyCode != .none || !shortcut.modifierFlags.isEmpty else { return nil }
        return shortcut.description
    }
}
