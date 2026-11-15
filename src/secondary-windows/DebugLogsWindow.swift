import Cocoa

class DebugLogsWindow: NSPanel {
    static var shared: DebugLogsWindow?
    override var canBecomeKey: Bool { SecondaryWindows.canBecomeKey }
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var copyLogsButton: NSButton!
    private var copyFeedbackTimer: Timer?
    private var filterControl: NSSegmentedControl!
    private var selectedMinLevel: LogLevel = .debug
    private var isAutoScrolling = true
    private var isPerformingAutoScroll = false
    private var entries = [(LogLevel, String)]()
    private var captureStartedAt = Date()
    private var isListening = false
    private var windowAdmissionCheckbox: NSButton!
    private var filterWindowAdmission = false
    private static let logFont = NSFont.userFixedPitchFont(ofSize: 11)!
    private static let levels: [LogLevel] = [.debug, .info, .warning, .error]
    private static let defaultAttrs: [NSAttributedString.Key: Any] = [.font: logFont, .foregroundColor: NSColor.labelColor]
    private static let levelWords: [LogLevel: String] = [.debug: "DEBG", .info: "INFO", .warning: "WARN", .error: "ERRO"]

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
                  styleMask: [.titled, .utilityWindow, .closable, .miniaturizable, .resizable],
                  backing: .buffered, defer: false)
        setupWindow()
        setupView()
        // Keep the persisted frame key stable to preserve the user's window placement.
        setFrameAutosaveNameSafely("DebugWindow")
        Self.shared = self
    }

    private func setupWindow() {
        applySecondaryWindowChrome(NSLocalizedString("Debug Logs", comment: ""), hiddenTitlebar: false)
        minSize = NSSize(width: 400, height: 300)
    }

    private static func colorForLevel(_ level: LogLevel) -> NSColor {
        switch level {
            case .debug: return NSColor(calibratedRed: 0.0, green: 0.7, blue: 0.0, alpha: 1.0)
            case .info: return NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.85, alpha: 1.0)
            case .warning: return NSColor(calibratedRed: 0.82, green: 0.62, blue: 0.0, alpha: 1.0)
            case .error: return NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.3, alpha: 1.0)
        }
    }

    private static func colorDot(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private func setupView() {
        let filterLabel = NSTextField(labelWithString: "Log Level:")
        filterLabel.translatesAutoresizingMaskIntoConstraints = false
        filterControl = NSSegmentedControl(labels: ["Debug", "Info", "Warning", "Error"],
                                           trackingMode: .selectOne, target: nil, action: nil)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.selectedSegment = 0
        filterControl.onAction = { [weak self] _ in self?.filterChanged() }
        for i in 0..<Self.levels.count {
            filterControl.setImage(Self.colorDot(Self.colorForLevel(Self.levels[i])), forSegment: i)
            filterControl.setImageScaling(.scaleProportionallyDown, forSegment: i)
        }
        windowAdmissionCheckbox = NSButton(checkboxWithTitle: "Accepted/Rejected windows", target: nil, action: nil)
        windowAdmissionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        windowAdmissionCheckbox.onAction = { [weak self] _ in self?.windowAdmissionFilterChanged() }
        let filterRow = NSStackView(views: [filterLabel, filterControl, windowAdmissionCheckbox])
        filterRow.translatesAutoresizingMaskIntoConstraints = false
        filterRow.orientation = .horizontal
        filterRow.spacing = 8
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = Self.logFont
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        copyLogsButton = NSButton(title: "Copy all", target: nil, action: nil)
        copyLogsButton.translatesAutoresizingMaskIntoConstraints = false
        copyLogsButton.bezelStyle = .rounded
        copyLogsButton.controlSize = .small
        copyLogsButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        copyLogsButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyLogsButton.imagePosition = .imageLeading
        copyLogsButton.onAction = { [weak self] _ in self?.copyAllLogs() }
        let clearLogsButton = NSButton(title: "Clear logs", target: nil, action: nil)
        clearLogsButton.translatesAutoresizingMaskIntoConstraints = false
        clearLogsButton.bezelStyle = .rounded
        clearLogsButton.controlSize = .small
        clearLogsButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        clearLogsButton.onAction = { [weak self] _ in self?.clearLogs() }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(filterRow)
        container.addSubview(scrollView)
        container.addSubview(copyLogsButton)
        container.addSubview(clearLogsButton)
        contentView = container
        let padding: CGFloat = 12
        NSLayoutConstraint.activate([
            filterRow.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            filterRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            scrollView.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            copyLogsButton.centerYAnchor.constraint(equalTo: filterRow.centerYAnchor),
            clearLogsButton.centerYAnchor.constraint(equalTo: filterRow.centerYAnchor),
            clearLogsButton.leadingAnchor.constraint(greaterThanOrEqualTo: filterRow.trailingAnchor, constant: 16),
            copyLogsButton.leadingAnchor.constraint(equalTo: clearLogsButton.trailingAnchor, constant: 24),
            copyLogsButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
        ])
    }

    private func startListening() {
        guard !isListening else { return }
        captureStartedAt = Date()
        Logger.setTap { [weak self] level, message, emittedAt in
            DispatchQueue.main.async { self?.appendEntry(level, message, emittedAt) }
        }
        // Capture every level, including tab-detection decisions, regardless of the CLI log level.
        Logger.minLevel = .debug
        isListening = true
    }

    private func stopListening() {
        guard isListening else { return }
        Logger.setTap(nil)
        Logger.minLevel = Logger.decideLevel()
        isListening = false
    }

    private func filterChanged() {
        selectedMinLevel = Self.levels[filterControl.selectedSegment]
        rebuildText()
    }

    private func windowAdmissionFilterChanged() {
        filterWindowAdmission = windowAdmissionCheckbox.state == .on
        rebuildText()
    }

    private func shouldShowEntry(_ level: LogLevel, _ message: String) -> Bool {
        level.rawValue >= selectedMinLevel.rawValue &&
            (!filterWindowAdmission || message.contains("surface accepted") || message.contains("surface not admitted"))
    }

    private func attributedLine(_ text: String, _ level: LogLevel) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: Self.defaultAttrs)
        guard let word = Self.levelWords[level],
              let range = text.range(of: word) else { return result }
        result.addAttribute(.foregroundColor, value: Self.colorForLevel(level),
                            range: NSRange(range, in: text))
        return result
    }

    private func rebuildText() {
        let filtered = entries.filter { shouldShowEntry($0.0, $0.1) }
        let result = NSMutableAttributedString()
        for (i, entry) in filtered.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "\n", attributes: Self.defaultAttrs)) }
            result.append(attributedLine(entry.1, entry.0))
        }
        textView.textStorage?.setAttributedString(result)
        textView.needsDisplay = true
        if isAutoScrolling {
            scrollToBottom()
        }
    }

    private func appendEntry(_ level: LogLevel, _ message: String, _ emittedAt: Date) {
        // Formatting and delivery are asynchronous; clearing must also discard pending older entries.
        guard isListening, emittedAt >= captureStartedAt else { return }
        entries.append((level, message))
        guard shouldShowEntry(level, message) else { return }
        let prefix = textView.string.isEmpty ? "" : "\n"
        textView.textStorage?.append(attributedLine(prefix + message, level))
        if isAutoScrolling {
            scrollToBottom()
        }
    }

    private func copyAllLogs() {
        // copy the full unfiltered buffer, so a shared log isn't missing lines hidden by the level filter
        let text = entries.map { $0.1 }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyLogsButton.title = "Copied!"
        copyLogsButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        copyFeedbackTimer?.invalidate()
        copyFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.copyLogsButton.title = "Copy all"
            self.copyLogsButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        }
    }

    private func clearLogs() {
        captureStartedAt = Date()
        entries.removeAll()
        textView.textStorage?.setAttributedString(NSAttributedString())
        scrollView.contentView.setBoundsOrigin(.zero)
        isAutoScrolling = true
        resetCopyFeedback()
    }

    private func resetCopyFeedback() {
        copyFeedbackTimer?.invalidate()
        copyFeedbackTimer = nil
        copyLogsButton.title = "Copy all"
        copyLogsButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
    }

    private func scrollToBottom() {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        guard let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let maxY = documentView.frame.height - clipView.bounds.height
        guard maxY > 0 else { return }
        isPerformingAutoScroll = true
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: maxY))
        isPerformingAutoScroll = false
    }

    // periphery:ignore:parameters notification - NotificationCenter selector signature
    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard !isPerformingAutoScroll,
              let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let contentHeight = documentView.frame.height
        let scrollOffset = clipView.bounds.origin.y + clipView.bounds.height
        isAutoScrolling = scrollOffset >= contentHeight - 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        startListening()
        super.makeKeyAndOrderFront(sender)
    }

    override func close() {
        stopListening()
        clearLogs()
        selectedMinLevel = .debug
        filterControl.selectedSegment = 0
        filterWindowAdmission = false
        windowAdmissionCheckbox.state = .off
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}
