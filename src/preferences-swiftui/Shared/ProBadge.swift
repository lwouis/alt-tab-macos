import SwiftUI

/// Pro gradient matching `ProGradient` in AppKit:  #FF4488 → #4488FF → #66CCFF at 36° CCW.
@available(macOS 13.0, *)
let proGradient = LinearGradient(
    colors: [
        Color(red: 0xFF / 255, green: 0x44 / 255, blue: 0x88 / 255),
        Color(red: 0x44 / 255, green: 0x88 / 255, blue: 0xFF / 255),
        Color(red: 0x66 / 255, green: 0xCC / 255, blue: 0xFF / 255),
    ],
    startPoint: UnitPoint(x: 0.095, y: 0.206),
    endPoint: UnitPoint(x: 0.905, y: 0.794)
)

/// Gradient "Pro" badge mirroring `ProBadgeView` in AppKit:
/// gradient text + subtle gradient fill + gradient border.
@available(macOS 13.0, *)
struct ProBadgeLabel: View {
    var body: some View {
        Text(NSLocalizedString("Pro", comment: ""))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(proGradient)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(proGradient.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(proGradient.opacity(0.7), lineWidth: 1)
            )
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
