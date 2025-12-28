import AppKit
import ScriptingBridge

@objc public protocol DiaBrowserApplication {
    @objc optional func windows() -> SBElementArray
    @objc optional var name: String { get }
    @objc optional var frontmost: Bool { get }
    @objc optional var version: String { get }
    @objc optional var isRunning: Bool { get }
    @objc optional func activate()
}

@objc public protocol DiaBrowserWindow {
    @objc optional func tabs() -> SBElementArray
    @objc optional func id() -> String
    @objc optional var name: String { get }
    @objc optional var index: Int { get }
    @objc optional var bounds: NSRect { get }
    @objc optional var minimized: Bool { get }
    @objc optional var visible: Bool { get }
}

@objc public protocol DiaBrowserTab {
    @objc optional func id() -> String
    @objc optional var title: String { get }
    @objc optional var URL: String { get }
    @objc optional var isFocused: Bool { get }
    @objc optional var isPinned: Bool { get }
    @objc optional func focus()
}

extension SBApplication: DiaBrowserApplication {}
extension SBObject: DiaBrowserWindow, DiaBrowserTab {}

class DiaBrowserAdapter: BrowserAdapter {
    static let supportedBundleIds: [String] = [
        "company.thebrowser.dia",
    ]
    
    static func fetchAllTabs(bundleIdentifier: String) -> [BrowserTabInfo] {
        guard let browser: DiaBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return []
        }
        guard browser.isRunning == true else {
            return []
        }
        var allTabs: [BrowserTabInfo] = []
        guard let windows = browser.windows?() else {
            return []
        }
        for (windowIndex, windowObj) in windows.enumerated() {
            guard let window = windowObj as? DiaBrowserWindow else { continue }
            guard let tabs = window.tabs?() else { continue }
            for (tabIndex, tabObj) in tabs.enumerated() {
                guard let tab = tabObj as? DiaBrowserTab else { continue }
                let tabId = tab.id?() ?? ""
                let isActive = tab.isFocused ?? false
                let tabInfo = BrowserTabInfo(
                    tabId: String(tabId),
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: String(tab.title ?? ""),
                    url: String(tab.URL ?? ""),
                    isActive: isActive,
                    isIncognito: false,
                    bundleIdentifier: bundleIdentifier
                )
                allTabs.append(tabInfo)
            }
        }
        return allTabs
    }
    
    static func activateTab(bundleIdentifier: String, tabId: String) -> Bool {
        guard let browser: DiaBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return false
        }
        guard browser.isRunning == true else {
            return false
        }
        guard let windows = browser.windows?() else {
            return false
        }
        
        for windowObj in windows {
            guard let window = windowObj as? DiaBrowserWindow,
                  let tabs = window.tabs?() else { continue }
            
            for tabObj in tabs {
                guard let tab = tabObj as? DiaBrowserTab,
                      tab.id?() == tabId else { continue }
                
                tab.focus?()
                browser.activate?()
                return true
            }
        }
        return false
    }
    
    static func getActiveTabId(bundleIdentifier: String) -> String? {
        guard let browser: DiaBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        guard browser.isRunning == true else {
            return nil
        }
        guard let windows = browser.windows?() else {
            return nil
        }
        
        for windowObj in windows {
            guard let window = windowObj as? DiaBrowserWindow,
                  let tabs = window.tabs?() else { continue }
            
            for tabObj in tabs {
                guard let tab = tabObj as? DiaBrowserTab,
                      tab.isFocused == true else { continue }
                return tab.id?()
            }
        }
        return nil
    }
}
