import Cocoa
import Foundation

class FeedbackWindow: NSWindow {
    static let token: String = {
        // token is encoded to/from base64 to avoid github noticing it and revoking it
        let base64Token = Bundle.main.object(forInfoDictionaryKey: "FeedbackToken") as! String
        return String(data: Data(base64Encoded: base64Token)!, encoding: .utf8)!
    }()
    var body: TextArea!
    var email: TextArea!
    var sendButton: NSButton!
    var debugProfile: NSButton!
    var canBecomeKey_ = true
    override var canBecomeKey: Bool { canBecomeKey_ }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .miniaturizable, .closable], backing: .buffered, defer: false)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        title = NSLocalizedString("Send feedback", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    private func setupView() {
        let appIcon = NSImageView(image: NSImage.initResizedCopy("app", 80, 80))
        appIcon.imageScaling = .scaleNone
        let appText = StackView([
            BoldLabel(NSLocalizedString("Share improvement ideas, or report bugs", comment: "")),
            HyperlinkLabel(NSLocalizedString("View existing discussions", comment: ""), App.repository + "/issues"),
        ], .vertical)
        appText.spacing = GridView.interPadding / 2
        let header = NSStackView(views: [appIcon, appText])
        header.spacing = GridView.interPadding
        sendButton = NSButton(title: NSLocalizedString("Send", comment: ""), target: nil, action: #selector(sendCallback))
        sendButton.keyEquivalent = "\r"
        sendButton.isEnabled = false
        let buttons = StackView([
            NSButton(title: NSLocalizedString("Cancel", comment: ""), target: nil, action: #selector(cancel)),
            sendButton,
        ])
        buttons.spacing = GridView.interPadding
        body = TextArea(80, 12, NSLocalizedString("I think the app could be improved with…", comment: ""), { () -> Void in
            self.sendButton.isEnabled = !self.body.stringValue.isEmpty
        })
        email = TextArea(80, 1, NSLocalizedString("Optional: email (if you want a reply)", comment: ""))
        debugProfile = NSButton(checkboxWithTitle: NSLocalizedString("Send debug profile (CPU, memory, etc)", comment: ""), target: nil, action: nil)
        debugProfile.state = .on
        let warning = BoldLabel(NSLocalizedString("All data from this form will be made public, as a ticket on github.com", comment: ""))
        let view = GridView([
            [header],
            [body],
            [email],
            [debugProfile],
            [buttons],
            [warning],
        ])
        view.cell(atColumnIndex: 0, rowIndex: 4).xPlacement = .trailing
        view.cell(atColumnIndex: 0, rowIndex: 5).xPlacement = .trailing
        setContentSize(view.fittingSize)
        contentView = view
    }

    // allow to close with the escape key
    @objc func cancel(_ sender: Any?) {
        close()
    }

    @objc private func sendCallback() {
        if email.stringValue.isEmpty && !warnAboutNoEmail() {
            return
        }
        openTicket()
    }

    func openTicket() {
        URLSession.shared.dataTask(with: prepareRequest(), completionHandler: { data, response, error in
            if error != nil || response == nil || (response as! HTTPURLResponse).statusCode != 201 {
                debugPrint("HTTP call failed:", response ?? "nil", error ?? "nil")
            }
        }).resume()
        close()
    }

    func warnAboutNoEmail() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Are you sure you don’t want a response?", comment: "")
        alert.informativeText = NSLocalizedString("You didn’t write your email, thus can’t receive any response.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Send anyway", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        return alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn
    }

    private func prepareRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/lwouis/alt-tab-macos/issues")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // access token of the alt-tab-macos-bot github account, with scope repo > public_repo
        request.addValue("token " + FeedbackWindow.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try! JSONSerialization.data(withJSONObject: [
            "title": "[In-app feedback]",
            "body": assembleBody()
        ])
        return request
    }

    private func assembleBody() -> String {
        var result = ""
        result += "_This issue was opened by a bot after a user submitted feedback through the in-app form._"
        if !email.stringValue.isEmpty {
            result += "\n\n__From:__ " + email.stringValue
        }
        result += "\n\n__Message:__"
        result += "\n\n> " + body.stringValue.replacingOccurrences(of: "\n", with: "\n> ")
        if debugProfile.state == .on {
            result += "\n\n<details>\n<summary><strong>Debug profile</strong></summary>\n<p>"
            result += "\n\n" + DebugProfile.make()
            result += "\n\n" + "</p>\n</details>"
        }
        return result
    }
}
