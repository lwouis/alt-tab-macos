import Cocoa

class CustomizeStyleSheet: SheetWindow {
    static let illustratedImageWidth = width

    let model = Preferences.appearanceModel
    var illustratedImageView: IllustratedImageThemeView!
    var alignThumbnails: TableGroupView.Row!
    var titleTruncation: TableGroupView.Row!
    var showAppsWindows: TableGroupView.Row!
    var showAppNamesWindowTitles: TableGroupView.Row!

    var showHideView: TableGroupSetView!
    var advancedView: TableGroupSetView!
    var control: NSSegmentedControl!

    override func makeContentView() -> NSView {
        makeComponents()
        showHideView = ShowHideIllustratedView(model, illustratedImageView).makeView()

        if model == .thumbnails {
            advancedView = makeThumbnailsView()
        } else if model == .appIcons {
            advancedView = makeAppIconsView()
        } else if model == .titles {
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
        illustratedImageView = IllustratedImageThemeView(model, CustomizeStyleSheet.illustratedImageWidth)
        alignThumbnails = TableGroupView.Row(leftTitle: NSLocalizedString("Align windows", comment: ""),
                rightViews: [LabelAndControl.makeDropdown(
                        "alignThumbnails", AlignThumbnailsPreference.allCases, extraAction: { _ in
                    self.showAlignThumbnailsIllustratedImage()
                })])
        titleTruncation = TableGroupView.Row(leftTitle: NSLocalizedString("Window title truncation", comment: ""),
                rightViews: [LabelAndControl.makeDropdown("titleTruncation", TitleTruncationPreference.allCases)])
        showAppsWindows = TableGroupView.Row(leftTitle: NSLocalizedString("Show running", comment: ""),
                rightViews: LabelAndControl.makeRadioButtons(ShowAppsWindowsPreference.allCases,
                        "showAppsWindows", extraAction: { _ in
                    self.toggleAppNamesWindowTitles()
                    self.showAppsOrWindowsIllustratedImage()
                }))
        showAppNamesWindowTitles = TableGroupView.Row(leftTitle: NSLocalizedString("Show titles", comment: ""),
                rightViews: [LabelAndControl.makeDropdown(
                        "showAppNamesWindowTitles", ShowAppNamesWindowTitlesPreference.allCases, extraAction: { _ in
                    self.showAppsOrWindowsIllustratedImage()
                })])
    }

    private func makeThumbnailsView() -> TableGroupSetView {
        let table = TableGroupView(width: CustomizeStyleSheet.width)
        _ = table.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        }, onMouseExited: { event, view in
            self.illustratedImageView.highlight(false)
        })
        _ = table.addRow(titleTruncation)
        table.onMouseExited = { event, view in
            self.illustratedImageView.highlight(false)
        }
        table.fit()

        let view = TableGroupSetView(originalViews: [table], padding: 0)
        return view
    }

    private func makeAppIconsView() -> TableGroupSetView {
        let table1 = makeAppWindowTableGroupView()
        table1.fit()

        let table2 = TableGroupView(width: CustomizeStyleSheet.width)
        _ = table2.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        })
        table2.onMouseExited = { event, view in
            self.illustratedImageView.highlight(false)
        }
        table2.fit()

        let view = TableGroupSetView(originalViews: [table1, table2], padding: 0)
        toggleAppNamesWindowTitles()
        return view
    }

    private func makeTitlesView() -> TableGroupSetView {
        let table1 = makeAppWindowTableGroupView()
        table1.fit()

        let table2 = TableGroupView(width: CustomizeStyleSheet.width)
        _ = table2.addRow(titleTruncation)
        table2.fit()

        let view = TableGroupSetView(originalViews: [table1, table2], padding: 0)
        toggleAppNamesWindowTitles()
        return view
    }

    private func makeAppWindowTableGroupView() -> TableGroupView {
        let view = TableGroupView(title: NSLocalizedString("Applications & Windows", comment: ""),
                subTitle: NSLocalizedString("Provide the ability to switch between displaying applications in a windowed form (allowing an application to contain multiple windows) or in an application form (where each application can only have one window).", comment: ""),
                width: CustomizeStyleSheet.width)
        _ = view.addRow(showAppsWindows, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        _ = view.addRow(showAppNamesWindowTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        view.onMouseExited = { event, view in
            self.illustratedImageView.highlight(false)
        }
        return view
    }

    private func toggleAppNamesWindowTitles() {
        let button = showAppNamesWindowTitles.rightViews[0] as? NSControl
        if Preferences.showAppsWindows == .windows {
            button?.isEnabled = true
        } else {
            button?.isEnabled = false
        }
    }

    private func showAlignThumbnailsIllustratedImage() {
        self.illustratedImageView.highlight(true, Preferences.alignThumbnails.image.name)
    }

    private func showAppsOrWindowsIllustratedImage() {
        var imageName = ShowAppNamesWindowTitlesPreference.windowTitles.image.name
        if Preferences.showAppsWindows == .applications || Preferences.showAppNamesWindowTitles == .applicationNames {
            imageName = ShowAppNamesWindowTitlesPreference.applicationNames.image.name
        } else if Preferences.showAppNamesWindowTitles == .applicationNamesAndWindowTitles {
            imageName = ShowAppNamesWindowTitlesPreference.applicationNamesAndWindowTitles.image.name
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
