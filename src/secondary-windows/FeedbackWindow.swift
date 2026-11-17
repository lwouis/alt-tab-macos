import Cocoa
import UniformTypeIdentifiers

class FeedbackWindow: NSWindow {
    static var shared: FeedbackWindow?
    private let report = NSTextView()
    override var canBecomeKey: Bool { SecondaryWindows.canBecomeKey }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        applySecondaryWindowChrome("Local diagnostics")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        report.isEditable = false
        report.isSelectable = true
        report.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        scroll.documentView = report
        let save = NSButton(title: "Save locally…", target: self, action: #selector(sendCallback))
        let stack = NSStackView(views: [scroll, save])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setContentSize(NSSize(width: 640, height: 440))
        Self.shared = self
        reset()
    }

    func reset() {
        report.string = DebugProfile.make()
    }

    @objc private func selectBug() { reset() }
    @objc private func selectEnhancement() { reset() }

    @objc private func sendCallback() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "AltTab-local-diagnostics.txt"
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.report.string.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).beginSheetModal(for: self)
            }
        }
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}
