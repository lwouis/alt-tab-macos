import Foundation

/// How many tiles `TilesView.recycledViews` must hold. A tile bakes the switcher's appearance (title font,
/// image shadows) in when it is built, and `Appearance` holds placeholder values (a 3pt font, red shadows)
/// until launch applies the real ones right before building the switcher UI. Windows start arriving earlier:
/// the WindowServer tap is installed ahead of the permission gate, which resumes launch asynchronously. So
/// no tile is built before the UI, and the UI's first pool covers every window already known.
enum TilePool {
    static let minimumSize = 20

    static func tilesToAdd(poolSize: Int, windowCount: Int, uiIsBuilt: Bool) -> Int {
        guard uiIsBuilt else { return 0 }
        return max(0, max(minimumSize, windowCount) - poolSize)
    }
}
