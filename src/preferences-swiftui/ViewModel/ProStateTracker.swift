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

    init() {
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
