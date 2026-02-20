class CliEvents {
    static let portName = "com.lwouis.alt-tab-macos.cli"

    static func observe() {
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        if let messagePort = CFMessagePortCreateLocal(nil, portName as CFString, handleEvent, &context, nil),
           let source = CFMessagePortCreateRunLoopSource(nil, messagePort, 0) {
            CFRunLoopAddSource(BackgroundWork.cliEventsThread.runLoop, source, .commonModes)
        } else {
            Logger.error { "Can't listen on message port. Is another AltTab already running?" }
            // TODO: should we quit or restart here?
            // It's complex since AltTab can be restarted sometimes,
            // and the new instance may coexist with the old for some duration
            // There is also the case of multiple instances at login
        }
    }

    private static let handleEvent: CFMessagePortCallBack = { (_: CFMessagePort?, _: Int32, _ data: CFData?, _: UnsafeMutableRawPointer?) in
        Logger.debug { "" }
        if let data,
           let message = String(data: data as Data, encoding: .utf8) {
            Logger.info { message }
            let output = CliServer.executeCommandAndSendReponse(message)
            if let responseData = try? CliServer.jsonEncoder.encode(output) as CFData {
                return Unmanaged.passRetained(responseData)
            }
        }
        Logger.error { "Failed to decode message" }
        return nil
    }
}

class CliServer {
    static let jsonEncoder = JSONEncoder()
    static let error = "error"
    static let noOutput = "noOutput"

    static func executeCommandAndSendReponse(_ rawValue: String) -> Codable {
        var output: Codable = ""
        DispatchQueue.main.sync {
            output = executeCommandAndSendReponse_(rawValue)
        }
        return output
    }

    private static func executeCommandAndSendReponse_(_ rawValue: String) -> Codable {
        if rawValue == "--list" {
            return JsonWindowList(windows: Windows.list
                .filter { !$0.isWindowlessApp }
                .map { JsonWindow(id: $0.cgWindowId, title: $0.title) }
            )
        }
        if rawValue == "--detailed-list" {
            // refresh space/screen assignments so CLI returns fresh data
            Spaces.refresh()
            for window in Windows.list {
                window.updateSpacesAndScreen()
            }
            let windows = Windows.list
                .filter { !$0.isWindowlessApp }
                .map {
                    JsonWindowFull(
                        id: $0.cgWindowId,
                        title: $0.title,
                        appName: $0.application.localizedName,
                        appBundleId: $0.application.bundleIdentifier,
                        spaceIndexes: $0.spaceIndexes,
                        lastFocusOrder: $0.lastFocusOrder,
                        creationOrder: $0.creationOrder,
                        isTabbed: $0.isTabbed,
                        isHidden: $0.isHidden,
                        isFullscreen: $0.isFullscreen,
                        isMinimized: $0.isMinimized,
                        isOnAllSpaces: $0.isOnAllSpaces,
                        position: $0.position,
                        size: $0.size,
                        screenId: $0.screenId as String?,
                        appPid: $0.application.pid,
                        dockLabel: $0.application.dockLabel
                    )
                }

            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
            let screens = NSScreen.screens.compactMap { screen -> JsonScreen? in
                guard let uuid = screen.cachedUuid() else { return nil }
                let f = screen.frame
                let quartzY = primaryScreenHeight - f.origin.y - f.height
                let vf = screen.visibleFrame
                let quartzVisibleY = primaryScreenHeight - vf.origin.y - vf.height
                return JsonScreen(
                    id: uuid as String,
                    frame: [Double(f.origin.x), quartzY, Double(f.width), Double(f.height)],
                    visibleFrame: [Double(vf.origin.x), quartzVisibleY, Double(vf.width), Double(vf.height)]
                )
            }

            let visibleSpaceIndexes = Spaces.visibleSpaces.compactMap { spaceId in
                Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1
            }

            let screenSpacesMap = Dictionary(uniqueKeysWithValues: Spaces.screenSpacesMap.map { (key, value) in
                (key as String, value.compactMap { spaceId in
                    Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1
                })
            })

            let blacklistEntries = Preferences.blacklist
            let blacklist: [[String: String]]? = blacklistEntries.isEmpty ? nil : blacklistEntries.map { entry in
                var dict: [String: String] = [
                    "bundleIdentifier": entry.bundleIdentifier,
                    "hide": entry.hide.rawValue,
                    "ignore": entry.ignore.rawValue,
                ]
                if let title = entry.windowTitleContains {
                    dict["windowTitleContains"] = title
                }
                return dict
            }

            let mouseScreenId = NSScreen.withMouse()?.cachedUuid() as String?

            return JsonDetailedList(
                windows: windows,
                screens: screens,
                currentSpaceIndex: Spaces.currentSpaceIndex,
                visibleSpaceIndexes: visibleSpaceIndexes,
                screenSpacesMap: screenSpacesMap,
                frontmostAppPid: Applications.frontmostPid,
                mouseScreenId: mouseScreenId,
                blacklist: blacklist
            )
        }
        if rawValue.hasPrefix("--focus="),
           let id = CGWindowID(rawValue.dropFirst("--focus=".count)), let window = (Windows.list.first { $0.cgWindowId == id }) {
            window.focus()
            return noOutput
        }
        if rawValue.hasPrefix("--focusUsingLastFocusOrder="),
           let lastFocusOrder = Int(rawValue.dropFirst("--focusUsingLastFocusOrder=".count)), let window = (Windows.list.first { $0.lastFocusOrder == lastFocusOrder }) {
            window.focus()
            return noOutput
        }
        if rawValue.hasPrefix("--show="),
           let shortcutIndex = Int(rawValue.dropFirst("--show=".count)), (0..<Preferences.shortcutCount).contains(shortcutIndex) {
            App.app.showUi(shortcutIndex)
            return noOutput
        }
        return error
    }

    private struct JsonWindowList: Codable {
        var windows: [JsonWindow]
    }

    private struct JsonWindow: Codable {
        var id: CGWindowID?
        var title: String
    }

    private struct JsonDetailedList: Codable {
        var windows: [JsonWindowFull]
        var screens: [JsonScreen]
        var currentSpaceIndex: SpaceIndex
        var visibleSpaceIndexes: [SpaceIndex]
        var screenSpacesMap: [String: [SpaceIndex]]
        var frontmostAppPid: Int32?
        var mouseScreenId: String?
        var blacklist: [[String: String]]?
    }

    private struct JsonScreen: Codable {
        var id: String
        var frame: [Double]
        var visibleFrame: [Double]
    }

    private struct JsonWindowFull: Codable {
        var id: CGWindowID?
        var title: String
        // -- additional properties
        var appName: String?
        var appBundleId: String?
        var spaceIndexes: [SpaceIndex]
        var lastFocusOrder: Int
        var creationOrder: Int
        var isTabbed: Bool
        var isHidden: Bool
        var isFullscreen: Bool
        var isMinimized: Bool
        var isOnAllSpaces: Bool
        var position: CGPoint?
        var size: CGSize?
        var screenId: String?
        var appPid: Int32?
        var dockLabel: String?
    }
}

class CliClient {
    static func detectCommand() -> String? {
        let args = CommandLine.arguments
        if args.count == 2 && !args[1].starts(with: "--logs=") {
            if args[1] == "--list" || args[1] == "--detailed-list" || args[1].hasPrefix("--focus=") || args[1].hasPrefix("--focusUsingLastFocusOrder=") || args[1].hasPrefix("--show=") {
                return args[1]
            }
        }
        return nil
    }

    static func sendCommandAndProcessResponse(_ command: String) {
        do {
            let serverPortClient = try CFMessagePortCreateRemote(nil, CliEvents.portName as CFString).unwrapOrThrow()
            let data = try command.data(using: .utf8).unwrapOrThrow()
            var returnData: Unmanaged<CFData>?
            let _ = CFMessagePortSendRequest(serverPortClient, 0, data as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &returnData)
            let responseData = try returnData.unwrapOrThrow().takeRetainedValue()
            if let response = String(data: responseData as Data, encoding: .utf8) {
                if response != "\"\(CliServer.error)\"" {
                    if response != "\"\(CliServer.noOutput)\"" {
                        print(response)
                    }
                    exit(0)
                }
            }
            print("Couldn't execute command. Is it correct?")
            exit(1)
        } catch {
            print("AltTab.app needs to be running for CLI commands to work")
            exit(1)
        }
    }
}
