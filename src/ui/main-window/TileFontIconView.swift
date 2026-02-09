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
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class TileFontIconView: TileTitleView {
    static var paragraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        // clip the top of the box since we know these symbols are always disks
        paragraphStyle.lineHeightMultiple = 0.85
        return paragraphStyle
    }()
    var initialAttributedString: NSMutableAttributedString!

    convenience init(symbol: Symbols, tooltip: String? = nil, size: CGFloat = Appearance.fontHeight, color: NSColor = Appearance.fontColor) {
        // This helps SF symbols display vertically centered and not clipped at the top
        self.init(font: NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!)
        initialAttributedString = NSMutableAttributedString(string: symbol.rawValue, attributes: [.paragraphStyle: TileFontIconView.paragraphStyle])
        attributedStringValue = initialAttributedString
        textColor = color
        toolTip = tooltip
        frame.size = cell!.cellSize
    }

    // number should be in the interval [0-50]
    func setNumber(_ number: Int, _ filled: Bool) {
        let (baseCharacter, offset) = baseCharacterAndOffset(number, filled)
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

    private func baseCharacterAndOffset(_ number: Int, _ filled: Bool) -> (String, Int) {
        if number <= 9 {
            // numbers alternate between empty and full circles; we skip the full circles
            return ((filled ? Symbols.filledCircledNumber0 : Symbols.circledNumber0).rawValue, number * 2)
        } else {
            return ((filled ? Symbols.filledCircledNumber10 : Symbols.circledNumber10).rawValue, number - 10)
        }
    }
}

class ThumbnailFilledFontIconView: NSView {
    convenience init(_ thumbnailFontIconView: TileFontIconView, backgroundColor: NSColor, size: CGFloat) {
        self.init(frame: .zero)
        let backgroundView = TileFontIconView(symbol: .filledCircled, size: size - 3, color: backgroundColor)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        let fgSize = thumbnailFontIconView.frame.size
        let bgSize = backgroundView.frame.size
        let offset = ((fgSize.width - bgSize.width) / 2).rounded()
        thumbnailFontIconView.frame.origin = .zero
        backgroundView.frame.origin = NSPoint(x: (fgSize.width - bgSize.width) / 2, y: offset)
        frame.size = fgSize
    }
}
