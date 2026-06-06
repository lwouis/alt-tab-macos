import SwiftUI

/// NSWindow subclass that hosts the SwiftUI settings interface via `NSHostingController`.
@available(macOS 13.0, *)
final class SwiftUISettingsWindow: NSWindow {
    static var shared: SwiftUISettingsWindow?
    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }

    static let sidebarWidth: CGFloat = 175
    static let contentWidth: CGFloat = 700
    static let sectionContentHorizontalMargin: CGFloat = 15
    static let defaultWindowHeight: CGFloat = 570
    static let minWindowHeight: CGFloat = 400

    static var totalWindowWidth: CGFloat { sidebarWidth + contentWidth }

    private let store = PreferencesStore()
    private let proTracker = ProStateTracker()
    private let searchVM = SearchViewModel()

    convenience init() {
        let width = Self.totalWindowWidth
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: Self.defaultWindowHeight),
            styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        minSize = NSSize(width: width, height: Self.minWindowHeight)
        maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "SwiftUISettingsToolbar")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        toolbarStyle = .unified
        titlebarSeparatorStyle = .none

        let rootView = ContentView()
            .environmentObject(store)
            .environmentObject(proTracker)
            .environmentObject(searchVM)
        let hostingController = NSHostingController(rootView: rootView)
        self.contentViewController = hostingController

        setFrameAutosaveName("SwiftUISettingsWindow")
        if UserDefaults.standard.string(forKey: "NSWindow Frame SwiftUISettingsWindow") == nil {
            setContentSize(NSSize(width: width, height: Self.defaultWindowHeight))
            center()
        }
        Self.shared = self
    }

    override func close() {
        Self.shared = nil
        super.close()
    }
}
