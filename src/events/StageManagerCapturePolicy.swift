import CoreGraphics

struct StageManagerCaptureMode: Equatable {
    private(set) var enabled = false
    private(set) var generation: UInt64 = 0

    mutating func update(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        generation &+= 1
    }
}

enum StageManagerCapturePolicy {
    static func allowsPublication(_ capturedMode: StageManagerCaptureMode, _ currentMode: StageManagerCaptureMode,
                                  capturedFocus: UInt64, currentFocus: UInt64, isFocused: Bool) -> Bool {
        capturedMode == currentMode && (!currentMode.enabled || (capturedFocus == currentFocus && isFocused))
    }

    static func hasNormalGeometry(_ bounds: CGRect?, _ size: CGSize) -> Bool {
        guard let bounds,
              bounds.width.isFinite, bounds.height.isFinite, size.width.isFinite, size.height.isFinite,
              bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return false }
        return bounds.width >= size.width * 0.9 && bounds.height >= size.height * 0.9
    }

}
