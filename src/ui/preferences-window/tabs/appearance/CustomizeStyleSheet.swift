import Cocoa

class CustomizeStyleSheet: SheetWindow {
    static let illustratedImageWidth = width

    let style = Preferences.appearanceStyle
    var illustratedImageView: IllustratedImageThemeView!
    var alignThumbnails: TableGroupView.Row!
    var titleTruncation: TableGroupView.Row!
    var showAppsOrWindows: TableGroupView.Row!
    var showTitles: TableGroupView.Row!

    var showHideView: TableGroupSetView!
    var advancedView: TableGroupSetView!
    var control: NSSegmentedControl!

    override func makeContentView() -> NSView {
        makeComponents()
        showHideView = ShowHideIllustratedView(style, illustratedImageView).makeView()

        if style == .thumbnails {
            advancedView = makeThumbnailsView()
        } else if style == .appIcons {
            advancedView = makeAppIconsView()
        } else if style == .titles {
            advancedView = makeTitlesView()
        }
        control = NSSegmentedControl(labels: [
            NSLocalizedString("Show & Hide", comment: ""),
            NSLocalizedString("Advanced", comment: "")
        ], trackingMode: .selectOne, target: self, action: #selector(switchTab(_:)))
        control.selectedSegment = 0
        control.segmentStyle = .automatic
        control.widthAnchor.constraint(equalToConstant: CustomizeStyleSheet.width).isActive = true

        let view = TableGroupSetView(originalViews: [illustratedImageView, control, showHideView, advancedView], padding: 0)
        return view
    }

    override func setupView() {
        super.setupView()
        switchTab(control)
    }

    private func makeComponents() {
        illustratedImageView = IllustratedImageThemeView(style, CustomizeStyleSheet.illustratedImageWidth)
        alignThumbnails = TableGroupView.Row(leftTitle: NSLocalizedString("Align windows", comment: ""),
                rightViews: LabelAndControl.makeRadioButtons(
                        "alignThumbnails", AlignThumbnailsPreference.allCases, extraAction: { _ in
                    self.showAlignThumbnailsIllustratedImage()
                }))
        titleTruncation = TableGroupView.Row(leftTitle: NSLocalizedString("Title truncation", comment: ""),
                rightViews: LabelAndControl.makeRadioButtons("titleTruncation", TitleTruncationPreference.allCases))
        showAppsOrWindows = TableGroupView.Row(leftTitle: NSLocalizedString("Show in switcher", comment: ""),
                rightViews: LabelAndControl.makeRadioButtons("showAppsOrWindows", ShowAppsOrWindowsPreference.allCases, extraAction: { _ in
                    self.toggleAppNamesWindowTitles()
                    self.showAppsOrWindowsIllustratedImage()
                }))
        showTitles = TableGroupView.Row(leftTitle: NSLocalizedString("Show titles", comment: ""),
                rightViews: [LabelAndControl.makeDropdown(
                        "showTitles", ShowTitlesPreference.allCases, extraAction: { _ in
                    self.showAppsOrWindowsIllustratedImage()
                })])
    }

    private func makeThumbnailsView() -> TableGroupSetView {
        let table = TableGroupView(width: CustomizeStyleSheet.width)
        table.addRow(showTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        table.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        }, onMouseExited: { event, view in
            self.illustratedImageView.highlight(false)
        })
        table.addRow(titleTruncation)
        table.onMouseExited = { event, view in
            self.illustratedImageView.highlight(false)
        }
        table.fit()

        let view = TableGroupSetView(originalViews: [table], padding: 0)
        return view
    }

    private func makeAppIconsView() -> TableGroupSetView {
        let table = makeAppWindowTableGroupView()

        table.addNewTable()
        table.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        })
        table.onMouseExited = { event, view in
            self.illustratedImageView.highlight(false)
        }
        table.fit()

        let view = TableGroupSetView(originalViews: [table], padding: 0)
        toggleAppNamesWindowTitles()
        return view
    }

    private func makeTitlesView() -> TableGroupSetView {
        let table = makeAppWindowTableGroupView()

        table.addNewTable()
        table.addRow(titleTruncation)
        table.fit()

        let view = TableGroupSetView(originalViews: [table], padding: 0)
        toggleAppNamesWindowTitles()
        return view
    }

    private func makeAppWindowTableGroupView() -> TableGroupView {
        let view = TableGroupView(title: NSLocalizedString("Applications & Windows", comment: ""),
                subTitle: NSLocalizedString("Provide the ability to switch between displaying applications in a windowed form (allowing an application to contain multiple windows) or in an application form (where each application can only have one window).", comment: ""),
                width: CustomizeStyleSheet.width)
        _ = view.addRow(showAppsOrWindows, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        _ = view.addRow(showTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        view.onMouseExited = { event, view in
            self.illustratedImageView.highlight(false)
        }
        return view
    }

    private func toggleAppNamesWindowTitles() {
        let button = showTitles.rightViews[0] as? NSControl
        if Preferences.showAppsOrWindows == .windows {
            button?.isEnabled = true
        } else {
            button?.isEnabled = false
        }
    }

    private func showAlignThumbnailsIllustratedImage() {
        self.illustratedImageView.highlight(true, Preferences.alignThumbnails.image.name)
    }

    private func showAppsOrWindowsIllustratedImage() {
        var imageName = ShowTitlesPreference.windowTitle.image.name
        if Preferences.showAppsOrWindows == .applications || Preferences.showTitles == .appName {
            imageName = ShowTitlesPreference.appName.image.name
        } else if Preferences.showTitles == .appNameAndWindowTitle {
            imageName = ShowTitlesPreference.appNameAndWindowTitle.image.name
        }
        self.illustratedImageView.highlight(true, imageName)
    }

    @objc func switchTab(_ sender: NSSegmentedControl) {
        let selectedIndex = sender.selectedSegment
        [showHideView, advancedView].enumerated().forEach { (index, view) in
            if selectedIndex == index {
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }
        adjustWindowHeight()
    }

    private func adjustWindowHeight() {
        guard let contentView = self.contentView else { return }

        // Calculate the fitting height of the content view
        let fittingSize = contentView.fittingSize
        var windowFrame = frame
        windowFrame.size.height = fittingSize.height
        setFrame(windowFrame, display: true, animate: false)
    }
}
