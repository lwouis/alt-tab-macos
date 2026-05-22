import SwiftUI
/// Image-based radio button group for the appearance style chooser
/// (Thumbnails / App Icons / Titles). Mirrors `ImageTextButtonView` from AppKit.
@available(macOS 13.0, *)
struct ImageRadioGroup<T: Hashable & CaseIterable>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let entries: [(value: T, label: String, imageName: String)]
    let proGatedIndices: Set<Int>

    @EnvironmentObject var proState: ProStateTracker

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let isSelected = entry.value == selection
                let isProGated = proGatedIndices.contains(index)
                StyleTile(
                    imageName: entry.imageName,
                    label: entry.label,
                    isSelected: isSelected,
                    showProBadge: isProGated && proState.isProLocked
                )
                .onTapGesture {
                    guard !(isProGated && proState.isProLocked) else { return }
                    selection = entry.value
                }
            }
        }
    }
}

@available(macOS 13.0, *)
private struct StyleTile: View {
    let imageName: String
    let label: String
    let isSelected: Bool
    let showProBadge: Bool

    private let tileWidth: CGFloat = 150
    private let tileHeight: CGFloat = 150 / 1.6

    /// Load illustration from bundle, matching the original `loadIllustration` pattern.
    /// Tries `NSImage(named:)` first (asset catalog / bundled resources), then falls back
    /// to loading directly from the bundle path.
    static func loadImage(_ name: String) -> NSImage? {
        if let img = NSImage(named: name) { return img }
        guard let path = Bundle.main.path(forResource: "\(name)@2x", ofType: "heic") else { return nil }
        let image = NSImage(contentsOfFile: path)
        image?.cacheMode = .never
        return image
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                if let nsImage = Self.loadImage(imageName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: tileWidth, height: tileHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.quaternaryLabelColor))
                        .frame(width: tileWidth, height: tileHeight)
                        .overlay(Text(label).foregroundColor(.secondary))
                }

                if showProBadge {
                    ProBadgeLabel()
                        .padding(2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 3)
            )

            Text(label)
                .font(isSelected ? .system(size: 12, weight: .bold) : .system(size: 12))
                .foregroundColor(.primary)
        }
    }
}
