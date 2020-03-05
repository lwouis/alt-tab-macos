import Cocoa
import Darwin
import LetsMove

let cgsMainConnectionId = CGSMainConnectionID()

class App: NSApplication, NSApplicationDelegate {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
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
            debugPrint("focusTarget: appIsBeingUsed")
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
        uiWorkShouldBeDone = true
        showUiOrCycleSelection(0)
    }

    func cycleSelection(_ step: Int) {
        Windows.cycleFocusedWindowIndex(step)
        thumbnailsPanel!.highlightCell()
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
            // TODO: find a way to update thumbnails by listening to content change, instead of every trigger. Or better, switch to video
            Windows.refreshAllThumbnails()
            Windows.focusedWindowIndex = 0
            Windows.cycleFocusedWindowIndex(step)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay, execute: { [weak self] in
                guard let self = self else { return }
                self.refreshOpenUi()
                if self.uiWorkShouldBeDone { self.thumbnailsPanel?.show() }
            })
        } else {
            debugPrint("showUiOrCycleSelection: !isFirstSummon")
            cycleSelection(step)
        }
    }

    func reopenUi() {
        thumbnailsPanel!.orderOut(nil)
        Windows.refreshAllThumbnails()
        refreshOpenUi()
        thumbnailsPanel!.show()
    }

    func refreshOpenUi() {
        guard appIsBeingUsed else { return }
        let currentScreen = Screen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        if uiWorkShouldBeDone { thumbnailsPanel!.refreshCollectionView(currentScreen, uiWorkShouldBeDone); debugPrint("refreshCollectionView") }
        if uiWorkShouldBeDone { thumbnailsPanel!.highlightCell(); debugPrint("highlightCellAt") }
        if uiWorkShouldBeDone { Screen.repositionPanel(thumbnailsPanel!, currentScreen, .appleCentered); debugPrint("repositionPanel") }
    }

    func focusSelectedWindow(_ window: Window?) {
        hideUi()
        guard !CGWindow.isMissionControlActive() else { return }
        window?.focus()
    }
}
