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
        let choices = AppearanceStylePreference.allCases.map { style in
            (style, ProPromptButtons.makePrimary(buttonTitle(style)) { select(style) })
        }
        let cardWidth = max(164, (choices.map { $0.1.intrinsicContentSize.width }.max() ?? 164).rounded(.up))
        let cards = NSStackView()
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.orientation = .horizontal
        cards.distribution = .fillEqually
        cards.spacing = 12
        for (style, button) in choices {
            let image = LocalizedIllustrationView("settings-" + style.image.name.replacingOccurrences(of: "_", with: "-"))
            image.imageScaling = .scaleProportionallyUpOrDown
            image.translatesAutoresizingMaskIntoConstraints = false
            image.heightAnchor.constraint(equalToConstant: cardWidth * 108 / 164).isActive = true
            image.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
            let card = NSStackView(views: [image, button])
            button.widthAnchor.constraint(equalTo: image.widthAnchor).isActive = true
            card.orientation = .vertical
            card.spacing = 10
            cards.addArrangedSubview(card)
            if style == .thumbnails {
                cards.setCustomSpacing(40, after: card)
                let separator = NSBox()
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.setAccessibilityElement(false)
                cards.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.widthAnchor.constraint(equalToConstant: 1),
                    separator.centerXAnchor.constraint(equalTo: card.trailingAnchor, constant: 20),
                    separator.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
                    separator.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
                ])
            }
        }
        let width = cardWidth * CGFloat(choices.count) + 40 + cards.spacing + 2 * ProPromptPopover.padding
        let title = ProPromptPopover.makeTitle(NSLocalizedString("Try a different window style", comment: ""))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: NSLocalizedString("You can change it anytime in Settings", comment: ""))
        detail.textColor = .secondaryLabelColor
        detail.isSelectable = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.preferredMaxLayoutWidth = width - 2 * ProPromptPopover.padding
        return ProPromptPopover.makeContainer(width: width, [
            .init(view: title, gapAbove: 0, width: .full),
            .init(view: detail, gapAbove: 6, width: .full),
            .init(view: cards, gapAbove: 16, width: .full),
        ])
    }

    private static func buttonTitle(_ style: AppearanceStylePreference) -> String {
        switch style {
        case .thumbnails: return NSLocalizedString("Keep Thumbnails", comment: "")
        case .appIcons: return NSLocalizedString("Use App Icons", comment: "")
        case .titles: return NSLocalizedString("Use Titles", comment: "")
        }
    }
}
