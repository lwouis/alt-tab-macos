class CliEvents {
    static let portName = "\(App.bundleIdentifier).cli"

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

    /// Returning nil is not an error the caller can see: a NULL from a message-port callback arrives as a
    /// zero-byte reply, so the CLI prints an empty line and exits 0, exactly like a healthy call. Every
    /// way out therefore says in the log what it could not do.
    private static let handleEvent: CFMessagePortCallBack = { (_: CFMessagePort?, _: Int32, _ data: CFData?, _: UnsafeMutableRawPointer?) in
        Logger.debug { "" }
        guard let data, let message = String(data: data as Data, encoding: .utf8) else {
            Logger.error { "Failed to decode message" }
            return nil
        }
        Logger.info { message }
        let output = CliServer.executeCommandAndSendReponse(message)
        do {
            let reply = try CliServer.jsonEncoder.encode(output)
            Logger.debug { "replying \(reply.count) bytes to \(message): \(String(data: reply.prefix(60), encoding: .utf8) ?? "?")" }
            return Unmanaged.passRetained(reply as CFData)
        } catch {
            Logger.error { "Failed to encode the response to \(message): \(error)" }
            return nil
        }
    }
}

class CliServer {
    /// `JSONEncoder` refuses a NaN or an infinite `Double` by default. Window geometry comes from AX and
    /// can be either, and one such window would otherwise make every response fail to encode for as long
    /// as it exists — silently, since the client cannot tell a failed reply from an empty one.
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }()
    static let error = "error"
    static let noOutput = "noOutput"

    // main.sync is safe here: the main thread never synchronously waits on the CLI thread
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
            return JsonWindowFullList(windows: Windows.list
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
                        size: $0.size
                    )
                }
            )
        }
        if rawValue == "--qa-state" {
            return qaState()
        }
        // The provider timeline, drained rather than read: each record is reported exactly once, so a QA test
        // gets the events of its own session and not the whole run's backlog. The harness writes them out as
        // NDJSON (`TrackingTelemetryNdjson`).
        if rawValue == "--qa-telemetry" {
            return QaTelemetryDrain(v: TrackingTelemetryState.schemaVersion,
                records: TrackingTelemetryRecorder.drain())
        }
        // **Fault injection: make an app look like one that never announces its window closes.** Takes a
        // comma-separated pid list and REPLACES the muted set; an empty value clears it. Its
        // `elementDestroyed` deliveries are then dropped on arrival, so the app never proves it delivers and
        // every close of its windows falls back to the WindowServer's order-out probe. The fallback has no
        // other way to be exercised — see `AxObserverRegistry.mutedDestroyPids` for why no real app can be
        // asked to behave this way on demand.
        if rawValue.hasPrefix("--qa-mute-ax-destroys=") {
            let raw = rawValue.dropFirst("--qa-mute-ax-destroys=".count)
            let pids = Set(raw.split(separator: ",").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) })
            AxObserverRegistry.muteDestroys(pids: pids)
            Logger.info { "QA: muting ax destroys for \(pids.isEmpty ? "no pids" : "\(pids.sorted())")" }
            return noOutput
        }
        if rawValue.hasPrefix("--qa-mark=") {
            let mark = String(rawValue.dropFirst("--qa-mark=".count))
            Logger.info { "QAMARK \(mark)" }
            return noOutput
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
            App.showUi(shortcutIndex)
            return noOutput
        }
        // The counterpart to `--show=`, for the QA harness. `--show=` opens the switcher WITHOUT making
        // AltTab the active app (no modifier is held, nothing activates us), and in that state Esc can
        // only arrive through the global cghid tap — the local monitor never sees it, because local
        // monitors only get events aimed at their own app. So a synthetic Esc is not a reliable way for
        // the harness to close what `--show=` opened, and when it failed the whole suite cascaded: the
        // switcher stayed up, later tests died in their setup, and it was written up as a product bug
        // before the maintainer showed a real keyboard never reproduces it. Dismissal the harness drives
        // itself, so a test that is not ABOUT Esc cannot be derailed by it.
        if rawValue == "--hide" {
            App.hideUi()
            return noOutput
        }
        return error
    }

    /// Read-only snapshot of everything the switcher would decide, without showing the UI. Exists for the
    /// automated QA harness: a live assertion oracle that costs one IPC round-trip instead of
    /// parsing debug logs or screenshotting tiles. Mutates nothing — `shown` is computed into a local, not
    /// written to `Window.shouldShowTheUser`, and the list is not sorted.
    private static func qaState() -> Codable {
        let filters = WindowFilters.snapshot()
        let frontmostPid = Applications.frontmostPid
        let visibleSpaceIds = Spaces.visibleSpaces
        let cursor = filters.appsToShow == .underCursor ? NSScreen.mouseLocationInQuartzCoordinates() : nil
        let windows = Windows.list.enumerated().map { (i, w) -> QaWindow in
            let wid = w.cgWindowId
            let shown = WindowFilterResolver.shouldShow(
                w.state, w.application.state,
                onlyFrontmostApp: filters.appsToShow == .active,
                excludeFrontmostApp: filters.appsToShow == .nonActive,
                onlyUnderCursor: filters.appsToShow == .underCursor,
                hideHidden: filters.showHiddenWindows == .hide,
                hideWindowless: filters.showWindowlessApps == .hide,
                hideFullscreen: filters.showFullscreenWindows == .hide,
                hideMinimized: filters.showMinimizedWindows == .hide,
                onlyVisibleSpaces: filters.spacesToShow == .visible,
                onlyNonVisibleSpaces: filters.spacesToShow == .nonVisible,
                onlyPreferredScreen: filters.screensToShow == .showingAltTab,
                separateTabs: filters.groupTabs == .separateWindows,
                frontmostPid: frontmostPid,
                visibleSpaceIds: visibleSpaceIds,
                exceptions: filters.exceptions,
                isOnPreferredScreen: w.isOnScreen(NSScreen.preferred),
                isUnderCursor: cursor.map { w.contains($0) } ?? false)
            return QaWindow(
                index: i,
                wid: wid,
                title: w.title,
                app: w.application.runningApplication.localizedName,
                bundleId: w.application.bundleIdentifier,
                pid: w.application.pid,
                shown: shown,
                tabbed: w.isTabbed,
                groupId: wid.flatMap { TabGroups.groupId(of: $0) },
                siblings: w.tabbedSiblingWids,
                isGroupRepresentative: wid.flatMap { w2 in TabGroups.groupId(of: w2).map { TabGroups.representativeByGroup[$0] == w2 } } ?? false,
                tabCount: w.tabCount,
                phantom: w.isPhantom,
                phantomLatch: w.cgsPhantomLatch,
                held: wid.map { Windows.windowsHeldVisibleForTab.contains($0) } ?? false,
                fullscreen: w.isFullscreen,
                fullscreenMirrored: w.isFullscreenMirrored,
                minimized: w.isMinimized,
                appHidden: w.isHidden,
                windowless: w.isWindowlessApp,
                focused: w.application.pid == frontmostPid && w.application.focusedWindow === w,
                isMainWindow: w.state.isMainWindow,
                spaceIds: w.spaceIds,
                spaceIndexes: w.spaceIndexes,
                spaceIsBorrowed: w.spaceIsBorrowed,
                lastFocusOrder: w.lastFocusOrder,
                creationOrder: w.creationOrder,
                focusedAt: w.focusedAt,
                position: w.position,
                size: w.size,
                axHash: w.axUiElement.map { Int(CFHash($0) % 100000) })
        }
        let groups = TabGroups.membersByGroup.map {
            QaGroup(groupId: $0.key, members: $0.value, representative: TabGroups.representativeByGroup[$0.key])
        }.sorted { $0.groupId < $1.groupId }
        return QaState(
            at: Date().timeIntervalSince1970,
            frontmostPid: frontmostPid,
            frontmostApp: NSWorkspace.shared.frontmostApplication?.localizedName,
            currentSpaceId: Spaces.currentSpaceId,
            currentSpaceIndex: Spaces.currentSpaceIndex,
            visibleSpaceIds: visibleSpaceIds,
            allSpaces: Spaces.idsAndIndexes.map { QaSpace(id: $0.0, index: $0.1) },
            switcherVisible: SwitcherSession.isActive,
            selectedIndex: SwitcherSession.current?.selectedIndex,
            heldWids: Array(Windows.windowsHeldVisibleForTab),
            recentlyCreatedWids: Array(Windows.recentlyCreatedWindows),
            apps: Applications.list.map {
                QaApp(pid: $0.pid, name: $0.runningApplication.localizedName, bundleId: $0.bundleIdentifier, hidden: $0.isHidden)
            },
            groups: groups,
            windows: windows,
            tiles: renderedTiles(),
            tracking: TrackingTelemetryRecorder.state.summary())
    }

    /// What the tiles on screen are CURRENTLY showing, as opposed to what the model says they should show.
    /// The two are the same only if every model flip that happens while the panel is open also asks for a
    /// repaint — and one that didn't is a bug the user sees and no model-side oracle can: un-minimizing a
    /// window from the open switcher left the minimized indicator on its tile until the panel was closed
    /// and reopened. Read straight off the laid-out `TileView`s, so it reports the last frame drawn.
    private static func renderedTiles() -> [QaTile] {
        guard SwitcherSession.isActive else { return [] }
        return TilesView.recycledViews.enumerated().compactMap { (i, view) -> QaTile? in
            guard view.frame != .zero, let window = view.window_ else { return nil }
            let icons = view.statusIcons.icons
            return QaTile(index: i, wid: window.cgWindowId, title: window.title,
                app: window.application.runningApplication.localizedName,
                minimizedIcon: icons[StatusIconsView.minimizedIdx].visible,
                fullscreenIcon: icons[StatusIconsView.fullscreenIdx].visible,
                appHiddenIcon: icons[StatusIconsView.hiddenIdx].visible,
                spaceIcon: icons[StatusIconsView.spaceIdx].visible)
        }
    }

    private struct QaState: Codable {
        var at: TimeInterval
        var frontmostPid: pid_t?
        var frontmostApp: String?
        var currentSpaceId: UInt64
        var currentSpaceIndex: Int
        var visibleSpaceIds: [UInt64]
        var allSpaces: [QaSpace]
        var switcherVisible: Bool
        var selectedIndex: Int?
        var heldWids: [CGWindowID]
        var recentlyCreatedWids: [CGWindowID]
        var apps: [QaApp]
        var groups: [QaGroup]
        var windows: [QaWindow]
        /// empty while the switcher is closed — there is nothing drawn to report
        var tiles: [QaTile]
        /// provider health and the last committed attention decision (`TrackingTelemetryState`)
        var tracking: TrackingTelemetrySummary
    }

    private struct QaTelemetryDrain: Codable {
        var v: Int
        var records: [TelemetryRecord]
    }

    private struct QaTile: Codable {
        var index: Int
        var wid: CGWindowID?
        var title: String
        var app: String?
        var minimizedIcon: Bool
        var fullscreenIcon: Bool
        var appHiddenIcon: Bool
        var spaceIcon: Bool
    }

    private struct QaSpace: Codable {
        var id: UInt64
        var index: Int
    }

    private struct QaApp: Codable {
        var pid: pid_t
        var name: String?
        var bundleId: String?
        var hidden: Bool
    }

    private struct QaGroup: Codable {
        var groupId: Int
        var members: [CGWindowID]
        var representative: CGWindowID?
    }

    private struct QaWindow: Codable {
        var index: Int
        var wid: CGWindowID?
        var title: String
        var app: String?
        var bundleId: String?
        var pid: pid_t
        var shown: Bool
        var tabbed: Bool
        var groupId: Int?
        var siblings: [CGWindowID]?
        var isGroupRepresentative: Bool
        var tabCount: Int
        var phantom: Bool
        var phantomLatch: Bool
        var held: Bool
        var fullscreen: Bool
        var fullscreenMirrored: Bool
        var minimized: Bool
        var appHidden: Bool
        var windowless: Bool
        var focused: Bool
        var isMainWindow: Bool
        var spaceIds: [UInt64]
        var spaceIndexes: [Int]
        var spaceIsBorrowed: Bool
        var lastFocusOrder: Int
        var creationOrder: Int
        var focusedAt: TimeInterval
        var position: CGPoint?
        var size: CGSize?
        var axHash: Int?
    }

    private struct JsonWindowList: Codable {
        var windows: [JsonWindow]
    }

    private struct JsonWindow: Codable {
        var id: CGWindowID?
        var title: String
    }

    private struct JsonWindowFullList: Codable {
        var windows: [JsonWindowFull]
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
    }
}

class CliClient {
    static func detectCommand() -> String? {
        let args = CommandLine.arguments
        if args.count == 2 && !args[1].starts(with: "--logs=") {
            if args[1] == "--list" || args[1] == "--detailed-list" || args[1] == "--qa-state" || args[1] == "--qa-telemetry" || args[1] == "--hide" || args[1].hasPrefix("--qa-mark=") || args[1].hasPrefix("--focus=") || args[1].hasPrefix("--focusUsingLastFocusOrder=") || args[1].hasPrefix("--show=") {
                return args[1]
            }
        }
        return nil
    }

    /// Every failure exits non-zero and says which one it was, on stderr so it cannot be mistaken for the
    /// answer. Silence on stdout with exit 0 means one thing only: the command ran and has no output.
    /// A reply of zero bytes is a failure, not an answer — that is what the callback returning NULL looks
    /// like from here, and reading it as success is what let a broken port pass for a healthy one.
    static func sendCommandAndProcessResponse(_ command: String) {
        do {
            let serverPortClient = try CFMessagePortCreateRemote(nil, CliEvents.portName as CFString).unwrapOrThrow()
            let data = try command.data(using: .utf8).unwrapOrThrow()
            var returnData: Unmanaged<CFData>?
            let status = CFMessagePortSendRequest(serverPortClient, 0, data as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &returnData)
            guard let responseData = returnData?.takeRetainedValue() as Data?, !responseData.isEmpty else {
                fail("AltTab did not answer \(command) (CFMessagePortSendRequest status \(status), "
                    + "\(returnData == nil ? "no reply" : "empty reply"))")
            }
            guard let response = String(data: responseData, encoding: .utf8) else {
                fail("AltTab's answer to \(command) is \(responseData.count) bytes that are not text")
            }
            guard response != "\"\(CliServer.error)\"" else {
                fail("Couldn't execute command. Is it correct?")
            }
            if response != "\"\(CliServer.noOutput)\"" {
                print(response)
            }
            exit(0)
        } catch {
            fail("AltTab.app needs to be running for CLI commands to work")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
