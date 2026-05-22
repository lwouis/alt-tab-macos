import SwiftUI
/// Gradient "Pro" badge that mirrors the existing `ProBadgeView` in AppKit.
/// Renders as a small pill with "PRO" text on a gradient background.
@available(macOS 13.0, *)
struct ProBadgeLabel: View {
    var body: some View {
        Text("Pro")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Non-hit-testing overlay that positions a Pro badge on the trailing-top corner of a view.
/// Use as `.overlay(alignment: .topTrailing) { ProBadgeOverlay() }`
@available(macOS 13.0, *)
struct ProBadgeOverlay: View {
    var body: some View {
        ProBadgeLabel()
            .padding(4)
            .allowsHitTesting(false)
    }
}

/// Attaches a Pro badge to the trailing segment of a Picker with `.segmented` style.
/// Since SwiftUI doesn't expose per-segment frames, the badge is positioned manually
/// as an overlay on the entire control, aligned to the top-trailing portion of the
/// last segment.
@available(macOS 13.0, *)
struct SegmentedProBadgeModifier: ViewModifier {
    let proSegmentIndex: Int
    let segmentCount: Int

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width / CGFloat(segmentCount)
            let badgeX = segmentWidth * CGFloat(proSegmentIndex + 1) - segmentWidth * 0.3
            content
                .overlay(alignment: .topLeading) {
                    ProBadgeLabel()
                        .allowsHitTesting(false)
                        .offset(x: badgeX, y: -6)
                }
        }
    }
}

@available(macOS 13.0, *)
extension View {
    func proBadgeOnSegment(at index: Int, of total: Int) -> some View {
        modifier(SegmentedProBadgeModifier(proSegmentIndex: index, segmentCount: total))
    }
}
