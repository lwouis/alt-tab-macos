import Cocoa

class CustomizeStyleSheet: SheetWindow {
    static let illustratedImageWidth = width

    let style = Preferences.appearanceStyle
    var illustratedImageView: IllustratedImageThemeView!
    var showHideIllustratedView: ShowHideIllustratedView!

    var alignThumbnails: TableGroupView.Row!
    var titleTruncation: TableGroupView.Row!
    var showAppsOrWindows: TableGroupView.Row!
    var showTitles: TableGroupView.Row!
    var showTitlesRowInfo: TableGroupView.RowInfo!

    var showHideView: TableGroupSetView!
    var advancedView: TableGroupSetView!
    var control: NSSegmentedControl!

    override func makeContentView() -> NSView {
        makeComponents()
        showHideView = showHideIllustratedView.makeView()
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
        showHideIllustratedView = ShowHideIllustratedView(style, illustratedImageView)
        alignThumbnails = TableGroupView.Row(leftTitle: NSLocalizedString("Align windows", comment: ""),
            rightViews: LabelAndControl.makeRadioButtons(
                "alignThumbnails", AlignThumbnailsPreference.allCases, extraAction: { _ in
                self.showAlignThumbnailsIllustratedImage()
            }))
        titleTruncation = TableGroupView.Row(leftTitle: NSLocalizedString("Title truncation", comment: ""),
            rightViews: LabelAndControl.makeRadioButtons("titleTruncation", TitleTruncationPreference.allCases))
        let showAppWindowsInfo = LabelAndControl.makeInfoButton(onMouseEntered: { (event, view) in
            Popover.shared.show(event: event, positioningView: view,
                message: NSLocalizedString("Show an item in the switcher for each window, or for each application. Windows will be focused, whereas applications will be activated.", comment: ""))
        }, onMouseExited: { (event, view) in
            Popover.shared.hide()
        })
        showAppsOrWindows = TableGroupView.Row(leftTitle: NSLocalizedString("Show in switcher", comment: ""),
            rightViews: LabelAndControl.makeRadioButtons("showAppsOrWindows", ShowAppsOrWindowsPreference.allCases, extraAction: { _ in
                self.showHideIllustratedView.setStateOnApplications()
                self.toggleAppNamesWindowTitles()
                self.showAppsOrWindowsIllustratedImage()
            }) + [showAppWindowsInfo])
        showTitles = TableGroupView.Row(leftTitle: NSLocalizedString("Show titles", comment: ""),
            rightViews: [LabelAndControl.makeDropdown(
                "showTitles", ShowTitlesPreference.allCases, extraAction: { _ in
                self.showAppsOrWindowsIllustratedImage()
            })])
    }

    private func makeThumbnailsView() -> TableGroupSetView {
        let table = TableGroupView(width: CustomizeStyleSheet.width)
        showTitlesRowInfo = table.addRow(showTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        table.addNewTable()
        table.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        }, onMouseExited: { event, view in
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
        })
        table.addRow(titleTruncation)
        table.onMouseExited = { event, view in
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
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
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
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
        let view = TableGroupView(width: CustomizeStyleSheet.width)
        view.addRow(showAppsOrWindows, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        view.addNewTable()
        showTitlesRowInfo = view.addRow(showTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        view.onMouseExited = { event, view in
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
        }
        return view
    }

    private func toggleAppNamesWindowTitles() {
        var isEnabled = false
        if Preferences.showAppsOrWindows == .windows || Preferences.appearanceStyle == .thumbnails {
            isEnabled = true
        }
        showTitlesRowInfo.leftViews?.forEach { view in
            if let view = view as? NSTextField {
                view.textColor = isEnabled ? NSColor.textColor : NSColor.gray
            }
        }
        showTitlesRowInfo.rightViews?.forEach { view in
            if let view = view as? NSControl {
                view.isEnabled = isEnabled
            }
        }
    }

    private func showAlignThumbnailsIllustratedImage() {
        illustratedImageView.highlight(true, Preferences.alignThumbnails.image.name)
    }

    private func showAppsOrWindowsIllustratedImage() {
        var imageName = Preferences.showTitles.image.name
        if Preferences.onlyShowApplications() {
            imageName = ShowTitlesPreference.appName.image.name
        }
        illustratedImageView.highlight(true, imageName)
    }

    @objc func switchTab(_ sender: NSSegmentedControl) {
        let selectedIndex = sender.selectedSegment
        [showHideView, advancedView].enumerated().forEach { (index, view) in
            if selectedIndex == index {
                view!.isHidden = false
            } else {
                view!.isHidden = true
            }
        }
        adjustWindowHeight()
    }

    private func adjustWindowHeight() {
        guard let contentView = contentView else { return }
        // Calculate the fitting height of the content view
        let fittingSize = contentView.fittingSize
        var windowFrame = frame
        windowFrame.size.height = fittingSize.height
        setFrame(windowFrame, display: true, animate: false)
    }
}
