import Cocoa

/// SVG sources compile to shared drawing instructions; runtime images use public native drawing only.
enum LocalizedIllustration {
    private static let images = NSCache<NSString, NSImage>()
    private static let drawers = NSCache<NSString, IllustrationDrawer>()

    static func image(_ name: String, dark: Bool = false, rightToLeft: Bool = false,
                      overrides: [String: String] = [:], bundle: Bundle = .main) -> NSImage? {
        let locale = bundle.preferredLocalizations.first ?? "en"
        let substitutions = overrides.sorted { $0.key < $1.key }.map { [$0.key, $0.value] }
        let encoded = (try? JSONSerialization.data(withJSONObject: substitutions).base64EncodedString()) ?? ""
        let key = "\(bundle.bundleURL.path)|\(name)|\(locale)|\(dark)|\(rightToLeft)|\(encoded)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let drawer = drawer(bundle),
            let image = drawer.image(name, dark: dark, rightToLeft: rightToLeft, localize: { id, english in
                overrides[id] ?? bundle.localizedString(forKey: english, value: english, table: nil)
            }) else { return nil }
        images.countLimit = 48
        images.setObject(image, forKey: key)
        return image
    }

    private static func drawer(_ bundle: Bundle) -> IllustrationDrawer? {
        let key = bundle.bundleURL.path as NSString
        if let cached = drawers.object(forKey: key) { return cached }
        guard let url = bundle.url(forResource: "scenes", withExtension: "plist", subdirectory: "native-illustrations") else { return nil }
        // Bundle replacement during an update can briefly interrupt resource reads.
        for _ in 0..<2 {
            if let drawer = try? IllustrationDrawer(directory: url.deletingLastPathComponent()) {
                drawers.countLimit = 4
                drawers.setObject(drawer, forKey: key)
                return drawer
            }
        }
        return nil
    }
}

final class LocalizedIllustrationView: NSImageView {
    var artwork: String { didSet { refreshImage() } }
    private let overrides: [String: String]

    init(_ artwork: String, overrides: [String: String] = [:]) {
        self.artwork = artwork
        self.overrides = overrides
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityElement(false)
        refreshImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshImage()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshImage()
    }

    private func refreshImage() {
        image = LocalizedIllustration.image(artwork, dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            rightToLeft: userInterfaceLayoutDirection == .rightToLeft, overrides: overrides)
    }
}
