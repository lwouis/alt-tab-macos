import Foundation

enum WindowCaptureMethod {
    case screenCaptureKit
    case privateApi
}

enum WindowCaptureMethodResolver {
    static func method(osMajorVersion: Int, stageManagerEnabled: Bool) -> WindowCaptureMethod {
        // ScreenCaptureKit can capture Stage Manager strip previews instead of the full window.
        if stageManagerEnabled { return .privateApi }
        // Mitigate macOS 15 bugs with ScreenCaptureKit (see https://github.com/lwouis/alt-tab-macos/issues/5190).
        if osMajorVersion == 15 { return .privateApi }
        if osMajorVersion >= 14 { return .screenCaptureKit }
        return .privateApi
    }
}

enum StageManager {
    private static let defaultsDomain = "com.apple.WindowManager"
    private static let globallyEnabledKey = "GloballyEnabled"

    static var isEnabled: Bool {
        isEnabled(defaults: UserDefaults(suiteName: defaultsDomain))
    }

    static func isEnabled(defaults: UserDefaults?) -> Bool {
        defaults?.bool(forKey: globallyEnabledKey) ?? false
    }
}
