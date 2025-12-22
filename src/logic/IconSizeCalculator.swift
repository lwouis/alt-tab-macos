import Cocoa

/// Utility class to calculate optimal icon sizes based on monitor configuration
/// This helps balance memory usage with visual quality across different display setups
class IconSizeCalculator {
    private static var cachedOptimalSize: CGSize?
    
    /// Calculate optimal icon size across all monitors with 20% buffer for quality
    /// - Parameters:
    ///   - displaySize: The target display size for the icon
    ///   - scaleFactor: The backing scale factor of the current screen
    /// - Returns: Optimal size that works well across all connected monitors
    static func optimalIconSize(for displaySize: NSSize, scaleFactor: CGFloat) -> NSSize {
        if let cached = cachedOptimalSize {
            return cached
        }
        
        // Find maximum scale factor across all screens
        // This ensures icons look sharp even on the highest-resolution display
        let maxScaleFactor = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? scaleFactor
        
        // Calculate size with 20% buffer for quality
        // The buffer prevents pixelation when icons are slightly enlarged
        let bufferMultiplier = CGFloat(1.2)
        let width = displaySize.width * maxScaleFactor * bufferMultiplier
        let height = displaySize.height * maxScaleFactor * bufferMultiplier
        
        let optimalSize = NSSize(width: width, height: height)
        cachedOptimalSize = optimalSize
        return optimalSize
    }
    
    /// Invalidate cache when monitor configuration changes
    /// Should be called when monitors are plugged/unplugged or resolution changes
    static func invalidateCache() {
        cachedOptimalSize = nil
    }
}
