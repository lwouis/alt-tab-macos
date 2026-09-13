import Foundation

class AppearanceTestable {
    static func fittedTitlesWidth(measured: CGFloat, limit: CGFloat, minimum: CGFloat = 300) -> CGFloat {
        min(max(0, limit), max(max(0, minimum), measured.rounded(.up)))
    }

    static func stableTitlesWidth(measured: CGFloat, limit: CGFloat, previous: CGFloat?, tolerance: CGFloat, minimum: CGFloat = 300) -> CGFloat {
        let required = fittedTitlesWidth(measured: measured, limit: limit, minimum: minimum)
        let slack = max(0, tolerance)
        if let previous, previous <= limit, previous >= required, previous - required <= slack * 2 {
            return previous
        }
        return min(max(0, limit), required + slack)
    }

    static func appNameColumnWidth(measured: CGFloat, previous: CGFloat, rowWidth: CGFloat) -> CGFloat {
        min(240, max(0, rowWidth * 0.25), max(previous, measured))
    }

    static func relativeLuminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    static func needsIconSeparation(_ samples: [Double], background: [Double]) -> Bool {
        guard !samples.isEmpty else { return false }
        let backgroundLuminance = relativeLuminance(background)
        let lowContrast = samples.filter { (max($0, backgroundLuminance) + 0.05) / (min($0, backgroundLuminance) + 0.05) < 1.5 }
        return Double(lowContrast.count) / Double(samples.count) >= 0.6
    }

    // First opaque pixels from each side follow the artwork silhouette rather than transparent padding.
    static func iconEdgeLuminances(_ bytes: [UInt8], side: Int) -> [Double] {
        guard side > 0, bytes.count == side * side * 4 else { return [] }
        var offsets = Set<Int>()
        for line in 0..<side {
            for indexes in [(0..<side).map { (line * side + $0) * 4 },
                            (0..<side).map { ($0 * side + line) * 4 }] {
                if let first = indexes.first(where: { bytes[$0 + 3] >= 192 }) { offsets.insert(first) }
                if let last = indexes.last(where: { bytes[$0 + 3] >= 192 }) { offsets.insert(last) }
            }
        }
        return offsets.map { offset in
            let alpha = Double(bytes[offset + 3])
            return relativeLuminance((0..<3).map { min(1, Double(bytes[offset + $0]) / alpha) })
        }
    }

    /// How wide should the TilesPanel be, for comfortable viewing?
    /// * a comfortable field-of-view is 50-60 degrees
    /// * people sit at various distances from the screen. We can't know how far they sit
    /// * most people will seat far enough so that they can view the whole width of the screen
    /// * some people use wide-screen or TV monitors. Those people tend to be too close to the screen, since they need to use keyboard and mouse on their desk
    /// Let's use this heuristic: let's assume that people can view 60cm comfortably. Bigger screens can only show parts of AltTab
    /// Let's clamp at 90% like Windows 11
    /// Let's clamp at 45% (value for the biggest, 60" screens)
    static func comfortableWidth(_ physicalWidth: Double?) -> Double {
        if let physicalWidth {
            return min(0.9, max(0.45, 600.0 / physicalWidth))
        }
        return 0.9
    }

    // calculate windowMinWidthInRow and windowMaxWidthInRow such that:
    // * fullscreen windows fill their tile vertically
    // * narrow windows have enough width that a few words can be read from their title
    static func goodValuesForThumbnailsWidthMinMax(_ aspectRatio: CGFloat, _ rowsCount: CGFloat) -> (CGFloat, CGFloat) {
        let minRatio: CGFloat
        let maxRatio: CGFloat
        if aspectRatio >= 1 {
            minRatio = 0.7 / (aspectRatio * rowsCount)
            maxRatio = 1.5 / (aspectRatio * rowsCount)
        } else {
            minRatio = 1.3 / rowsCount
            maxRatio = 2.1 / rowsCount
        }
        // Make sure the values are clamped between some reasonable bounds
        return (max(0.09, minRatio), min(0.30, maxRatio))
    }
}
