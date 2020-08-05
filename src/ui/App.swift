import Cocoa
import Darwin
import LetsMove
import ShortcutRecorder
import Preferences

let cgsMainConnectionId = CGSMainConnectionID()

class App: AppCenterApplication, NSApplicationDelegate {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let id = Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static var app: App!
    static var statusItem: NSStatusItem!
    var thumbnailsPanel: ThumbnailsPanel!
    var preferencesWindowController: PreferencesWindowController!
    var feedbackWindow: FeedbackWindow?
    var isFirstSummon = true
    var appIsBeingUsed = false
    var shortcutsShouldBeDisabled = false
    var shortcutIndex = 0
    var appCenterDelegate: AppCenterCrash?

    override init() {
        super.init()
        delegate = self
        App.app = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        appCenterDelegate = AppCenterCrash()
        NSApp.disableRelaunchOnLogin()
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        #endif
        #if !DEBUG
        PFMoveToApplicationsFolderIfNecessary()
        #endif
        AXUIElement.setGlobalTimeout()
        SystemPermissions.ensurePermissionsAreGranted { [weak self] in
            guard let self = self else { return }
            BackgroundWork.start()
            Preferences.migratePreferences()
            Preferences.registerDefaults()
            App.statusItem = Menubar.make()
            self.loadMainMenuXib()
            self.thumbnailsPanel = ThumbnailsPanel()
            Spaces.initialDiscovery()
            Applications.initialDiscovery()
            self.loadPreferencesWindow()
            KeyboardEvents.observe()
            MouseEvents.observe()
            // TODO: undeterministic; events in the queue may still be processing; good enough for now
            DispatchQueue.main.async { () -> () in Windows.sortByLevel() }
            self.preloadWindows()
            #if DEBUG
            self.preferencesWindowController.show()
            #endif
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        showPreferencesPanel()
        return true
    }

    // pre-load some windows so they are faster on first display
    private func preloadWindows() {
        thumbnailsPanel.orderFront(nil)
        thumbnailsPanel.orderOut(nil)
    }

    private func loadPreferencesWindow() {
        let tabs = [
            GeneralTab(),
            ControlsTab(),
            AppearanceTab(),
            PoliciesTab(),
            BlacklistsTab(),
            AboutTab(),
            AcknowledgmentsTab(),
        ]
        // pre-load tabs so we can interact with them before the user opens the preferences window
        let widest = tabs.reduce(CGFloat(0), {
            $1.loadView()
            return max($0, $1.view.subviews[0].fittingSize.width)
        })
        tabs.forEach {
            $0.view.fit(widest, $0.view.subviews[0].fittingSize.height)
        }

        preferencesWindowController = PreferencesWindowController(preferencePanes: tabs as! [PreferencePane])

        let window = preferencesWindowController.window!
        let quitButton = NSButton(title: NSLocalizedString("Quit", comment: ""), target: nil, action: #selector(NSApplication.terminate(_:)))
        let titleBarView = window.standardWindowButton(.closeButton)!.superview!
        titleBarView.addSubview(quitButton)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.topAnchor.constraint(equalTo: titleBarView.topAnchor, constant: 5).isActive = true
        quitButton.rightAnchor.constraint(equalTo: titleBarView.rightAnchor, constant: -8).isActive = true
    }

    // keyboard shortcuts are broken without a menu. We generated the default menu from XCode and load it
    // see https://stackoverflow.com/a/3746058/2249756
    private func loadMainMenuXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        menu = menuObjects?.first { $0 is NSMenu } as? NSMenu
    }

    // we put application code here which should be executed on init() and Preferences change
    func resetPreferencesDependentComponents() {
        ThumbnailsView.recycledViews = ThumbnailsView.recycledViews.map { _ in ThumbnailView() }
        thumbnailsPanel.thumbnailsView.layer!.cornerRadius = Preferences.windowCornerRadius
    }

    func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }

    func hideUi() {
        debugPrint("hideUi")
        appIsBeingUsed = false
        isFirstSummon = true
        MouseEvents.disable()
        thumbnailsPanel.orderOut(nil)
    }

    func closeSelectedWindow() {
        Windows.focusedWindow()?.close()
    }

    func minDeminSelectedWindow() {
        Windows.focusedWindow()?.minDemin()
    }

    func quitSelectedApp() {
        Windows.focusedWindow()?.quitApp()
    }

    func hideShowSelectedApp() {
        Windows.focusedWindow()?.hideShowApp()
    }

    func focusTarget() {
        debugPrint("focusTarget")
        focusSelectedWindow(Windows.focusedWindow())
    }

    @objc func checkForUpdatesNow(_ sender: NSMenuItem) {
        PoliciesTab.checkForUpdatesNow(sender)
    }

    @objc func showPreferencesPanel() {
        if let preferencesWindow = preferencesWindowController.window {
            Screen.repositionPanel(preferencesWindow, Screen.preferred(), .appleCentered)
            preferencesWindowController.show()
        }
    }

    @objc func showFeedbackPanel() {
        if feedbackWindow == nil {
            feedbackWindow = FeedbackWindow()
        }
        Screen.repositionPanel(feedbackWindow!, Screen.preferred(), .appleCentered)
        feedbackWindow?.show()
    }

    @objc func showUi() {
        appIsBeingUsed = true
        DispatchQueue.main.async { () -> () in self.showUiOrCycleSelection(0) }
    }

    func cycleSelection(_ direction: Direction) {
        if direction == .up || direction == .down {
            thumbnailsPanel.thumbnailsView.navigateUpOrDown(direction)
        } else {
            Windows.cycleFocusedWindowIndex(direction.step())
        }
    }

    func focusSelectedWindow(_ window: Window?) {
        hideUi()
        guard !CGWindow.isMissionControlActive() else { return }
        window?.focus()
    }

    func reopenUi() {
        thumbnailsPanel.orderOut(nil)
        rebuildUi()
    }

    func refreshOpenUi(_ windowsToUpdate: [Window]? = nil) {
        guard appIsBeingUsed else { return }
        let currentScreen = Screen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refreshCurrentSpaceId()
        refreshSpecificWindows(windowsToUpdate, currentScreen)
        guard appIsBeingUsed else { return }
        thumbnailsPanel.thumbnailsView.updateItemsAndLayout(currentScreen)
        guard appIsBeingUsed else { return }
        thumbnailsPanel.setFrame(thumbnailsPanel.thumbnailsView.frame, display: false)
        guard appIsBeingUsed else { return }
        Screen.repositionPanel(thumbnailsPanel, currentScreen, .appleCentered)
    }

    private func refreshSpecificWindows(_ windowsToUpdate: [Window]?, _ currentScreen: NSScreen) -> ()? {
        windowsToUpdate?.forEach { (window: Window) in
            guard appIsBeingUsed else { return }
            window.refreshThumbnail()
            Windows.refreshIfWindowShouldBeShownToTheUser(window, currentScreen)
            if !window.shouldShowTheUser && window.cgWindowId == Windows.focusedWindow()!.cgWindowId {
                let stepWithClosestWindow = Windows.windowIndexAfterCycling(-1) > Windows.focusedWindowIndex ? 1 : -1
                Windows.cycleFocusedWindowIndex(stepWithClosestWindow)
            } else {
                Windows.updatesWindowSpace(window)
            }
        }
    }

    func showUiOrCycleSelection(_ shortcutIndex: Int) {
        debugPrint("showUiOrCycleSelection")
        if isFirstSummon {
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            isFirstSummon = false
            if Windows.list.count == 0 || CGWindow.isMissionControlActive() { hideUi(); return }
            // TODO: find a way to update space info when spaces are changed, instead of on every trigger
            // replace with:
            // So far, the best signal I've found is to watch com.apple.dock for the uiElementDestroyed notification.
            // When Mission Control is triggered, an AXGroup element is created (with some nested groups for the window and desktop buttons).
            // There's no way to observe this with the AX API, other than polling. However, when Mission Control is deactivated,
            // that AXGroup gets destroyed, triggering the uiElementDestroyed notification.
            // (At that point we won't be able to see what the element was, of course.)
            Spaces.idsAndIndexes = Spaces.allIdsAndIndexes()
            Windows.updateSpaces()
            let screen = Screen.preferred()
            self.shortcutIndex = shortcutIndex
            Windows.refreshWhichWindowsToShowTheUser(screen)
            if (!Windows.list.contains { $0.shouldShowTheUser }) { hideUi(); return }
            Windows.updateFocusedWindowIndex(0)
            Windows.cycleFocusedWindowIndex(1)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) { () -> () in
                self.rebuildUi()
            }
        } else {
            cycleSelection(.leading)
        }
    }

    func rebuildUi() {
        guard appIsBeingUsed else { return }
        Windows.refreshAllThumbnails()
        guard appIsBeingUsed else { return }
        refreshOpenUi()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.show()
    }
}
