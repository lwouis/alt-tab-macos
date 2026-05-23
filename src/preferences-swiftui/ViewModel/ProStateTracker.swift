import Cocoa
/// Wraps `LicenseManager.shared` state as a `@Published` ObservableObject for SwiftUI,
/// listening to `ProTransitionManager.proLockStateDidChangeNotification` to stay current
/// while the Settings window is open.
@available(macOS 13.0, *)
final class ProStateTracker: ObservableObject {
    @Published var licenseState: LicenseState = .trialExpired
    @Published var isProLocked: Bool = true
    @Published var customerEmail: String? = nil
    @Published var isLifetimeVariant: Bool = false

    private var proLockObserver: NSObjectProtocol?

    /// 检测是否运行在 SwiftUI Preview 环境中
    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// DEBUG 构建自动解锁 Pro 方便开发测试
    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    init() {
        // SwiftUI Preview / DEBUG 环境下使用 mock 数据，方便开发测试
        if Self.isRunningInPreview || Self.isDebugBuild {
            self.licenseState = .pro
            self.isProLocked = false
            self.customerEmail = "preview@example.com"
            self.isLifetimeVariant = true
        } else {
            // Defer keychain access off the main thread so window init doesn't block
            DispatchQueue.global().async {
                let state = LicenseManager.shared.state
                let isLocked = LicenseManager.shared.isProLocked
                let email = LicenseManager.shared.customerEmail
                let lifetime = LicenseManager.shared.isLifetimeVariant
                DispatchQueue.main.async {
                    self.licenseState = state
                    self.isProLocked = isLocked
                    self.customerEmail = email
                    self.isLifetimeVariant = lifetime
                }
            }
        }
        // Always listen for Pro state changes so views update after activation/deactivation
        proLockObserver = NotificationCenter.default.addObserver(
            forName: ProTransitionManager.proLockStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer = proLockObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        // Avoid keychain access on the main thread
        DispatchQueue.global().async {
            LicenseManager.shared.refreshState()
            let state = LicenseManager.shared.state
            let isLocked = LicenseManager.shared.isProLocked
            let email = LicenseManager.shared.customerEmail
            let lifetime = LicenseManager.shared.isLifetimeVariant
            DispatchQueue.main.async {
                self.licenseState = state
                self.isProLocked = isLocked
                self.customerEmail = email
                self.isLifetimeVariant = lifetime
            }
        }
    }

    /// Used by Pro-gated controls: if locked and user taps a Pro value, bounce to Upgrade.
    func ensureNotLocked(or onLocked: @escaping () -> Void) -> Bool {
        guard isProLocked else { return true }
        onLocked()
        return false
    }
}
