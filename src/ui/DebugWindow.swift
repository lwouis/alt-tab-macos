import Cocoa
import SwiftyBeaver

class DebugWindow: NSPanel {
    static var shared: DebugWindow?
    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var filterControl: NSSegmentedControl!
    private var selectedMinLevel: SwiftyBeaver.Level = .debug
    private var isAutoScrolling = true
    private var isPerformingAutoScroll = false
    private var entries = [(SwiftyBeaver.Level, String)]()
    private var destination: DebugWindowDestination?
    private var inspectButton: NSButton!
    private var inspectColumns: NSStackView!
    private var inspectAppField: NSTextField!
    private var inspectCgField: NSTextField!
    private var inspectAxField: NSTextField!
    private var inspectTimer: Timer?
    private var inspectClickMonitor: Any?
    private var isInspecting = false
    private static let logFont = NSFont.userFixedPitchFont(ofSize: 11)!
    private static let levels: [SwiftyBeaver.Level] = [.debug, .info, .warning, .error]
    private static let defaultAttrs: [NSAttributedString.Key: Any] = [.font: logFont, .foregroundColor: NSColor.labelColor]
    private static let levelWords: [SwiftyBeaver.Level: String] = [.debug: "DEBG", .info: "INFO", .warning: "WARN", .error: "ERRO"]

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
                  styleMask: [.titled, .utilityWindow, .closable, .miniaturizable, .resizable],
                  backing: .buffered, defer: false)
        setupWindow()
        setupView()
        setFrameAutosaveName("DebugWindow")
        Self.shared = self
    }

    private func setupWindow() {
        title = NSLocalizedString("Debug tools", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 400, height: 300)
    }

    private static func colorForLevel(_ level: SwiftyBeaver.Level) -> NSColor {
        switch level {
            case .debug: return NSColor(calibratedRed: 0.0, green: 0.7, blue: 0.0, alpha: 1.0)
            case .info: return NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.85, alpha: 1.0)
            case .warning: return NSColor(calibratedRed: 0.82, green: 0.62, blue: 0.0, alpha: 1.0)
            case .error: return NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.3, alpha: 1.0)
            default: return .textColor
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
        // Inspect section
        inspectButton = NSButton(title: "Inspect window", target: nil, action: nil)
        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        inspectButton.bezelStyle = .rounded
        inspectButton.onAction = { [weak self] _ in self?.toggleInspect() }
        inspectAppField = Self.makeInspectColumn("App", ["Name", "BundleID", "PID"])
        inspectCgField = Self.makeInspectColumn("Window (CG API)", ["Title", "WID", "Level (kCGWindowLayer)", "Level (CGSGetWindowLevel)", "Size", "Position", "Alpha", "IsOnScreen"])
        inspectAxField = Self.makeInspectColumn("Window (AX API)", ["Title", "Role", "Subrole", "Minimized", "Fullscreen", "Size", "Position"])
        inspectColumns = NSStackView(views: [inspectAppField, inspectCgField, inspectAxField])
        inspectColumns.translatesAutoresizingMaskIntoConstraints = false
        inspectColumns.orientation = .horizontal
        inspectColumns.alignment = .top
        inspectColumns.spacing = 16
        inspectColumns.distribution = .fillEqually
        // Log header and filter
        let filterLabel = NSTextField(labelWithString: "Log Level:")
        filterLabel.translatesAutoresizingMaskIntoConstraints = false
        filterControl = NSSegmentedControl(labels: ["Debug", "Info", "Warning", "Error"],
                                           trackingMode: .selectOne, target: nil, action: nil)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        LabelAndControl.applySystemSelectedSegmentStyle(filterControl)
        filterControl.selectedSegment = 0
        filterControl.onAction = { [weak self] _ in self?.filterChanged() }
        for i in 0..<Self.levels.count {
            filterControl.setImage(Self.colorDot(Self.colorForLevel(Self.levels[i])), forSegment: i)
            filterControl.setImageScaling(.scaleProportionallyDown, forSegment: i)
        }
        let filterRow = NSStackView(views: [filterLabel, filterControl])
        filterRow.translatesAutoresizingMaskIntoConstraints = false
        filterRow.orientation = .horizontal
        filterRow.spacing = 8
        // Log scroll view
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
        // Inspect group box
        let inspectBox = NSBox()
        inspectBox.translatesAutoresizingMaskIntoConstraints = false
        inspectBox.title = "Inspect"
        inspectBox.contentView = NSView()
        inspectBox.contentView!.addSubview(inspectButton)
        inspectBox.contentView!.addSubview(inspectColumns)
        NSLayoutConstraint.activate([
            inspectButton.topAnchor.constraint(equalTo: inspectBox.contentView!.topAnchor, constant: 4),
            inspectButton.leadingAnchor.constraint(equalTo: inspectBox.contentView!.leadingAnchor, constant: 4),
            inspectColumns.topAnchor.constraint(equalTo: inspectButton.bottomAnchor, constant: 8),
            inspectColumns.leadingAnchor.constraint(equalTo: inspectBox.contentView!.leadingAnchor, constant: 4),
            inspectColumns.trailingAnchor.constraint(equalTo: inspectBox.contentView!.trailingAnchor, constant: -4),
            inspectColumns.bottomAnchor.constraint(equalTo: inspectBox.contentView!.bottomAnchor, constant: -4),
        ])
        // Log group box
        let logBox = NSBox()
        logBox.translatesAutoresizingMaskIntoConstraints = false
        logBox.title = "Logs"
        logBox.contentView = NSView()
        logBox.contentView!.addSubview(filterRow)
        logBox.contentView!.addSubview(scrollView)
        NSLayoutConstraint.activate([
            filterRow.topAnchor.constraint(equalTo: filterRow.superview!.topAnchor, constant: 8),
            filterRow.leadingAnchor.constraint(equalTo: logBox.contentView!.leadingAnchor, constant: 4),
            scrollView.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: logBox.contentView!.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: logBox.contentView!.trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: logBox.contentView!.bottomAnchor, constant: -4),
        ])
        // Main container
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectBox)
        container.addSubview(logBox)
        contentView = container
        let padding: CGFloat = 12
        NSLayoutConstraint.activate([
            inspectBox.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            inspectBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            inspectBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            logBox.topAnchor.constraint(equalTo: inspectBox.bottomAnchor, constant: padding),
            logBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            logBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            logBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])
    }

    private func startListening() {
        guard destination == nil else { return }
        let dest = DebugWindowDestination()
        dest.onNewEntry = { [weak self] level, message in
            self?.appendEntry(level, message)
        }
        Logger.addDestination(dest)
        destination = dest
    }

    private func stopListening() {
        guard let dest = destination else { return }
        Logger.removeDestination(dest)
        destination = nil
    }

    private func filterChanged() {
        selectedMinLevel = Self.levels[filterControl.selectedSegment]
        rebuildText()
    }

    private func attributedLine(_ text: String, _ level: SwiftyBeaver.Level) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: Self.defaultAttrs)
        guard let word = Self.levelWords[level],
              let range = text.range(of: word) else { return result }
        result.addAttribute(.foregroundColor, value: Self.colorForLevel(level),
                            range: NSRange(range, in: text))
        return result
    }

    private func rebuildText() {
        let filtered = entries.filter { $0.0.rawValue >= selectedMinLevel.rawValue }
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

    private func appendEntry(_ level: SwiftyBeaver.Level, _ message: String) {
        entries.append((level, message))
        guard level.rawValue >= selectedMinLevel.rawValue else { return }
        let prefix = textView.string.isEmpty ? "" : "\n"
        textView.textStorage?.append(attributedLine(prefix + message, level))
        if isAutoScrolling {
            scrollToBottom()
        }
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
        stopInspecting()
        stopListening()
        clearInspectData()
        entries.removeAll()
        textView.textStorage?.setAttributedString(NSAttributedString())
        selectedMinLevel = .debug
        filterControl.selectedSegment = 0
        isAutoScrolling = true
        hideAppIfLastWindowIsClosed()
        super.close()
    }

    private func toggleInspect() {
        if isInspecting { stopInspecting() } else { startInspecting() }
    }

    private func startInspecting() {
        isInspecting = true
        inspectButton.title = "Stop inspecting"
        inspectTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateInspectData()
        }
        inspectClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.stopInspecting()
        }
    }

    private func stopInspecting() {
        guard isInspecting else { return }
        isInspecting = false
        inspectButton.title = "Inspect window"
        inspectTimer?.invalidate()
        inspectTimer = nil
        if let monitor = inspectClickMonitor {
            NSEvent.removeMonitor(monitor)
            inspectClickMonitor = nil
        }
    }

    private func updateInspectData() {
        let mouseLocation = NSEvent.mouseLocation
        guard let mainScreen = NSScreen.screens.first else { return }
        let cgMousePoint = CGPoint(x: mouseLocation.x, y: mainScreen.frame.height - mouseLocation.y)
        let myWid = CGWindowID(windowNumber)
        guard let found = CGWindow.windows(.optionOnScreenOnly).first(where: { win in
            guard let wid = win.id(), wid != myWid,
                  let bounds = win.bounds() else { return false }
            return CGRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
                .contains(cgMousePoint)
        }) else {
            clearInspectData()
            return
        }
        let wid = (found[kCGWindowNumber] as? Int).map { CGWindowID($0) }
        let pid = found.ownerPID()
        // App column
        var appName = "-"
        var appBundleId = "-"
        let pidStr = pid.map { String($0) } ?? "-"
        if let pid {
            let app = NSRunningApplication(processIdentifier: pid)
            appName = app?.localizedName ?? "-"
            appBundleId = app?.bundleIdentifier ?? "-"
        }
        inspectAppField.stringValue = Self.formatColumn("App", [
            ("Name", appName), ("BundleID", appBundleId), ("PID", pidStr),
        ])
        // CG column
        let cgTitle = found.title() ?? "-"
        let widStr = wid.map { "\($0)" } ?? "-"
        let cgLayer = found.layer().map { "\($0)" } ?? "-"
        let cgsLevel = wid.map { "\($0.level())" } ?? "-"
        let bounds = found.bounds()
        let cgSize = bounds.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"
        let cgPos = bounds.map { "\(Int($0.origin.x)),\(Int($0.origin.y))" } ?? "-"
        let alpha = (found[kCGWindowAlpha] as? Double).map { "\($0)" } ?? "-"
        let isOnScreen = (found[kCGWindowIsOnscreen] as? Bool).map { "\($0)" } ?? "-"
        inspectCgField.stringValue = Self.formatColumn("Window (CG API)", [
            ("Title", cgTitle), ("WID", widStr),
            ("Level (kCGWindowLayer)", cgLayer), ("Level (CGSGetWindowLevel)", cgsLevel),
            ("Size", cgSize), ("Position", cgPos), ("Alpha", alpha), ("IsOnScreen", isOnScreen),
        ])
        // AX column
        var axTitle = "-"
        var axRole = "-"
        var axSubrole = "-"
        var axMinimized = "-"
        var axFullscreen = "-"
        var axSize = "-"
        var axPosition = "-"
        if let pid, let wid {
            let axApp = AXUIElementCreateApplication(pid)
            if let axWindows = try? axApp.attributes([kAXWindowsAttribute]).windows {
                for axWin in axWindows {
                    if let axWid = try? axWin.cgWindowId(), axWid == wid {
                        let attrs = try? axWin.attributes([kAXTitleAttribute, kAXRoleAttribute, kAXSubroleAttribute,
                                                           kAXMinimizedAttribute, kAXFullscreenAttribute,
                                                           kAXSizeAttribute, kAXPositionAttribute])
                        axTitle = attrs?.title ?? "-"
                        axRole = attrs?.role ?? "-"
                        axSubrole = attrs?.subrole ?? "-"
                        axMinimized = attrs?.isMinimized.map { "\($0)" } ?? "-"
                        axFullscreen = attrs?.isFullscreen.map { "\($0)" } ?? "-"
                        if let s = attrs?.size { axSize = "\(Int(s.width))x\(Int(s.height))" }
                        if let p = attrs?.position { axPosition = "\(Int(p.x)),\(Int(p.y))" }
                        break
                    }
                }
            }
        }
        inspectAxField.stringValue = Self.formatColumn("Window (AX API)", [
            ("Title", axTitle), ("Role", axRole), ("Subrole", axSubrole),
            ("Minimized", axMinimized), ("Fullscreen", axFullscreen),
            ("Size", axSize), ("Position", axPosition),
        ])
    }

    private func clearInspectData() {
        inspectAppField.stringValue = Self.formatColumn("App", [("Name", "-"), ("BundleID", "-"), ("PID", "-")])
        inspectCgField.stringValue = Self.formatColumn("Window (CG API)", [
            ("Title", "-"), ("WID", "-"), ("Level (kCGWindowLayer)", "-"), ("Level (CGSGetWindowLevel)", "-"),
            ("Size", "-"), ("Position", "-"), ("Alpha", "-"), ("IsOnScreen", "-"),
        ])
        inspectAxField.stringValue = Self.formatColumn("Window (AX API)", [
            ("Title", "-"), ("Role", "-"), ("Subrole", "-"), ("Minimized", "-"), ("Fullscreen", "-"), ("Size", "-"), ("Position", "-"),
        ])
    }

    private static func makeInspectColumn(_ title: String, _ labels: [String]) -> NSTextField {
        let field = NSTextField(labelWithString: formatColumn(title, labels.map { ($0, "-") }))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = logFont
        field.isSelectable = true
        field.maximumNumberOfLines = 0
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private static func formatColumn(_ title: String, _ rows: [(String, String)]) -> String {
        return "\(title)\n" + rows.map { "• \($0.0): \($0.1)" }.joined(separator: "\n")
    }
}
