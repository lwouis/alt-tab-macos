import Cocoa

class AboutTab {
    static func initTab() -> NSView {
        makeContentView()
    }

    static func makeContentView(_ fitToContent: Bool = true, _ showFeedbackButton: Bool = true, _ centerHero: Bool = false) -> NSView {
        let appIcon = LightImageView()
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.updateContents(.cgImage(App.appIcon), NSSize(width: 128, height: 128))
        appIcon.fit(128, 128)
        let appText = StackView([
            BoldLabel(App.name),
            NSTextField(wrappingLabelWithString: NSLocalizedString("Version", comment: "") + " " + App.version),
            NSTextField(wrappingLabelWithString: App.licence),
            HyperlinkLabel(NSLocalizedString("Source code repository", comment: ""), App.repository),
            HyperlinkLabel(NSLocalizedString("Latest releases", comment: ""), App.repository + "/releases"),
        ], .vertical)
        appText.spacing = GridView.interPadding / 2
        let rowToSeparate = 3
        appText.views[rowToSeparate].topAnchor.constraint(equalTo: appText.views[rowToSeparate - 1].bottomAnchor, constant: GridView.interPadding).isActive = true
        let appInfo = NSStackView(views: [appIcon, appText])
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appInfo.spacing = GridView.interPadding
        appInfo.alignment = .centerY
        let supportProject = makeSupportProjectButton()
        let rows = [[appInfo], [supportProject]]
        let grid = GridView(rows, 0)
        if centerHero {
            grid.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .center
        }
        let supportProjectCell = grid.cell(atColumnIndex: 0, rowIndex: showFeedbackButton ? 2 : 1)
        supportProjectCell.xPlacement = .center
        if fitToContent {
            grid.fit()
        }
        return grid
    }

    static func makeSupportProjectButton() -> NSButton {
        let button = makeButtonWithIcon(NSLocalizedString("Support this project", comment: ""), App.supportProjectAction, "heart.fill", .red, App.self)
        styleSupportProjectButton(button)
        return button
    }

    private static func styleSupportProjectButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private static func makeButtonWithIcon(_ title: String, _ selector: Selector, _ symbolName: String?, _ color: NSColor? = nil, _ target: AnyObject? = nil) -> NSButton {
        let button = NSButton(title: title, target: target, action: selector)
        if #available(macOS 26.0, *), let symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            if let color {
                button.image = button.image?.withSymbolConfiguration(.init(paletteColors: [color]))
            }
        }
        return button
    }
}

class AboutWindow: NSPanel {
    private static let contentPadding = CGFloat(24)
    static var shared: AboutWindow?

    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 450), styleMask: [.utilityWindow, .titled, .closable], backing: .buffered, defer: false)
        setupWindow()
        setupView()
        setFrameAutosaveName("AboutWindow")
        Self.shared = self
    }

    private func setupWindow() {
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        title = String(format: NSLocalizedString("About %@", comment: ""), App.name)
    }

    private func setupView() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        let documentView = FlippedView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 30
        stack.translatesAutoresizingMaskIntoConstraints = false
        let aboutView = AboutTab.makeContentView(false, false, true)
        let acknowledgmentsColumnWidth = frame.width - 2 * Self.contentPadding
        let acknowledgmentsView = AcknowledgmentsTab.makeContentView(columnWidth: acknowledgmentsColumnWidth, shouldFit: false, verticallyStacked: true)
        acknowledgmentsView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(aboutView)
        stack.addArrangedSubview(acknowledgmentsView)
        documentView.addSubview(stack)
        contentView = scrollView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: Self.contentPadding),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: Self.contentPadding),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Self.contentPadding),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -Self.contentPadding),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            aboutView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            aboutView.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            acknowledgmentsView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            acknowledgmentsView.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}
