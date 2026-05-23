import SwiftUI

private struct TileHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Image-based radio button group for the appearance style chooser
/// (Thumbnails / App Icons / Titles). Mirrors `ImageTextButtonView` from AppKit.
@available(macOS 13.0, *)
struct ImageRadioGroup<T: Hashable & CaseIterable>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let entries: [(value: T, label: String, imageName: String)]
    let proGatedIndices: Set<Int>
    var onProLockedTap: (() -> Void)?

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
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    guard !(isProGated && proState.isProLocked) else {
                        onProLockedTap?()
                        return
                    }
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
    @State private var tileHeightPreference: CGFloat = 100

    static func loadImage(_ name: String) -> NSImage? {
        let imageName = "\(name)_light"
        if let img = NSImage(named: imageName) { return img }
        guard let path = Bundle.main.path(forResource: "\(imageName)@2x", ofType: "heic") else { return nil }
        let image = NSImage(contentsOfFile: path)
        image?.cacheMode = .never
        return image
    }

    var body: some View {
        GeometryReader { geo in
            let tileWidth = geo.size.width
            let tileHeight = tileWidth / 1.6
            VStack(spacing: 5) {
                ZStack {
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
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 3)
                )

                HStack(spacing: 4) {
                    Text(label)
                        .font(isSelected ? .system(size: 12, weight: .bold) : .system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if showProBadge {
                        ProBadgeLabel()
                    }
                }
                .frame(width: tileWidth)
                .background(
                    GeometryReader { textGeo in
                        Color.clear.preference(key: TileHeightKey.self,
                            value: tileHeight + textGeo.size.height + 5)
                    }
                )
            }
        }
        .onPreferenceChange(TileHeightKey.self) { height in
            tileHeightPreference = height
        }
        .frame(height: tileHeightPreference)
    }
}
