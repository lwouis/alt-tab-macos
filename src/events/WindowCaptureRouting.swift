enum WindowCaptureBackend: Equatable {
    case screenCaptureKit
    case windowServer
}

enum WindowCaptureKind: Equatable {
    case thumbnail
    case focusedPreview
}

enum WindowCaptureRouting {
    static func backend(macOSMajorVersion: Int, kind: WindowCaptureKind,
                        hasTrustedGrantHistory: Bool, switcherIsActive: Bool,
                        backgroundCaptureIsEnabled: Bool) -> WindowCaptureBackend? {
        guard switcherIsActive || (kind == .thumbnail && backgroundCaptureIsEnabled) else { return nil }
        if kind == .focusedPreview {
            return macOSMajorVersion >= 26 ? .screenCaptureKit : .windowServer
        }
        if macOSMajorVersion >= 27 && hasTrustedGrantHistory {
            return .windowServer
        }
        return macOSMajorVersion >= 26 ? .screenCaptureKit : .windowServer
    }
}

enum WindowServerCaptureFallback {
    static func capture<Image>(primary: () -> Image?, fallback: () -> Image?) -> Image? {
        primary() ?? fallback()
    }
}
