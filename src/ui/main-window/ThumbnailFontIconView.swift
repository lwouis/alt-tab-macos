import Cocoa

enum Symbols: String {
    case circledPlusSign = "􀁌"
    case circledMinusSign = "􀁎"
    case circledSlashSign = "􀕧"
    case circledNumber0 = "􀀸"
    case circledNumber10 = "􀓵"
    case circledStar = "􀕬"
    case filledCircled = "􀀁"
    case filledCircledMultiplySign = "􀁑"
    case filledCircledMinusSign = "􀁏"
    case filledCircledPlusSign = "􀁍"
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class ThumbnailFontIconView: ThumbnailTitleView {
    convenience init(_ symbol: Symbols, _ size: CGFloat = Preferences.fontIconSize, _ color: NSColor = .white, _ isBackground: Bool = false) {
        // This helps SF symbols display vertically centered and not clipped at the bottom
        if isBackground {
            self.init(size, 3, shadow: nil)
        } else {
            self.init(size, 3)
        }
        string = symbol.rawValue
        font = NSFont(name: "SF Pro Text", size: size)
        textColor = color
        // This helps SF symbols not be clipped on the right
        widthAnchor.constraint(equalToConstant: size * 1.15).isActive = true
    }

    // number should be in the interval [0-50]
    func setNumber(_ number: UInt32) {
        let (baseCharacter, offset) = baseCharacterAndOffset(number)
        assignIfDifferent(&string, String(UnicodeScalar(baseCharacter.unicodeScalars.first!.value + offset)!))
    }

    func setStar() {
        assignIfDifferent(&string, Symbols.circledStar.rawValue)
    }

    private func baseCharacterAndOffset(_ number: UInt32) -> (String, UInt32) {
        if number <= 9 {
            // numbers alternate between empty and full circles; we skip the full circles
            return (Symbols.circledNumber0.rawValue, number * UInt32(2))
        } else {
            return (Symbols.circledNumber10.rawValue, number - 10)
        }
    }
}

class ThumbnailFilledFontIconView: NSView {
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, _ backgroundColor: NSColor) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        var backgroundView = ThumbnailFontIconView(.filledCircled, thumbnailFontIconView.font!.pointSize, backgroundColor, true)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        fit(backgroundView.fittingSize.width, backgroundView.fittingSize.height)
    }
}
