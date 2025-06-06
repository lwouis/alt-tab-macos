import Cocoa

class CustomizeStyleSheet: SheetWindow {
    static let illustratedImageWidth = width

    let style = Preferences.appearanceStyle
    var illustratedImageView: IllustratedImageThemeView!
    var showHideIllustratedView: ShowHideIllustratedView!

    var alignThumbnails: TableGroupView.Row!
    var titleTruncation: TableGroupView.Row!
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

        control = NSSegmentedControl(
            labels: [
                NSLocalizedString("Show & Hide", comment: ""),
                NSLocalizedString("Advanced", comment: "")
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(switchTab(_:))
        )
        control.selectedSegment = 0
        control.segmentStyle = .automatic
        control.widthAnchor.constraint(equalToConstant: CustomizeStyleSheet.width).isActive = true

        let view = TableGroupSetView(
            originalViews: [illustratedImageView, control, showHideView, advancedView],
            padding: 0
        )
        return view
    }

    override func setupView() {
        super.setupView()
        switchTab(control)
    }

    private func makeComponents() {
        illustratedImageView = IllustratedImageThemeView(style, CustomizeStyleSheet.illustratedImageWidth)
        showHideIllustratedView = ShowHideIllustratedView(style, illustratedImageView)

        alignThumbnails = TableGroupView.Row(
            leftTitle: NSLocalizedString("Align windows", comment: ""),
            rightViews: LabelAndControl.makeRadioButtons(
                "alignThumbnails",
                AlignThumbnailsPreference.allCases,
                extraAction: { _ in self.showAlignThumbnailsIllustratedImage() }
            )
        )

        titleTruncation = TableGroupView.Row(
            leftTitle: NSLocalizedString("Title truncation", comment: ""),
            rightViews: LabelAndControl.makeRadioButtons(
                "titleTruncation",
                TitleTruncationPreference.allCases
            )
        )

        showTitles = TableGroupView.Row(
            leftTitle: NSLocalizedString("Show titles", comment: ""),
            rightViews: [
                LabelAndControl.makeDropdown(
                    "showTitles",
                    ShowTitlesPreference.allCases,
                    extraAction: { _ in self.showAlignThumbnailsIllustratedImage() }
                )
            ]
        )
    }

    private func makeThumbnailsView() -> TableGroupSetView {
        let table = TableGroupView(width: CustomizeStyleSheet.width)

        showTitlesRowInfo = table.addRow(
            showTitles,
            onMouseEntered: { event, view in
                self.showAlignThumbnailsIllustratedImage()
            }
        )
        table.addNewTable()
        table.addRow(
            alignThumbnails,
            onMouseEntered: { event, view in
                self.showAlignThumbnailsIllustratedImage()
            },
            onMouseExited: { event, view in
                IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
            }
        )
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
        table.addRow(
            alignThumbnails,
            onMouseEntered: { event, view in
                self.showAlignThumbnailsIllustratedImage()
            }
        )
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

        // Removed the old “Show in switcher” row entirely.

        view.addNewTable()
        showTitlesRowInfo = view.addRow(
            showTitles,
            onMouseEntered: { event, view in
                self.showAlignThumbnailsIllustratedImage()
            }
        )
        view.onMouseExited = { event, view in
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
        }
        return view
    }

    private func toggleAppNamesWindowTitles() {
        // Now read the per-shortcut “Show in switcher” value using the current index
        let isEnabled = (Preferences.showAppsOrWindows[App.app.shortcutIndex] == .windows)
                        || (Preferences.appearanceStyle == .thumbnails)

        showTitlesRowInfo.leftViews?.forEach { view in
            if let tf = view as? NSTextField {
                tf.textColor = isEnabled ? .textColor : .gray
            }
        }
        showTitlesRowInfo.rightViews?.forEach { view in
            if let ctrl = view as? NSControl {
                ctrl.isEnabled = isEnabled
            }
        }
    }

    private func showAlignThumbnailsIllustratedImage() {
        illustratedImageView.highlight(
            true,
            Preferences.alignThumbnails.image.name
        )
    }

    @objc func switchTab(_ sender: NSSegmentedControl) {
        let selectedIndex = sender.selectedSegment
        [showHideView, advancedView].enumerated().forEach { (index, view) in
            view!.isHidden = (index != selectedIndex)
        }
        adjustWindowHeight()
    }

    private func adjustWindowHeight() {
        guard let contentView else { return }
        let fittingSize = contentView.fittingSize
        var windowFrame = frame
        windowFrame.size.height = fittingSize.height
        setFrame(windowFrame, display: true, animate: false)
    }
}
