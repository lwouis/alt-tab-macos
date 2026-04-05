import Cocoa

/// Hero usage-stat block used by [C] Day 15 Full Upgrade, [D] Day 15 Proactive, [G] Day 35
/// Final, and the Upgrade tab. Reads `UsageStats.triggerCount` and
/// `UsageStats.usedProFeaturesSessionCount` at init **and on every `refresh()`** call.
///
/// Hosts that keep this view alive across re-shows (singleton windows, the static Upgrade
/// tab) must call `refresh()` whenever the host becomes visible, otherwise the displayed
/// numbers stay frozen at first-render and disagree with sibling surfaces. Popovers that
/// recreate their entire view tree on every `show()` don't need to refresh.
///
/// Rendering logic:
/// - Both counts > 0: two-column hero (switches + Pro feature uses) — bridges the user's
///   total app value to their specific Pro engagement.
/// - Only triggerCount > 0: single-column hero (switches only) — fallback for users who
///   never engaged with Pro features during trial.
/// - Both zero: hero block omitted entirely.
///
/// `supportingLine` is optional; pass nil to omit it. The window's
/// `setContentSize(... fittingSize ...)` call at end of init absorbs the height delta
/// automatically.
class UsageStatHeroView: NSStackView {
    private let supportingLineLabel = NSTextField(wrappingLabelWithString: "")
    private let hasSupportingLine: Bool

    init(supportingLine: String? = nil) {
        hasSupportingLine = supportingLine != nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .centerX
        spacing = 4

        if let supportingLine {
            supportingLineLabel.font = .systemFont(ofSize: 13)
            supportingLineLabel.textColor = .secondaryLabelColor
            supportingLineLabel.alignment = .center
            supportingLineLabel.stringValue = supportingLine
        }

        rebuildStatsBlock()
    }

    /// Re-reads `UsageStats` and re-renders the stat columns in place. Call when the host
    /// becomes visible again so cumulative trigger/Pro-use counts track usage growth. The
    /// host is responsible for re-fitting its content size afterwards if a number's width
    /// could have grown (e.g. "9" → "1.2K").
    func refresh() {
        rebuildStatsBlock()
        needsLayout = true
    }

    var supportingLine: String {
        get { supportingLineLabel.stringValue }
        set { supportingLineLabel.stringValue = newValue }
    }

    private func rebuildStatsBlock() {
        for view in Array(arrangedSubviews) {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let triggerCount = UsageStats.triggerCount
        let proCount = UsageStats.usedProFeaturesSessionCount

        if triggerCount > 0 {
            let leadInFont = NSFont.systemFont(ofSize: 11, weight: .medium)
            let leadInString = NSLocalizedString("YOUR USAGE SO FAR", comment: "")
            let leadInAttr = NSMutableAttributedString(string: leadInString)
            let leadInRange = NSRange(location: 0, length: leadInAttr.length)
            leadInAttr.addAttribute(.kern, value: 0.8, range: leadInRange)
            leadInAttr.addAttribute(.font, value: leadInFont, range: leadInRange)
            leadInAttr.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: leadInRange)
            let leadIn = NSTextField(labelWithAttributedString: leadInAttr)
            leadIn.alignment = .center
            addArrangedSubview(leadIn)
            setCustomSpacing(4, after: leadIn)

            let switchesColumn = Self.makeStatColumn(
                number: UsageStats.formatCount(triggerCount),
                caption: NSLocalizedString("window switches", comment: ""))

            if proCount > 0 {
                let proColumn = Self.makeStatColumn(
                    number: UsageStats.formatCount(proCount),
                    caption: NSLocalizedString("Pro feature uses", comment: ""),
                    useGradient: true)

                let pairRow = NSStackView(views: [switchesColumn, proColumn])
                pairRow.translatesAutoresizingMaskIntoConstraints = false
                pairRow.orientation = .horizontal
                pairRow.alignment = .top
                pairRow.spacing = 32
                pairRow.distribution = .equalSpacing
                addArrangedSubview(pairRow)
                setCustomSpacing(20, after: pairRow)
            } else {
                addArrangedSubview(switchesColumn)
                setCustomSpacing(20, after: switchesColumn)
            }
        }

        if hasSupportingLine {
            addArrangedSubview(supportingLineLabel)
        }
    }

    private static func makeStatColumn(number: String, caption: String, useGradient: Bool = false) -> NSStackView {
        let numberFont = NSFont.systemFont(ofSize: 32, weight: .semibold)
        let numberView: NSView
        if useGradient {
            let imageView = NSImageView()
            imageView.image = ProGradient.makeGradientTextImage(number, font: numberFont)
            imageView.imageScaling = .scaleNone
            imageView.imageAlignment = .alignCenter
            numberView = imageView
        } else {
            let numberLabel = NSTextField(labelWithString: number)
            numberLabel.font = numberFont
            numberLabel.textColor = .labelColor
            numberLabel.alignment = .center
            numberView = numberLabel
        }

        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 12)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center

        let stack = NSStackView(views: [numberView, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        return stack
    }

    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }
}
