import Cocoa

class Day4TourPopover {
    private static var popover: AnchoredPopover?

    static func show() {
        guard popover?.isShown != true else { return }
        let popover = ProPromptPopover.make()
        self.popover = popover
        ProPromptPopover.present(popover, content: makeContent { [weak popover] style in
            popover?.acknowledgePresentation()
            if style != .thumbnails, LicenseManager.shared.isProAvailable {
                Preferences.set("appearanceStyle", style.indexAsString)
                if Preferences.hasOverride("appearanceStyleOverride", 0) {
                    Preferences.set("appearanceStyleOverride", style.indexAsString)
                }
            }
            popover?.close()
        }, onShown: {
            ProTransitionManager.shared.state.day4TourDeferred = false
        })
    }

    static func makeContent(select: @escaping (AppearanceStylePreference) -> Void) -> NSView {
        let cards = NSStackView()
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.orientation = .horizontal
        cards.distribution = .fillEqually
        cards.spacing = 12
        for style in AppearanceStylePreference.allCases {
            let image = NSImageView()
            image.image =
                IllustratedImageThemeView.loadIllustration(IllustratedImageThemeView.getConcatenatedImageName(
                    style,
                    "light"
                ))
            image.imageScaling = .scaleProportionallyUpOrDown
            image.translatesAutoresizingMaskIntoConstraints = false
            image.heightAnchor.constraint(equalToConstant: 108).isActive = true
            image.widthAnchor.constraint(equalToConstant: 164).isActive = true
            image.setAccessibilityLabel(style.localizedString)
            let title: String
            switch style {
            case .thumbnails: title = NSLocalizedString("Keep Thumbnails", comment: "")
            case .appIcons: title = NSLocalizedString("Use App Icons", comment: "")
            case .titles: title = NSLocalizedString("Use Titles", comment: "")
            }
            let button = ProPromptButtons.makePrimary(title) { select(style) }
            let card = NSStackView(views: [image, button])
            button.widthAnchor.constraint(equalTo: image.widthAnchor).isActive = true
            card.orientation = .vertical
            card.spacing = 10
            cards.addArrangedSubview(card)
            if style == .thumbnails {
                cards.setCustomSpacing(24, after: card)
                let separator = NSBox()
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.setAccessibilityElement(false)
                cards.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.widthAnchor.constraint(equalToConstant: 1),
                    separator.centerXAnchor.constraint(equalTo: card.trailingAnchor, constant: 12),
                    separator.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                    separator.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
                ])
            }
        }
        let title = ProPromptPopover.makeTitle(NSLocalizedString("Try a different window style", comment: ""))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: NSLocalizedString("You can change it anytime in Settings.", comment: ""))
        detail.textColor = .secondaryLabelColor
        detail.isSelectable = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.preferredMaxLayoutWidth = 528
        return ProPromptPopover.makeContainer(width: 560, [
            .init(view: title, gapAbove: 0, width: .full),
            .init(view: detail, gapAbove: 6, width: .full),
            .init(view: cards, gapAbove: 16, width: .full),
        ])
    }
}
