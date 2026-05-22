import SwiftUI
// MARK: - Upgrade tab

@available(macOS 13.0, *)
struct UpgradeTabView: View {
    @EnvironmentObject var proTracker: ProStateTracker

    var body: some View {
        SwiftUI.ScrollView {
            VStack(spacing: 0) {
                switch proTracker.licenseState {
                case .pro:
                    proActivatedView
                case .trial, .trialExpired, .proExpired:
                    purchaseView
                }
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        }
    }

    // MARK: - Purchase flow

    private var purchaseView: some View {
        VStack(spacing: 16) {
            // Header
            Text("AltTab Pro")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )

            // Status
            Text(statusLabel)
                .font(.title3)
                .foregroundColor(.secondary)

            // Hero button
            heroButton

            // Guarantee
            Text(NSLocalizedString("30-day money-back guarantee", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            Divider().padding(.vertical, 8)

            // Features
            featuresList

            // Footer links
            VStack(spacing: 8) {
                footerLink(NSLocalizedString("I already have a license key", comment: "")) {
                    presentActivationSheet()
                }
                footerLink(NSLocalizedString("I lost my license key", comment: "")) {
                    UpgradeTab.openAccountPage()
                }
            }
            .padding(.top, 8)
        }
    }

    private var statusLabel: String {
        switch proTracker.licenseState {
        case .trial(let days):
            return String(format: NSLocalizedString("Trial: %d days remaining", comment: ""), days)
        case .trialExpired:
            return NSLocalizedString("Trial expired", comment: "")
        case .proExpired:
            return NSLocalizedString("Your license doesn't cover this version", comment: "")
        default:
            return ""
        }
    }

    private var heroButton: some View {
        SwiftUI.Button(action: { ProTransitionManager.openCheckout() }) {
            Text(NSLocalizedString("Get Pro", comment: ""))
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 220, height: 40)
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Pro includes:", comment: ""))
                .font(.headline)
            ForEach(proFeatures, id: \.self) { feature in
                Label(feature, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
    }

    private let proFeatures = [
        NSLocalizedString("App Icons & Window Titles styles", comment: ""),
        NSLocalizedString("Search windows by typing", comment: ""),
        NSLocalizedString("Auto-sizing switcher", comment: ""),
        NSLocalizedString("Up to 9 keyboard shortcuts", comment: ""),
    ]

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        SwiftUI.Button(action: action) {
            Text(title)
                .font(.caption)
        }
        .buttonStyle(.link)
    }

    // MARK: - Pro activated

    @ViewBuilder
    private var proActivatedView: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("AltTab Pro", comment: ""))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )

            statusLabelView

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
                            Text(NSLocalizedString("License will remain valid for other machines and future updates.", comment: ""))
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
    }

    private var statusLabelView: some View {
        if proTracker.isLifetimeVariant {
            return Text(
                String(format: NSLocalizedString("Pro Lifetime license activated for %@", comment: ""),
                       proTracker.customerEmail ?? ""))
                .foregroundColor(.secondary)
        } else {
            return Text(
                String(format: NSLocalizedString("Pro license activated for %@", comment: ""),
                       proTracker.customerEmail ?? ""))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Activation sheet

    @State private var activationKey: String = ""
    @State private var showActivationSheet = false

    private func presentActivationSheet() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Activate your Pro license", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Activate", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let keyField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        keyField.placeholderString = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        keyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = keyField

        if alert.runModal() == .alertFirstButtonReturn {
            let key = keyField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            LicenseManager.shared.activate(key) { _ in }
        }
    }

    private func deactivateLicense() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Deactivate license?", comment: "")
        alert.informativeText = NSLocalizedString("You can re-activate on this or another machine later.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Deactivate", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            LicenseManager.shared.deactivate { _ in }
        }
    }
}
