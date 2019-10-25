import Cocoa

class BaseLabel: NSTextView {
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(_ text: String) {
        super.init(frame: .zero)
        _init()
        heightAnchor.constraint(greaterThanOrEqualToConstant: Preferences.fontHeight! + Preferences.interItemPadding).isActive = true
        string = text
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        _init()
    }

    private func _init() {
        drawsBackground = true
        backgroundColor = .clear
        isSelectable = false
        isEditable = false
        font = Preferences.font
        enabledTextCheckingTypes = 0
    }
}

class CellTitle: BaseLabel {
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        super.init(frame: .zero, textContainer: textContainer)
        textColor = Preferences.fontColor
        shadow = Cell.makeShadow(.darkGray)
        defaultParagraphStyle = makeParagraphStyle()
        heightAnchor.constraint(equalToConstant: Preferences.fontHeight!).isActive = true
    }

    private func makeParagraphStyle() -> NSMutableParagraphStyle {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.maximumLineHeight = Preferences.fontHeight!
        paragraphStyle.minimumLineHeight = Preferences.fontHeight!
        paragraphStyle.allowsDefaultTighteningForTruncation = false
        return paragraphStyle
    }
}
