import Cocoa
import Foundation

extension AXUIElement {
    func cgWindowId() -> CGWindowID {
        var id = CGWindowID(0)
        _AXUIElementGetWindow(self, &id)
        return id
    }

    func pid() -> pid_t {
        var pid = pid_t(0)
        AXUIElementGetPid(self, &pid)
        return pid
    }

    func isActualWindow(_ isAppHidden: Bool = false) -> Bool {
        // TODO: should we displays windows that disappear when invoking Expose? (e.g. Outlook meeting reminder window) (see https://stackoverflow.com/a/49723037/2249756)
        // TODO: TotalFinder and XtraFinder double-window hacks (see #84)
        // TODO: should we display menubar windows? (e.g. iStats Pro dropdown menu)
        // Some non-windows have subrole: nil (e.g. some OS elements), "AXUnknown" (e.g. Bartender), "AXSystemDialog" (e.g. Intellij tooltips)
        // Some non-windows have title: nil (e.g. some OS elements)
        // Minimized windows or windows of a hidden app have subrole "AXDialog"
        return title() != nil && (subrole() == "AXStandardWindow" || isMinimized() || isAppHidden)
    }

    func title() -> String? {
        return attribute(kAXTitleAttribute, String.self)
    }

    func windows() -> [AXUIElement]? {
        return attribute(kAXWindowsAttribute, [AXUIElement].self)
    }

    func isMinimized() -> Bool {
        return attribute(kAXMinimizedAttribute, Bool.self) == true
    }

    func isHidden() -> Bool {
        return attribute(kAXHiddenAttribute, Bool.self) == true
    }

    func focusedWindow() -> AXUIElement? {
        return attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }

    func subrole() -> String? {
        return attribute(kAXSubroleAttribute, String.self)
    }

    private func attribute<T>(_ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, key as CFString, &value)
        if result == .success, let value = value as? T {
            return value
        }
        return nil
    }

    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) -> T? {
        if let a = attribute(key, AXValue.self) {
            var value = target
            AXValueGetValue(a, type, &value)
            return value
        }
        return nil
    }
}
