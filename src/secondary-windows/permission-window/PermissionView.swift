import Cocoa

/// One step of the first-run permissions window, drawn as a rounded card. The live step shows its
/// justification and its before/after illustration; a finished or not-yet-reached step collapses to
/// its title row, so the window always has exactly one thing to act on.
/// `PermissionFlow` decides which is which.
class PermissionView: NSView {
    private static let horizontalInset = CGFloat(15)
    private static let liveVerticalInset = CGFloat(13)
    private static let collapsedVerticalInset = CGFloat(11)
    private static let badgeSize = CGFloat(20)
    /// Indent that lines the detail rows up with the title rather than with the badge.
    private static let detailIndent = badgeSize + 9

    private let badge: PermissionStepBadge
    private let title = BoldLabel("")
    private let status = NSTextField(labelWithString: "")
    private let justification = NSTextField(wrappingLabelWithString: "")
    private let illustration: PermissionIllustrationView
    /// "Grant permission" next to "Skipped", for a user who changes their mind. Hidden otherwise.
    private let grantAfterSkip: NSButton
    private let trailingRow: NSStackView
    private var collapsedHeightConstraint: NSLayoutConstraint!
    private var expandedHeightConstraint: NSLayoutConstraint!
    private var state = PermissionFlow.StepState.upcoming

    init(_ stepNumber: Int, _ title: String, _ justification: String, _ illustration: PermissionIllustrationView.Kind, onGrantAfterSkip: @escaping () -> Void = {}) {
        badge = PermissionStepBadge(stepNumber)
        self.illustration = PermissionIllustrationView(illustration)
        grantAfterSkip = Button(NSLocalizedString("Grant permission", comment: "Permissions window button")) { _ in onGrantAfterSkip() }
        trailingRow = NSStackView(views: [status, grantAfterSkip])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer!.cornerRadius = 10
        self.title.stringValue = title
        self.title.font = .systemFont(ofSize: 13, weight: .semibold)
        self.justification.stringValue = justification
        self.justification.font = .systemFont(ofSize: 12)
        self.justification.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11.5, weight: .medium)
        grantAfterSkip.isBordered = false
        grantAfterSkip.attributedTitle = NSAttributedString(string: grantAfterSkip.title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: 11.5),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        grantAfterSkip.isHidden = true
        trailingRow.spacing = 10
        trailingRow.alignment = .centerY
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupConstraints() {
        [badge, title, trailingRow, justification, illustration].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        let inset = Self.horizontalInset
        collapsedHeightConstraint = bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: Self.collapsedVerticalInset)
        expandedHeightConstraint = bottomAnchor.constraint(equalTo: illustration.bottomAnchor, constant: Self.liveVerticalInset)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: Self.liveVerticalInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + Self.detailIndent),
            title.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            trailingRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            trailingRow.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            trailingRow.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            justification.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            justification.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            justification.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 6),
            illustration.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            illustration.topAnchor.constraint(equalTo: justification.bottomAnchor, constant: 11),
        ])
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func update(_ state: PermissionFlow.StepState, _ permissionStatus: PermissionStatus, offersGrantAfterSkip: Bool) {
        self.state = state
        grantAfterSkip.isHidden = !offersGrantAfterSkip
        badge.update(state)
        let isLive = state == .live
        [justification, illustration].forEach { $0.isHidden = !isLive }
        // Deactivate before activating: for a moment both would be active, which AppKit reports as a conflict
        NSLayoutConstraint.deactivate([isLive ? collapsedHeightConstraint : expandedHeightConstraint])
        NSLayoutConstraint.activate([isLive ? expandedHeightConstraint : collapsedHeightConstraint])
        title.textColor = state == .upcoming ? .tertiaryLabelColor : .labelColor
        updateStatusLabel(state, permissionStatus)
        needsDisplay = true
    }

    private func updateStatusLabel(_ state: PermissionFlow.StepState, _ permissionStatus: PermissionStatus) {
        switch state {
            case .live:
                status.stringValue = ""
            case .upcoming:
                status.stringValue = NSLocalizedString("Next", comment: "Permissions window: a step the user hasn't reached yet")
                status.textColor = .tertiaryLabelColor
            case .done:
                let skipped = permissionStatus == .skipped
                status.stringValue = skipped
                    ? NSLocalizedString("Skipped", comment: "")
                    : NSLocalizedString("Allowed", comment: "")
                status.textColor = skipped ? .systemOrange : .systemGreen
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        withDrawingAppearance {
            let isLive = state == .live
            layer!.backgroundColor = (isLive ? NSColor.controlBackgroundColor : NSColor.underPageBackgroundColor).cgColor
            layer!.borderWidth = isLive ? 1.5 : 1
            layer!.borderColor = (isLive ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }
}

/// The circle at the head of a step: the step number while it is pending, a checkmark once done.
private class PermissionStepBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private let stepNumber: Int
    private var state = PermissionFlow.StepState.upcoming

    init(_ stepNumber: Int) {
        self.stepNumber = stepNumber
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer!.cornerRadius = 10
        label.stringValue = String(stepNumber)
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 20),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func update(_ state: PermissionFlow.StepState) {
        self.state = state
        label.stringValue = state == .done ? "✓" : String(stepNumber)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        withDrawingAppearance {
            switch state {
                case .done: layer!.backgroundColor = NSColor.systemGreen.cgColor
                case .live: layer!.backgroundColor = NSColor.controlAccentColor.cgColor
                case .upcoming: layer!.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            }
        }
    }
}
