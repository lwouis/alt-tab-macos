import Cocoa

let filename = "alt-tab-windows.json"

class Persist {
    private static func writeWindowsToFile(_ windows: [Window]) {
        var isDirectory: ObjCBool = false
        let persistDirectory = Preferences.persistDirectory
        FileManager.default.fileExists(atPath: persistDirectory.absoluteString, isDirectory: &isDirectory)
        if !isDirectory.boolValue {
            return
        }
        let windowData = windows.map({["name": $0.title ?? "(Unknown)", "isFullscreen": $0.isFullscreen, "isMinimized": $0.isMinimized, "spaceIndex": $0.spaceIndex, "lastFocusOrder": $0.lastFocusOrder, "application": $0.application.runningApplication.localizedName ?? "(Unknown)", "applicationBundleUrl": $0.application.runningApplication.bundleURL?.absoluteString ?? "file:///", "windowId": $0.cgWindowId, "isHidden": $0.isHidden, "isWindowlessApp": $0.isWindowlessApp]})
        let payload = ["windows": windowData, "version": 1] as [String : Any]
    
        let fileURL = persistDirectory.appendingPathComponent(filename)

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            try jsonData.write(to: fileURL)
        } catch {
            print(error.localizedDescription)
        }
    }
    static func writeWindowsToFileWithPermission(_ windows: [Window]) {
        if Preferences.persistToDisk {
            DispatchQueue.main.async {
                writeWindowsToFile(windows)
            }
        }
    }
}

