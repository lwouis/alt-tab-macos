import Cocoa

/// Icon-left, title-right header used by every Pro-transition window. Provides app-icon branding
/// so each window reads as "AltTab is talking to you" without relying on a chrome titlebar.
/// Popovers don't use this — their menubar anchor already signals app context.
///
/// The "Pro" substring (last occurrence) in the title is auto-replaced with the gradient text
/// attachment from `ProGradient`. Translators must keep "Pro" verbatim in localized titles for
/// the gradient to apply; otherwise the title renders as plain text (graceful degradation).
class ProPromptHeader: NSStackView {
    enum Size {
        case large    // 48pt icon, 22pt bold title — for windows ≥ 400pt tall
        case compact  // 32pt icon, 16pt bold title — for the 240pt-tall short windows

        var iconSide: CGFloat { self == .large ? 48 : 32 }
        var titleFont: NSFont { .systemFont(ofSize: self == .large ? 22 : 16, weight: .bold) }
    }

    private let titleLabel = NSTextField()
    private let size: Size
    var title: String { didSet { applyTitle(title) } }

    init(title: String, size: Size) {
        self.title = title
        self.size = size
        super.init(frame: .zero)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.isSelectable = false
        applyTitle(title)

        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        addArrangedSubview(iconView)
        addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: size.iconSide),
            iconView.heightAnchor.constraint(equalToConstant: size.iconSide),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

    private func applyTitle(_ text: String) {
        let font = size.titleFont
        let attr = NSMutableAttributedString(string: text, attributes: [.font: font])
        if let range = text.range(of: "Pro", options: .backwards) {
            attr.replaceCharacters(in: NSRange(range, in: text),
                with: ProGradient.makeProTextAttachment(font: font))
        }
        titleLabel.attributedStringValue = attr
    }
}
