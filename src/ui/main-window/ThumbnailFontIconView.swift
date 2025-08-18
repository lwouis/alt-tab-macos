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
class ThumbnailFontIconView: ThumbnailTitleView {
    static var paragraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        // clip the top of the box since we know these symbols are always disks
        paragraphStyle.lineHeightMultiple = 0.85
        return paragraphStyle
    }()
    var initialAttributedString: NSMutableAttributedString!

    convenience init(symbol: Symbols, tooltip: String? = nil, size: CGFloat = Appearance.fontHeight,
                     color: NSColor = Appearance.fontColor,
                     shadow: NSShadow? = ThumbnailView.makeShadow(Appearance.indicatedIconShadowColor)) {
        // This helps SF symbols display vertically centered and not clipped at the top
        self.init(shadow: shadow, font: NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!)
        initialAttributedString = NSMutableAttributedString(string: symbol.rawValue, attributes: [.paragraphStyle: ThumbnailFontIconView.paragraphStyle])
        attributedStringValue = initialAttributedString
        textColor = color
        toolTip = tooltip
        addOrUpdateConstraint(widthAnchor, cell!.cellSize.width)
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
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, backgroundColor: NSColor, size: CGFloat) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = ThumbnailFontIconView(symbol: .filledCircled, size: size - 4, color: backgroundColor, shadow: nil)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        backgroundView.centerXAnchor.constraint(equalTo: thumbnailFontIconView.centerXAnchor).isActive = true
        let offset = ((thumbnailFontIconView.cell!.cellSize.width - backgroundView.cell!.cellSize.width) / 2).rounded()
        backgroundView.topAnchor.constraint(equalTo: thumbnailFontIconView.topAnchor, constant: offset).isActive = true
        widthAnchor.constraint(equalTo: thumbnailFontIconView.widthAnchor).isActive = true
        heightAnchor.constraint(equalTo: thumbnailFontIconView.heightAnchor).isActive = true
    }
}

class DisplayNumberIconView: NSView {
    private let backgroundView = NSView()
    private let numberLabel = NSTextField()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        
        // Setup background with darker blue color
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 0.9).cgColor // Darker blue
        backgroundView.layer?.cornerRadius = 8 // Larger corner radius for bigger circle
        addSubview(backgroundView)
        
        // Setup label
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.isEditable = false
        numberLabel.isBordered = false
        numberLabel.isBezeled = false
        numberLabel.drawsBackground = false
        numberLabel.isSelectable = false
        numberLabel.textColor = NSColor.white
        numberLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium) // Larger font
        numberLabel.alignment = .center
        numberLabel.stringValue = "1"
        addSubview(numberLabel)
        
        // Constraints for larger circle (24x24 instead of 16x16)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            numberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            numberLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            numberLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            
            widthAnchor.constraint(equalToConstant: 24), // Larger width
            heightAnchor.constraint(equalToConstant: 24) // Larger height
        ])
    }
    
    func setDisplayNumber(_ number: Int) {
        numberLabel.stringValue = "\(number)"
    }
}
