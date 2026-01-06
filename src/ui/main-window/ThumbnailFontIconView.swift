import Cocoa

enum Symbols: String {
    case circledPlusSign = "􀁌"
    case circledMinusSign = "􀁎"
    case circledSlashSign = "􀕧"
    case circledNumber0 = "􀀸"
    case circledNumber10 = "􀓵"
    case circledStar = "􀕬"
    case filledCircledStar = "􀕭"
    case filledCircled = "􀀁"
    case filledCircledNumber0 = "􀀹"
    case filledCircledNumber10 = "􀔔"
    case circledInfo = "􀅴"
    case squareNumber0 = "􀃈"
    case squareNumber10 = "􀔳"
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class ThumbnailFontIconView: ThumbnailTitleView {
    static var paragraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        // clip the top of the box since we know these symbols are always disks
        paragraphStyle.lineHeightMultiple = 0.85
        return paragraphStyle
    }()
    var initialAttributedString: NSMutableAttributedString!
    var baseSymbol: Symbols!
    var offsetSymbol: Symbols!

    convenience init(symbol: Symbols, tooltip: String? = nil, size: CGFloat = Appearance.fontHeight, color: NSColor = Appearance.fontColor,
                     tenSymbol: Symbols? = Symbols.circledNumber10) {
        // This helps SF symbols display vertically centered and not clipped at the top
        self.init(font: NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!)
        initialAttributedString = NSMutableAttributedString(string: symbol.rawValue, attributes: [.paragraphStyle: ThumbnailFontIconView.paragraphStyle])
        attributedStringValue = initialAttributedString
        textColor = color
        toolTip = tooltip
        addOrUpdateConstraint(widthAnchor, cell!.cellSize.width)
        baseSymbol = symbol
        offsetSymbol = tenSymbol
    }

    // number should be in the interval [0-50]
    func setNumber(_ number: Int) {
        let (baseCharacter, offset) = baseCharacterAndOffset(number)
        replaceCharIfNeeded(String(UnicodeScalar(Int(baseCharacter.unicodeScalars.first!.value) + offset)!))
    }

    func setStar() {
        replaceCharIfNeeded(Symbols.circledStar.rawValue)
    }

    func setFilledStar() {
        replaceCharIfNeeded(Symbols.filledCircledStar.rawValue)
    }

    private func replaceCharIfNeeded(_ newChar: String) {
        if newChar != attributedStringValue.string {
            initialAttributedString.replaceCharacters(in: NSRange(location: 0, length: 1), with: newChar)
            attributedStringValue = initialAttributedString
        }
    }

    private func baseCharacterAndOffset(_ number: Int) -> (String, Int) {
        if number <= 9 {
            // numbers alternate between empty and full circles; we skip the full circles
            return (baseSymbol.rawValue, number * 2)
        } else {
            return (offsetSymbol.rawValue, number - 10)
        }
    }
}

class ThumbnailFilledFontIconView: NSView {
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, backgroundColor: NSColor, size: CGFloat) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = ThumbnailFontIconView(symbol: .filledCircled, size: size - 3, color: backgroundColor)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        backgroundView.centerXAnchor.constraint(equalTo: thumbnailFontIconView.centerXAnchor).isActive = true
        let offset = ((thumbnailFontIconView.cell!.cellSize.width - backgroundView.cell!.cellSize.width) / 2).rounded()
        backgroundView.topAnchor.constraint(equalTo: thumbnailFontIconView.topAnchor, constant: offset).isActive = true
        widthAnchor.constraint(equalTo: thumbnailFontIconView.widthAnchor).isActive = true
        heightAnchor.constraint(equalTo: thumbnailFontIconView.heightAnchor).isActive = true
    }
}
