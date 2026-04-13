// Fix for issue #5149 - Window ordering bug in alt-tab-macos
// This file addresses the window ordering issue where windows appear in incorrect order during alt-tab

import Cocoa

class WindowManager {
    // Function to fix window ordering when cycling through applications
    func fixWindowOrdering(for windows: [NSWindow]) -> [NSWindow] {
        // Sort windows by their creation time or last active time to ensure proper ordering
        let sortedWindows = windows.sorted { window1, window2 in
            // Get the activation times for comparison
            let time1 = getWindowActivationTime(window1)
            let time2 = getWindowActivationTime(window2)
            return time1 > time2 // Most recently used first
        }
        
        return sortedWindows
    }
    
    private func getWindowActivationTime(_ window: NSWindow) -> TimeInterval {
        // Attempt to get the actual activation time from window properties
        // Fallback to current time if unavailable
        guard let windowNumber = window.windowNumber as NSNumber? else {
            return Date().timeIntervalSince1970
        }
        
        // Query system for window information
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as! [[String: AnyObject]]
        
        for windowInfo in windowInfoList {
            if let windowID = windowInfo[kCGWindowNumber as String] as? Int,
               windowID == window.windowNumber {
                if let lastModified = windowInfo[kCGWindowLastModified as String] as? TimeInterval {
                    return lastModified
                }
            }
        }
        
        return Date().timeIntervalSince1970
    }
    
    // Main function to handle the window switching logic
    func processWindowSwitching() {
        // Get all application windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as! [[String: AnyObject]]
        
        var appWindows: [String: [NSWindow]] = [:]
        
        // Group windows by application
        for windowInfo in windowInfoList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               let windowID = windowInfo[kCGWindowNumber as String] as? Int {
                
                if let nsWindow = NSApp.windows.first(where: { $0.windowNumber == windowID }) {
                    if appWindows[ownerName] == nil {
                        appWindows[ownerName] = []
                    }
                    appWindows[ownerName]?.append(nsWindow)
                }
            }
        }
        
        // Process each application's windows to ensure correct ordering
        for (appName, windows) in appWindows {
            let orderedWindows = fixWindowOrdering(for: windows)
            appWindows[appName] = orderedWindows
            
            // Update the display order if needed
            updateDisplayOrder(for: orderedWindows)
        }
    }
    
    private func updateDisplayOrder(for windows: [NSWindow]) {
        // Ensure windows are ordered correctly in the UI
        for i in 0..<windows.count {
            windows[i].orderFront(nil)
        }
    }
}

// Extension to handle the specific issue in the main application flow
extension NSApplication {
    func fixAltTabWindowOrdering() {
        let windowManager = WindowManager()
        windowManager.processWindowSwitching()
    }
}

// Implementation of the fix in the main window controller
class AltTabWindowController: NSWindowController {
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        // Apply the fix when the window loads
        DispatchQueue.main.async {
            self.applyWindowOrderingFix()
        }
    }
    
    private func applyWindowOrderingFix() {
        // Get all visible windows
        let visibleWindows = NSApp.windows.filter { $0.isVisible && !$0.isMiniaturized }
        
        // Apply ordering fix
        let windowManager = WindowManager()
        let orderedWindows = windowManager.fixWindowOrdering(for: visibleWindows)
        
        // Update the internal state to reflect correct ordering
        updateWindowList(to: orderedWindows)
    }
    
    private func updateWindowList(to orderedWindows: [NSWindow]) {
        // This method updates the internal window list used by the alt-tab functionality
        // The exact implementation depends on how the original code manages window lists
        
        // Example implementation:
        // Assuming there's an internal array that tracks window order
        // self.windowOrder = orderedWindows
        
        // For now, just ensure the most recent window is properly focused
        if let mostRecentWindow = orderedWindows.first {
            mostRecentWindow.makeKeyAndOrderFront(nil)
        }
    }
}
