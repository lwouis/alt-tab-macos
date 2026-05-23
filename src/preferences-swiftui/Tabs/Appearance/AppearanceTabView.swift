import SwiftUI

@available(macOS 13.0, *)
struct AppearanceTabView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var proTracker: ProStateTracker
    private let proGatedStyleIndices: Set<Int> = [1, 2]

    private static let navigateToUpgrade = Notification.Name(
        "NavigateToUpgradeTab"
    )

    private func notifyProLocked() {
        NotificationCenter.default.post(
            name: Self.navigateToUpgrade,
            object: nil
        )
    }

    var body: some View {
        SwiftUI.ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 主要外观设置
                GroupBox {
                    VStack(spacing: 0) {
                        styleRow
                        RowDivider()
                        sizeRow
                        RowDivider()
                        themeRow
                        RowDivider()
                        afterReleaseRow
                        RowDivider()
                        previewWindowRow
                    }
                    .padding(.top, 4)
                } label: {
                    SectionLabel(title: "Appearance")
                }

                // 自定义选项 - 使用已有字符串组合
                GroupBox {
                    VStack(spacing: 0) {
                        hideStatusIconsRow
                        RowDivider()
                        hideSpaceNumberLabelsRow
                        RowDivider()
                        hideColoredCirclesRow
                        RowDivider()
                        showTitlesRow
                        RowDivider()
                        titleTruncationRow
                    }
                    .padding(.top, 4)
                } label: {
                    SectionLabel(title: "Window Style")
                }

                // 动画
                GroupBox {
                    animationsContent
                } label: {
                    SectionLabel(title: "Animations")
                }

                // 多屏幕设置
                GroupBox {
                    multipleScreensContent
                } label: {
                    SectionLabel(title: "Multiple screens")
                }
            }
            .padding(30)
        }
        .frame(minWidth: SwiftUISettingsWindow.contentWidth)
    }

    // MARK: - Rows

    private var styleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ImageRadioGroup(
                selection: store.proGatedBinding(
                    ProGatedPreferences.appearanceStyle
                ),
                entries: [
                    (
                        .thumbnails,
                        AppearanceStylePreference.thumbnails.localizedString,
                        "thumbnails"
                    ),
                    (
                        .appIcons,
                        AppearanceStylePreference.appIcons.localizedString,
                        "app_icons"
                    ),
                    (
                        .titles,
                        AppearanceStylePreference.titles.localizedString,
                        "titles"
                    ),
                ],
                proGatedIndices: proGatedStyleIndices,
                onProLockedTap: notifyProLocked
            )

            OverrideIndicatorButton(
                overrideIndices: store.overrideIndices(
                    for: "appearanceStyleOverride",
                    globalKey: "appearanceStyle"
                ),
                action: {}
            )
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
    }

    private var sizeRow: some View {
        LabeledRow(NSLocalizedString("Size", comment: "")) {
            HStack(spacing: 4) {
                SegmentedPicker(
                    options: AppearanceSizePreference.allCases.map { pref in
                        SegmentOption(
                            value: pref,
                            icon: pref.symbol.rawValue,
                            title: pref.localizedString,
                            width: 120
                        )
                    },
                    selection: store.proGatedBinding(
                        ProGatedPreferences.appearanceSize
                    ),
                    proSegmentIndex: 3,
                    onProLockedTap: notifyProLocked
                )
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(
                        for: "appearanceSizeOverride",
                        globalKey: "appearanceSize"
                    ),
                    action: {}
                )
            }
        }
    }

    private var themeRow: some View {
        LabeledRow(NSLocalizedString("Theme", comment: "")) {
            HStack(spacing: 4) {
                SegmentedPicker(
                    options: AppearanceThemePreference.allCases.map { pref in
                        SegmentOption(
                            value: pref,
                            icon: pref.symbol.rawValue,
                            title: pref.localizedString,
                            width: 120
                        )
                    },
                    selection: store.macroBinding(
                        for: "appearanceTheme",
                        AppearanceThemePreference.allCases
                    ),
                    proSegmentIndex: nil
                )
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(
                        for: "appearanceThemeOverride",
                        globalKey: "appearanceTheme"
                    ),
                    action: {}
                )
            }
        }
    }

    private var afterReleaseRow: some View {
        LabeledRow(NSLocalizedString("After keys are released", comment: "")) {
            HStack(spacing: 4) {
                SegmentedPicker(
                    options: ShortcutStylePreference.allCases.map { pref in
                        SegmentOption(
                            value: pref,
                            icon: pref.symbol.rawValue,
                            title: pref.localizedString,
                            width: 120
                        )
                    },
                    selection: store.proGatedBinding(
                        ProGatedPreferences.shortcutStyle
                    ),
                    proSegmentIndex: 2,
                    onProLockedTap: notifyProLocked
                )
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(
                        for: "shortcutStyleOverride",
                        globalKey: "shortcutStyle"
                    ),
                    action: {}
                )
            }
        }
    }

    private var previewWindowRow: some View {
        LabeledRow(NSLocalizedString("Preview selected window", comment: "")) {
            HStack(spacing: 8) {
                Toggle("", isOn: store.boolBinding(for: "previewFocusedWindow"))
                    .toggleStyle(.switch)
                OverrideIndicatorButton(
                    overrideIndices: store.overrideIndices(
                        for: "previewFocusedWindowOverride",
                        globalKey: "previewFocusedWindow"
                    ),
                    action: {}
                )
            }
        }
    }

    // MARK: - Customize Options Rows

    private var hideStatusIconsRow: some View {
        LabeledRow(NSLocalizedString("Hide status icons", comment: "")) {
            Toggle("", isOn: store.boolBinding(for: "hideStatusIcons"))
                .toggleStyle(.switch)
        }
    }

    private var hideSpaceNumberLabelsRow: some View {
        LabeledRow(NSLocalizedString("Hide Space number labels", comment: "")) {
            Toggle("", isOn: store.boolBinding(for: "hideSpaceNumberLabels"))
                .toggleStyle(.switch)
        }
    }

    private var hideColoredCirclesRow: some View {
        LabeledRow(
            NSLocalizedString(
                "Hide colored circles on mouse hover",
                comment: ""
            )
        ) {
            Toggle("", isOn: store.boolBinding(for: "hideColoredCircles"))
                .toggleStyle(.switch)
        }
    }

    private var showTitlesRow: some View {
        LabeledRow(NSLocalizedString("Show titles", comment: "")) {
            Picker(
                "",
                selection: store.macroBinding(
                    for: "showTitles",
                    ShowTitlesPreference.allCases
                )
            ) {
                ForEach(ShowTitlesPreference.allCases, id: \.self) {
                    Text($0.localizedString).tag($0)
                }
            }
        }
    }

    private var titleTruncationRow: some View {
        LabeledRow(NSLocalizedString("Title truncation", comment: "")) {
            Picker(
                "",
                selection: store.macroBinding(
                    for: "titleTruncation",
                    TitleTruncationPreference.allCases
                )
            ) {
                ForEach(TitleTruncationPreference.allCases, id: \.self) {
                    Text($0.localizedString).tag($0)
                }
            }
        }
    }

    // MARK: - Section contents

    private var animationsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    NSLocalizedString(
                        "Apparition delay of Switcher",
                        comment: ""
                    )
                )
                Spacer()
                let delayBinding = Binding<Double>(
                    get: {
                        Double(store.intBinding(for: "windowDisplayDelay").wrappedValue)
                    },
                    set: {
                        store.intBinding(for: "windowDisplayDelay").wrappedValue = Int($0)
                    }
                )
                Slider(value: delayBinding, in: 0...900, step: 50)
                    .frame(width: 200)
                Text("\(Int(delayBinding.wrappedValue)) ms").frame(
                    width: 56,
                    alignment: .trailing
                )
                .font(.body.monospacedDigit())
            }
            .padding(.vertical, 6).padding(.horizontal, 12)
            RowDivider()
            LabeledRow(
                NSLocalizedString("Fade out animation of Switcher", comment: "")
            ) {
                Toggle("", isOn: store.boolBinding(for: "fadeOutAnimation"))
                    .toggleStyle(.switch)
            }
            RowDivider()
            LabeledRow(
                NSLocalizedString("Fade in animation of Preview", comment: "")
            ) {
                Toggle(
                    "",
                    isOn: store.boolBinding(for: "previewFadeInAnimation")
                )
                .toggleStyle(.switch)
            }
        }
        .padding(.top, 4)
    }

    private var multipleScreensContent: some View {
        LabeledRow(NSLocalizedString("Show on", comment: "")) {
            Picker(
                "",
                selection: store.macroBinding(
                    for: "showOnScreen",
                    ShowOnScreenPreference.allCases
                )
            ) {
                ForEach(ShowOnScreenPreference.allCases, id: \.self) { pref in
                    Text(pref.localizedString).tag(pref)
                }
            }
        }
    }

}

// MARK: - Shared

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
#Preview("Appearance Tab - Mock Data") {
    // 注册默认值，Preview 环境会自动跳过权限检查和 Keychain 访问
    Preferences.registerDefaults()

    // 设置一些 mock 值用于预览展示
    let mockDefaults: [String: Any] = [
        "appearanceStyle": 1,  // appIcons (Pro 功能)
        "appearanceSize": 3,  // auto (Pro 功能)
        "appearanceTheme": 1,  // dark
        "shortcutStyle": 2,  // searchOnRelease (Pro 功能)
    ]

    mockDefaults.forEach { key, value in
        if let intValue = value as? Int {
            Preferences.set(key, String(intValue))
        }
    }

    return AppearanceTabView()
        .environmentObject(PreferencesStore())
        .environmentObject(ProStateTracker())
}
