import Cocoa

final class PermissionIllustrationView: NSView {
    enum Kind { case accessibility, screenRecording }

    init(_ kind: Kind) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let artwork = LocalizedIllustrationView(kind == .accessibility ? "permission-accessibility" : "permission-recording")
        addSubview(artwork)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 378),
            heightAnchor.constraint(equalToConstant: 110),
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: trailingAnchor),
            artwork.topAnchor.constraint(equalTo: topAnchor),
            artwork.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }
}
