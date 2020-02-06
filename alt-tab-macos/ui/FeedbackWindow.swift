import Cocoa
import Foundation

class FeedbackWindow: NSWindow, NSTextViewDelegate {
    var body: TextArea!
    var email: TextArea!
    var sendButton: NSButton!

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, styleMask: style, backing: backingStoreType, defer: flag)
        setupWindow()
        setupView()
    }

    func show() {
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    private func setupWindow() {
        title = "Send feedback"
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
    }

    private func setupView() {
        let appIcon = NSImageView(image: App.shared.applicationIconImage)
        appIcon.fit(80, 80)
        let appText = NSStackView(views: [
            BoldLabel("Share improvement ideas, or report bugs"),
            HyperlinkLabel("View existing discussions", App.repository + "/issues"),
        ])
        appText.orientation = .vertical
        appText.alignment = .left
        appText.spacing = GridView.interPadding / 2
        let header = NSStackView(views: [appIcon, appText])
        header.spacing = GridView.interPadding
        sendButton = NSButton(title: "Send", target: nil, action: #selector(sendCallback))
        sendButton.keyEquivalent = "\r"
        sendButton.isEnabled = false
        let buttons = NSStackView(views: [
            NSButton(title: "Cancel", target: nil, action: #selector(cancelCallback)),
            sendButton,
        ])
        buttons.spacing = GridView.interPadding
        body = TextArea(80, 20, "I think the app could be improved with…")
        body.delegate = self
        email = TextArea(80, 1.1, "Optional: email (if you want a reply)")
        let view = GridView.make([
            [header],
            [body],
            [email],
            [buttons],
        ])
        view.cell(atColumnIndex: 0, rowIndex: 3).xPlacement = .trailing
        view.fit()
        setContentSize(view.fittingSize)
        contentView = view
    }

    func textDidChange(_ notification: Notification) {
        sendButton.isEnabled = !body.string.isEmpty
    }

    @objc
    private func cancelCallback(senderControl: NSControl) {
        close()
    }

    @objc
    private func sendCallback(senderControl: NSControl) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/lwouis/alt-tab-macos/issues")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // access token of the alt-tab-macos-bot github account, with scope repo > public_repo
        request.addValue("token 6ab65e11bb51e47835fe1f64970b1d7df0341653", forHTTPHeaderField: "Authorization")
        let preamble = "_This issue was opened by a bot after a user submitted feedback through the in-app form. Here is what they wrote:_\n\n> "
        let emailNote = !email.string.isEmpty ? "\n\nAuthor's email: " + email.string : ""
        let parameters: [String: Any] = [
            "title": "[In-app feedback]",
            "body": preamble + body.string.replacingOccurrences(of: "\n", with: "\n> ") + emailNote
        ]
        request.httpBody = try! JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if error != nil || response == nil || (response as! HTTPURLResponse).statusCode != 201 {
                debugPrint("HTTP call failed:", response, error)
            }
        }).resume()
        close()
    }
}
