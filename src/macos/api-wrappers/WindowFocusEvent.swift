import CoreGraphics

/// CGSEventRecord layout used to make a window key through SLPSPostEventRecordTo.
/// The callback consumes the buffer synchronously; both edges use the same window and coordinates.
enum WindowFocusEvent {
    /// The declared record is 0xf8 bytes. WindowServer on macOS 14.7.4+ can read past that length,
    /// so the trailing bytes stay allocated and zeroed (karinushka/paneru#123).
    static let bufferSize = 0x100
    private static let offContentPoint = CGPoint(x: 300_000, y: 300_000)

    static func post(windowId: CGWindowID, send: (UnsafeMutablePointer<UInt8>) -> Void) {
        var windowId = windowId
        var point = offContentPoint
        var bytes = [UInt8](repeating: 0, count: bufferSize)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        memcpy(&bytes[0x10], &point, MemoryLayout<CGPoint>.size)
        memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
        memcpy(&bytes[0x3C], &windowId, MemoryLayout<CGWindowID>.size)
        bytes.withUnsafeMutableBufferPointer { buffer in
            let pointer = buffer.baseAddress!
            pointer[0x08] = 0x01
            send(pointer)
            pointer[0x08] = 0x02
            send(pointer)
        }
    }
}
