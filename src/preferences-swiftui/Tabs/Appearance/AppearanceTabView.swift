import SwiftUI

@available(macOS 13.0, *)
struct AppearanceTabView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var proTracker: ProStateTracker
    @State private var showCustomizeSheet = false
    @State private var showAnimationsSheet = false
    private let proGatedStyleIndices: Set<Int> = [1, 2]

    var body: some View {
        SwiftUI.ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(spacing: 0) {
                        styleRow.padding(.vertical, 12).padding(.horizontal, 12)
                        RowDivider()
                        sizeRow
                        RowDivider()
                        themeRow
                        RowDivider()
                        afterReleaseRow
                        RowDivider()
                        previewWindowRow
                        RowDivider()
                        SwiftUI.Button(String(format: NSLocalizedString("Customize %@ style…", comment: ""),
                                               ProGatedPreferences.appearanceStyle.read().localizedString)) {
                            showCustomizeSheet = true
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)
                    }
                }

                GroupBox {
                    LabeledRow(NSLocalizedString("Show on", comment: "")) {
                        Picker("", selection: store.macroBinding(for: "showOnScreen", ShowOnScreenPreference.allCases)) {
                            ForEach(ShowOnScreenPreference.allCases, id: \.self) { pref in
                                Text(pref.localizedString).tag(pref)
                            }
                        }
                        .pickerStyle(.menu).frame(width: 200)
                    }
                }
            }
            .padding(30)
        }
        .frame(minWidth: SwiftUISettingsWindow.contentWidth)
        .sheet(isPresented: $showCustomizeSheet) {
            CustomizeStyleSheetView().environmentObject(store).frame(width: 500, height: 450)
        }
        .sheet(isPresented: $showAnimationsSheet) {
            AnimationsSheetView().environmentObject(store).frame(width: 500, height: 250)
        }
    }

    // MARK: - Rows

    private var styleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(NSLocalizedString("Style", comment: ""))
                .frame(width: 200, alignment: .leading)
                .padding(.top, 6)
            ImageRadioGroup(
                selection: store.proGatedBinding(ProGatedPreferences.appearanceStyle),
                entries: [
                    (.thumbnails, AppearanceStylePreference.thumbnails.localizedString, "thumbnails"),
                    (.appIcons, AppearanceStylePreference.appIcons.localizedString, "app_icons"),
                    (.titles, AppearanceStylePreference.titles.localizedString, "titles"),
                ],
                proGatedIndices: proGatedStyleIndices
            )
            Spacer()
            OverrideIndicatorButton(
                overrideIndices: store.overrideIndices(for: "appearanceStyleOverride", globalKey: "appearanceStyle"),
                action: {}
            )
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
    }

    private var sizeRow: some View {
        segmentedRow(NSLocalizedString("Size", comment: ""),
                      gatedDef: ProGatedPreferences.appearanceSize,
                      allCases: AppearanceSizePreference.allCases,
                      overrideBase: "appearanceSizeOverride", globalKey: "appearanceSize")
    }
    private var themeRow: some View {
        segmentedRow(NSLocalizedString("Theme", comment: ""),
                      binding: store.macroBinding(for: "appearanceTheme", AppearanceThemePreference.allCases),
                      allCases: AppearanceThemePreference.allCases,
                      overrideBase: "appearanceThemeOverride", globalKey: "appearanceTheme")
    }
    private var afterReleaseRow: some View {
        segmentedRow(NSLocalizedString("After keys are released", comment: ""),
                      gatedDef: ProGatedPreferences.shortcutStyle,
                      allCases: ShortcutStylePreference.allCases,
                      overrideBase: "shortcutStyleOverride", globalKey: "shortcutStyle")
    }
    private var previewWindowRow: some View {
        LabeledRow(NSLocalizedString("Preview selected window", comment: "")) {
            HStack(spacing: 8) {
                Toggle("", isOn: store.boolBinding(for: "previewFocusedWindow"))
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(for: "previewFocusedWindowOverride", globalKey: "previewFocusedWindow"),
                    action: {}
                )
            }
        }
    }

    // MARK: - Reusable row builders

    private func segmentedRow<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        _ label: String, gatedDef: PreferenceDefinition<T>, allCases: [T],
        overrideBase: String, globalKey: String
    ) -> some View {
        LabeledRow(label) {
            HStack(spacing: 4) {
                Picker("", selection: store.proGatedBinding(gatedDef)) {
                    ForEach(allCases, id: \.self) { Text($0.localizedString).tag($0) }
                }
                .pickerStyle(.segmented)
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(for: overrideBase, globalKey: globalKey),
                    action: {}
                )
            }
        }
    }

    private func segmentedRow<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        _ label: String, binding: Binding<T>, allCases: [T],
        overrideBase: String, globalKey: String
    ) -> some View {
        LabeledRow(label) {
            HStack(spacing: 4) {
                Picker("", selection: binding) {
                    ForEach(allCases, id: \.self) { Text($0.localizedString).tag($0) }
                }
                .pickerStyle(.segmented)
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(for: overrideBase, globalKey: globalKey),
                    action: {}
                )
            }
        }
    }
}

// MARK: - Sheet views

@available(macOS 13.0, *)
struct CustomizeStyleSheetView: View {
    @EnvironmentObject var store: PreferencesStore
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        VStack(spacing: 20) {
            Text("Customize Style").font(.headline)
            GroupBox {
                VStack(spacing: 0) {
                    LabeledRow(NSLocalizedString("Hide status icons", comment: "")) {
                        Toggle("", isOn: store.boolBinding(for: "hideStatusIcons"))
                    }
                    RowDivider()
                    LabeledRow(NSLocalizedString("Hide Space number labels", comment: "")) {
                        Toggle("", isOn: store.boolBinding(for: "hideSpaceNumberLabels"))
                    }
                    RowDivider()
                    LabeledRow(NSLocalizedString("Hide colored circles on mouse hover", comment: "")) {
                        Toggle("", isOn: store.boolBinding(for: "hideColoredCircles"))
                    }
                    RowDivider()
                    LabeledRow(NSLocalizedString("Show titles", comment: "")) {
                        Picker("", selection: store.macroBinding(for: "showTitles", ShowTitlesPreference.allCases)) {
                            ForEach(ShowTitlesPreference.allCases, id: \.self) { Text($0.localizedString).tag($0) }
                        }.pickerStyle(.menu).frame(width: 220)
                    }
                    RowDivider()
                    LabeledRow(NSLocalizedString("Title truncation", comment: "")) {
                        Picker("", selection: store.macroBinding(for: "titleTruncation", TitleTruncationPreference.allCases)) {
                            ForEach(TitleTruncationPreference.allCases, id: \.self) { Text($0.localizedString).tag($0) }
                        }.pickerStyle(.radioGroup)
                    }
                }
            }
            SwiftUI.Button(NSLocalizedString("Done", comment: "")) { presentationMode.wrappedValue.dismiss() }
        }.padding(20)
    }
}

@available(macOS 13.0, *)
struct AnimationsSheetView: View {
    @EnvironmentObject var store: PreferencesStore
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Animations", comment: "")).font(.headline)
            GroupBox {
                VStack(spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("Apparition delay of Switcher", comment: ""))
                        Spacer()
                        let binding = Binding(get: { Double(CachedUserDefaults.int("windowDisplayDelay")) },
                                              set: { Preferences.set("windowDisplayDelay", String(Int($0))) })
                        Slider(value: binding, in: 0...900, step: 50)
                        Text("\(Int(binding.wrappedValue)) ms").frame(width: 56, alignment: .trailing).font(.body.monospacedDigit())
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    RowDivider()
                    LabeledRow(NSLocalizedString("Fade out animation of Switcher", comment: "")) {
                        Toggle("", isOn: store.boolBinding(for: "fadeOutAnimation"))
                    }
                    RowDivider()
                    LabeledRow(NSLocalizedString("Fade in animation of Preview", comment: "")) {
                        Toggle("", isOn: store.boolBinding(for: "previewFadeInAnimation"))
                    }
                }
            }
            SwiftUI.Button(NSLocalizedString("Done", comment: "")) { presentationMode.wrappedValue.dismiss() }
        }.padding(20)
    }
}
