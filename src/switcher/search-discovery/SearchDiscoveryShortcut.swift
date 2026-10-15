import Cocoa
import ShortcutRecorder

enum SearchDiscoveryShortcut {
    static func combinedLabel(hold: Shortcut?, next: Shortcut?) -> String? {
        guard let next, next.keyCode != .none else { return nil }
        return label(Shortcut(code: next.keyCode,
            modifierFlags: next.modifierFlags.union(hold?.modifierFlags ?? []),
            characters: nil, charactersIgnoringModifiers: nil))
    }

    static func label(_ shortcut: Shortcut) -> String? {
        let modifiers: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = modifiers.filter { shortcut.modifierFlags.contains($0.0) }.map { $0.1 }.joined()
        guard shortcut.keyCode != .none else { return prefix.isEmpty ? nil : prefix }
        guard let key = LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: shortcut.carbonKeyCode)),
              !key.isEmpty else { return nil }
        return prefix + key.uppercased()
    }
}
