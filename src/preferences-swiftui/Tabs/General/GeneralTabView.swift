import SwiftUI

@available(macOS 13.0, *)
struct GeneralTabView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var searchVM: SearchViewModel

    @State private var accessibilityStatus: PermissionStatus = .notGranted
    @State private var screenRecordingStatus: PermissionStatus = .notGranted

    var body: some View {
        SwiftUI.ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 20) {
                    SearchableSection(
                        sectionId: "general-main",
                        searchableText: [
                            NSLocalizedString("Start at login", comment: ""),
                            NSLocalizedString("Menubar icon", comment: ""),
                            NSLocalizedString("Capture windows in the background", comment: ""),
                            NSLocalizedString("Language", comment: ""),
                        ]
                    ) {
                        SectionLabel(title: "General")
                    } content: {
                        VStack(spacing: 0) {
                            startAtLoginRow
                            RowDivider()
                            menubarIconRow
                            RowDivider()
                            captureWindowsRow
                            RowDivider()
                            languageRow
                        }
                        .padding(.top, 4)
                    }

                    SearchableSection(
                        sectionId: "general-permissions",
                        searchableText: [
                            NSLocalizedString("Permissions", comment: ""),
                            NSLocalizedString("Accessibility", comment: ""),
                            NSLocalizedString("Screen Recording", comment: ""),
                        ]
                    ) {
                        SectionLabel(title: "Permissions")
                    } content: {
                        VStack(spacing: 0) {
                            accessibilityPermissionRow
                            RowDivider()
                            screenRecordingPermissionRow
                        }
                        .padding(.top, 4)
                    }

                    SearchableSection(
                        sectionId: "general-updates",
                        searchableText: [
                            NSLocalizedString("Updates policy", comment: ""),
                            NSLocalizedString("Crash reports policy", comment: ""),
                        ]
                    ) {
                        SectionLabel(title: "Updates")
                    } content: {
                        VStack(spacing: 0) {
                            updatesRow
                            RowDivider()
                            crashPolicyRow
                        }
                        .padding(.top, 4)
                    }

                    HStack(spacing: 12) {
                        SwiftUI.Button(
                            NSLocalizedString("Export settings…", comment: ""),
                            action: exportSettings
                        )
                        SwiftUI.Button(
                            NSLocalizedString("Import settings…", comment: ""),
                            action: importSettings
                        )
                        Spacer()
                        SwiftUI.Button(
                            NSLocalizedString("Check for updates now…", comment: "")
                        ) {
                            App.updaterController?.checkForUpdates(nil)
                        }
                        SwiftUI.Button(
                            NSLocalizedString(
                                "Reset settings and restart…",
                                comment: ""
                            ),
                            action: confirmReset
                        )
                    }
                }
                .padding(30)
                .onChange(of: searchVM.firstMatchSectionId) { id in
                    if let id {
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .frame(minWidth: SwiftUISettingsWindow.contentWidth)
        .onAppear { refreshPermissionStatus() }
    }

    // MARK: - General rows

    private var startAtLoginRow: some View {
        LabeledRow(NSLocalizedString("Start at login", comment: "")) {
            Toggle("", isOn: store.boolBinding(for: "startAtLogin"))
                .toggleStyle(.switch)
        }
    }

    private let menubarIconImages: [NSImage] = {
        (0..<3).map { i in
            let image = NSImage(named: "menubar-\(i)")!.copy() as! NSImage
            image.size = NSSize(width: 24, height: 24)
            return image
        }
    }()

    private var menubarIconRow: some View {
        let iconNames = [
            NSLocalizedString("Outlined", comment: ""),
            NSLocalizedString("Filled", comment: ""),
            NSLocalizedString("Colored", comment: ""),
        ]
        return LabeledRow(NSLocalizedString("Menubar icon", comment: "")) {
            HStack(spacing: 8) {
                Picker(
                    "",
                    selection: store.macroBinding(
                        for: "menubarIcon",
                        MenubarIconPreference.allCases
                    )
                ) {
                    ForEach(Array(MenubarIconPreference.allCases.enumerated()), id: \.offset) { item in
                        HStack(spacing: 4) {
                            Image(nsImage: menubarIconImages[item.offset])
                            Text(iconNames[item.offset])
                        }
                        .tag(item.element)
                    }
                }
                Toggle("", isOn: store.boolBinding(for: "menubarIconShown"))
                    .toggleStyle(.switch)
            }
        }
    }

    private var captureWindowsRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledRow(
                NSLocalizedString(
                    "Capture windows in the background",
                    comment: ""
                )
            ) {
                Toggle(
                    "",
                    isOn: store.boolBinding(for: "captureWindowsInBackground")
                )
                .toggleStyle(.switch)
            }
            Text(
                NSLocalizedString(
                    "Needed for protected content (DRM, some videogames). May increase the number of permissions requested from the system.",
                    comment: ""
                )
            )
            .font(.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Language row

    private var languageBinding: Binding<LanguagePreference> {
        Binding(
            get: { CachedUserDefaults.macroPref("language", LanguagePreference.allCases) },
            set: { newValue in
                if newValue == .systemDefault {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([newValue.appleLanguageCode!], forKey: "AppleLanguages")
                }
                Preferences.set("language", newValue.indexAsString)
                store.refreshToken = UUID()
                showLanguageRestartAlert()
            }
        )
    }

    private func showLanguageRestartAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Language Change", comment: "")
        alert.informativeText = NSLocalizedString("The application needs to restart to apply the language change.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            App.restart()
        }
    }

    private var languageRow: some View {
        LabeledRow(NSLocalizedString("Language", comment: "")) {
            Picker("", selection: languageBinding) {
                ForEach(LanguagePreference.allCases, id: \.self) { lang in
                    Text(lang.localizedString).tag(lang)
                }
            }
        }
    }

    // MARK: - Updates rows

    private var updatesRow: some View {
        LabeledRow(NSLocalizedString("Updates policy", comment: "")) {
            Picker(
                "",
                selection: store.macroBinding(
                    for: "updatePolicy",
                    UpdatePolicyPreference.allCases
                )
            ) {
                ForEach(UpdatePolicyPreference.allCases, id: \.self) { p in
                    Text(p.localizedString).tag(p)
                }
            }
        }
    }

    private var crashPolicyRow: some View {
        LabeledRow(NSLocalizedString("Crash reports policy", comment: "")) {
            Picker(
                "",
                selection: store.macroBinding(
                    for: "crashPolicy",
                    CrashPolicyPreference.allCases
                )
            ) {
                ForEach(CrashPolicyPreference.allCases, id: \.self) { p in
                    Text(p.localizedString).tag(p)
                }
            }
        }
    }

    // MARK: - Permissions rows

    private var accessibilityPermissionRow: some View {
        permissionStatusRow(
            label: NSLocalizedString("Accessibility", comment: ""),
            status: accessibilityStatus,
            description: NSLocalizedString(
                "Required to focus windows after you release the shortcut.",
                comment: ""
            ),
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    private var screenRecordingPermissionRow: some View {
        permissionStatusRow(
            label: NSLocalizedString("Screen Recording", comment: ""),
            status: screenRecordingStatus,
            description: NSLocalizedString(
                "Required to show thumbnails and previews of open windows.",
                comment: ""
            ),
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    private func permissionStatusRow(
        label: String,
        status: PermissionStatus,
        description: String,
        settingsURL: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                Text(label)
                Spacer()
                HStack(spacing: 6) {
                    Text(permissionStatusLabel(status))
                        .foregroundColor(permissionStatusColor(status))
                        .fontWeight(.medium)
                    SwiftUI.Button(
                        NSLocalizedString("Open Settings…", comment: "")
                    ) {
                        NSWorkspace.shared.open(URL(string: settingsURL)!)
                    }
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 12)
            Text(description)
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
    }

    private func permissionStatusLabel(_ status: PermissionStatus) -> String {
        switch status {
        case .granted:
            return NSLocalizedString("Allowed", comment: "")
        case .notGranted:
            return NSLocalizedString("Not allowed", comment: "")
        case .skipped:
            return NSLocalizedString("Skipped", comment: "")
        }
    }

    private func permissionStatusColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted:
            return .green
        case .notGranted:
            return .red
        case .skipped:
            return .orange
        }
    }

    private func refreshPermissionStatus() {
        AccessibilityPermission.update()
        accessibilityStatus = AccessibilityPermission.status
        ScreenRecordingPermission.update()
        screenRecordingStatus = ScreenRecordingPermission.status
    }

    // MARK: - Actions

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "AltTab Settings.plist"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dict =
            UserDefaults.standard.persistentDomain(
                forName: App.bundleIdentifier
            ) ?? [:]
        let filtered = dict.filter { Preferences.ownedKeys.contains($0.key) }
        (filtered as NSDictionary).write(to: url, atomically: true)
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return
        }
        for (key, value) in dict where Preferences.ownedKeys.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
        }
        Preferences.invalidateAllCache()
        App.restart()
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "Reset all settings?",
            comment: ""
        )
        alert.informativeText = NSLocalizedString(
            "This will restart AltTab with default settings.",
            comment: ""
        )
        alert.addButton(
            withTitle: NSLocalizedString("Reset and restart", comment: "")
        )
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .critical
        if alert.runModal() == .alertFirstButtonReturn {
            Preferences.resetAll()
            App.restart()
        }
    }
}

// MARK: - Section label

@available(macOS 13.0, *)
private struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.system(size: 15, weight: .semibold))
            .padding(.bottom, 4)
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
#Preview("General Tab") {
    Preferences.registerDefaults()
    return GeneralTabView()
        .environmentObject(PreferencesStore())
        .environmentObject(SearchViewModel())
}
