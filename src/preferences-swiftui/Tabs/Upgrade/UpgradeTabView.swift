import SwiftUI

// MARK: - Upgrade tab

@available(macOS 13.0, *)
struct UpgradeTabView: View {
    @EnvironmentObject var proTracker: ProStateTracker
    @StateObject private var usageStats = UsageStatsObserver()

    var body: some View {
        SwiftUI.ScrollView {
            VStack(alignment: .center, spacing: 0) {
                headerSection
                    .padding(.bottom, 28)

                if showHero {
                    usageStatsHero
                        .padding(.bottom, 40)

                    heroButton
                        .padding(.bottom, 6)

                    Text(NSLocalizedString("30-day money-back guarantee", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Divider()
                        .frame(width: 220)
                        .padding(.vertical, 28)

                    featuresSection
                        .padding(.bottom, 28)

                    footerLinks
                }

                if !showHero {
                    proManageSection
                }
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        }
    }

    // MARK: - State

    private var showHero: Bool {
        proTracker.licenseState != .pro
    }

    private var statusText: String {
        switch proTracker.licenseState {
        case .trial(let days):
            return String(format: NSLocalizedString("Trial: %d days remaining", comment: ""), days)
        case .trialExpired:
            return NSLocalizedString("Trial expired", comment: "")
        case .proExpired:
            return NSLocalizedString("Your license doesn't cover this version. Upgrade to Lifetime Pro.", comment: "")
        case .pro:
            if proTracker.isLifetimeVariant {
                return String(format: NSLocalizedString("Pro Lifetime license activated for %@", comment: ""),
                              proTracker.customerEmail ?? "")
            }
            return String(format: NSLocalizedString("Pro license activated for %@", comment: ""),
                          proTracker.customerEmail ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AltTab Pro")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    // MARK: - Usage stats

    private var usageStatsHero: some View {
        VStack(spacing: 0) {
            if usageStats.triggerCount > 0 {
                Text(NSLocalizedString("YOUR USAGE SO FAR", comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
                    .padding(.bottom, 4)

                HStack(alignment: .top, spacing: 32) {
                    statColumn(
                        number: UsageStats.formatCount(usageStats.triggerCount),
                        caption: NSLocalizedString("window switches", comment: ""),
                        useGradient: false
                    )
                    if usageStats.proCount > 0 {
                        statColumn(
                            number: UsageStats.formatCount(usageStats.proCount),
                            caption: NSLocalizedString("Pro feature uses", comment: ""),
                            useGradient: true
                        )
                    }
                }
            }
        }
    }

    private func statColumn(number: String, caption: String, useGradient: Bool) -> some View {
        VStack(spacing: 2) {
            if useGradient {
                Text(number)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
            } else {
                Text(number)
                    .font(.system(size: 32, weight: .semibold))
            }
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Hero button

    private var heroButton: some View {
        SwiftUI.Button(action: { ProTransitionManager.openCheckout() }) {
            Text(NSLocalizedString("Get Pro", comment: ""))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 220, height: 40)
        }
        .buttonStyle(.plain)
        .background(Color.blue)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Pro includes:", comment: ""))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            ForEach(proFeatures, id: \.self) { feature in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green)
                    Text(feature)
                        .font(.system(size: 13))
                }
            }
        }
    }

    private let proFeatures = [
        NSLocalizedString("App Icons & Window Titles styles", comment: ""),
        NSLocalizedString("Search windows by typing", comment: ""),
        NSLocalizedString("Auto-sizing switcher", comment: ""),
        NSLocalizedString("Up to 9 keyboard shortcuts", comment: ""),
    ]

    // MARK: - Footer links

    private var footerLinks: some View {
        HStack(spacing: 6) {
            footerLink(NSLocalizedString("I already have a license key", comment: "")) {
                presentActivationSheet()
            }
            Text("·")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            footerLink(NSLocalizedString("I lost my license key", comment: "")) {
                UpgradeTab.openAccountPage()
            }
        }
        .padding(.top, 8)
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        SwiftUI.Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.link)
    }

    // MARK: - Pro manage

    private var proManageSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                SwiftUI.Button(action: { UpgradeTab.openAccountPage() }) {
                    HStack {
                        Text(NSLocalizedString("My Account", comment: ""))
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6).padding(.horizontal, 10)

                Divider().padding(.leading, 10)

                SwiftUI.Button(action: { deactivateLicense() }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Deactivate license on this machine", comment: ""))
                        Text(NSLocalizedString("License will remain valid and usable to activate AltTab on any machine", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6).padding(.horizontal, 10)
            }
        }
    }

    // MARK: - Activation sheet

    private func presentActivationSheet() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Activate your Pro license", comment: "")
        alert.informativeText = NSLocalizedString("Paste your license key:", comment: "")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 370, height: 24))
        field.placeholderString = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        field.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        field.usesSingleLineMode = true
        alert.accessoryView = field

        alert.addButton(withTitle: NSLocalizedString("Activate", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            let key = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            LicenseManager.shared.activate(key) { _ in }
        }
    }

    private func deactivateLicense() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Deactivate license?", comment: "")
        alert.informativeText = NSLocalizedString("You can re-activate on this or another machine later.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Deactivate", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            LicenseManager.shared.deactivate { _ in }
        }
    }
}

// MARK: - Usage stats observer

@available(macOS 13.0, *)
private final class UsageStatsObserver: ObservableObject {
    @Published var triggerCount: Int = 0
    @Published var proCount: Int = 0

    init() {
        refresh()
    }

    func refresh() {
        triggerCount = UsageStats.triggerCount
        proCount = UsageStats.usedProFeaturesSessionCount
    }
}
