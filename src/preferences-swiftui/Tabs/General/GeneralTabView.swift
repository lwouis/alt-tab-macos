import SwiftUI

@available(macOS 13.0, *)
struct GeneralTabView: View {
    @EnvironmentObject var store: PreferencesStore

    var body: some View {
        SwiftUI.ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Startup & Menubar
                GroupBox {
                    VStack(spacing: 0) {
                        LabeledRow(NSLocalizedString("Start at login", comment: "")) {
                            Toggle("", isOn: store.boolBinding(for: "startAtLogin"))
                        }
                        RowDivider()
                        menubarIconRow
                        RowDivider()
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(NSLocalizedString("Capture windows in the background", comment: ""),
                                   isOn: store.boolBinding(for: "captureWindowsInBackground"))
                            Text(NSLocalizedString("Needed for protected content (DRM, some videogames). May increase the number of permissions requested from the system.", comment: ""))
                                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)
                    }
                }

                // Language
                GroupBox {
                    LabeledRow(NSLocalizedString("Language", comment: "")) {
                        Picker("", selection: store.macroBinding(for: "language", LanguagePreference.allCases)) {
                            ForEach(LanguagePreference.allCases, id: \.self) { lang in
                                Text(lang.localizedString).tag(lang)
                            }
                        }
                        .pickerStyle(.menu).frame(width: 180)
                    }
                }

                // Updates & Crash
                GroupBox {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledRow(NSLocalizedString("Updates policy", comment: "")) {
                                Picker("", selection: store.macroBinding(for: "updatePolicy", UpdatePolicyPreference.allCases)) {
                                    ForEach(UpdatePolicyPreference.allCases, id: \.self) { p in
                                        Text(p.localizedString).tag(p)
                                    }
                                }
                                .pickerStyle(.menu).frame(width: 180)
                            }
                            SwiftUI.Button(NSLocalizedString("Check for updates now…", comment: "")) {
                                App.updaterController?.checkForUpdates(nil)
                            }
                            .padding(.leading, 12)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)

                        RowDivider()

                        LabeledRow(NSLocalizedString("Crash reports policy", comment: "")) {
                            Picker("", selection: store.macroBinding(for: "crashPolicy", CrashPolicyPreference.allCases)) {
                                ForEach(CrashPolicyPreference.allCases, id: \.self) { p in
                                    Text(p.localizedString).tag(p)
                                }
                            }
                            .pickerStyle(.menu).frame(width: 180)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)
                    }
                }

                // Actions
                HStack(spacing: 12) {
                    SwiftUI.Button(NSLocalizedString("Export settings…", comment: ""), action: exportSettings)
                    SwiftUI.Button(NSLocalizedString("Import settings…", comment: ""), action: importSettings)
                    Spacer()
                    SwiftUI.Button(NSLocalizedString("Reset settings and restart…", comment: ""), action: confirmReset)
                }
            }
            .padding(30)
        }
        .frame(minWidth: SwiftUISettingsWindow.contentWidth)
    }

    // MARK: - Menubar icon

    private var menubarIconRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(NSLocalizedString("Menubar icon", comment: ""))
                .frame(width: 200, alignment: .leading)
            Spacer()
            Picker("", selection: store.macroBinding(for: "menubarIcon", MenubarIconPreference.allCases)) {
                ForEach(MenubarIconPreference.allCases, id: \.self) { icon in
                    Text(icon.localizedString).tag(icon)
                }
            }
            .pickerStyle(.menu).frame(width: 80)
            Toggle("", isOn: store.boolBinding(for: "menubarIconShown"))
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
    }

    // MARK: - Actions

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "AltTab Settings.plist"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dict = UserDefaults.standard.persistentDomain(forName: App.bundleIdentifier) ?? [:]
        let filtered = dict.filter { Preferences.ownedKeys.contains($0.key) }
        (filtered as NSDictionary).write(to: url, atomically: true)
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return }
        for (key, value) in dict where Preferences.ownedKeys.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
        }
        Preferences.invalidateAllCache()
        App.restart()
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Reset all settings?", comment: "")
        alert.informativeText = NSLocalizedString("This will restart AltTab with default settings.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Reset and restart", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .critical
        if alert.runModal() == .alertFirstButtonReturn { Preferences.resetAll(); App.restart() }
    }
}

// MARK: - Shared row components

@available(macOS 13.0, *)
struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) { self.label = label; self.content = content }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
            Spacer()
            content()
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
    }
}

@available(macOS 13.0, *)
struct FullWidthRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .padding(.vertical, 6).padding(.horizontal, 12)
    }
}

@available(macOS 13.0, *)
struct RowDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}
