import Cocoa
import Darwin
import LetsMove

let cgsMainConnectionId = CGSMainConnectionID()

class App: NSApplication, NSApplicationDelegate {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static let url = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
    var statusItem: NSStatusItem?
    var thumbnailsPanel: ThumbnailsPanel?
    var preferencesWindow: PreferencesWindow?
    var feedbackWindow: FeedbackWindow?
    var uiWorkShouldBeDone = true
    var isFirstSummon = true
    var appIsBeingUsed = false

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if !DEBUG
        PFMoveToApplicationsFolderIfNecessary()
        #endif
        SystemPermissions.ensureAccessibilityCheckboxIsChecked()
        SystemPermissions.ensureScreenRecordingCheckboxIsChecked()
        Preferences.registerDefaults()
        statusItem = Menubar.make(self)
        loadMainMenuXib()
        initPreferencesDependentComponents()
        Spaces.initialDiscovery()
        Applications.initialDiscovery()
        Keyboard.listenToGlobalEvents(self)
        preferencesWindow = PreferencesWindow()
        UpdatesTab.observeUserDefaults()
        // TODO: undeterministic; events in the queue may still be processing; good enough for now
        DispatchQueue.main.async { Windows.sortByLevel() }
    }

    // keyboard shortcuts are broken without a menu. We generated the default menu from XCode and load it
    // see https://stackoverflow.com/a/3746058/2249756
    private func loadMainMenuXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        menu = menuObjects?.first(where: { $0 is NSMenu }) as? NSMenu
    }

    // we put application code here which should be executed on init() and Preferences change
    func initPreferencesDependentComponents() {
        thumbnailsPanel = ThumbnailsPanel(self)
    }

    func hideUi() {
        debugPrint("hideUi")
        thumbnailsPanel!.orderOut(nil)
        appIsBeingUsed = false
        isFirstSummon = true
    }

    func focusTarget() {
        debugPrint("focusTarget")
        if appIsBeingUsed {
            let window = Windows.focusedWindow()
            focusSelectedWindow(window)
        }
    }

    @objc
    func checkForUpdatesNow(_ sender: NSMenuItem) {
        UpdatesTab.checkForUpdatesNow(sender)
    }

    @objc
    func showPreferencesPanel() {
        Screen.repositionPanel(preferencesWindow!, Screen.preferred(), .appleCentered)
        preferencesWindow?.show()
    }

    @objc
    func showFeedbackPanel() {
        if feedbackWindow == nil {
            feedbackWindow = FeedbackWindow()
        }
        Screen.repositionPanel(feedbackWindow!, Screen.preferred(), .appleCentered)
        feedbackWindow?.show()
    }

    @objc
    func showUi() {
        _ = dispatchWork { self.showUiOrCycleSelection(0) }
    }

    func cycleSelection(_ step: Int) {
        Windows.cycleFocusedWindowIndex(step)
    }

    func focusSelectedWindow(_ window: Window?) {
        hideUi()
        guard !CGWindow.isMissionControlActive() else { return }
        window?.focus()
    }

    func reopenUi() {
        thumbnailsPanel!.orderOut(nil)
        rebuildUi()
    }

    func refreshOpenUi(_ windowsToRefresh: [Window]? = nil) {
        guard appIsBeingUsed else { return }
        windowsToRefresh?.forEach { $0.refreshThumbnail() }
        let currentScreen = Screen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        guard uiWorkShouldBeDone else { return }
        thumbnailsPanel!.thumbnailsView.updateItems(currentScreen)
        thumbnailsPanel!.setFrame(thumbnailsPanel!.thumbnailsView.frame, display: false)
        guard uiWorkShouldBeDone else { return }
        Screen.repositionPanel(thumbnailsPanel!, currentScreen, .appleCentered)
    }

    func showUiOrCycleSelection(_ step: Int) {
        debugPrint("showUiOrCycleSelection", step)
        appIsBeingUsed = true
        if isFirstSummon {
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            isFirstSummon = false
            if Windows.list.count == 0 || CGWindow.isMissionControlActive() {
                appIsBeingUsed = false
                isFirstSummon = true
                return
            }
            // TODO: find a way to update isSingleSpace by listening to space creation, instead of on every trigger
            Spaces.updateIsSingleSpace()
            // TODO: find a way to update space index when windows are moved to another space, instead of on every trigger
            Windows.updateSpaces()
            Windows.updateFocusedWindowIndex(0)
            Windows.cycleFocusedWindowIndex(step)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) {
                self.rebuildUi()
            }
        } else {
            cycleSelection(step)
        }
    }

    func rebuildUi() {
        guard uiWorkShouldBeDone else { return }
        Windows.refreshAllThumbnails()
        guard uiWorkShouldBeDone else { return }
        refreshOpenUi()
        guard uiWorkShouldBeDone else { return }
        thumbnailsPanel!.show()
//        guard uiWorkShouldBeDone else { return }
//        DispatchQueue.main.async {
//            Windows.refreshAllExistingThumbnails()
//        }
    }
}
