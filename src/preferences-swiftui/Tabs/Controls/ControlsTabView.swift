import SwiftUI

// MARK: - Controls tab

@available(macOS 13.0, *)
struct ControlsTabView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var proTracker: ProStateTracker

    @State private var selectedIndex: Int = 0
    @State private var selectedSegment: Int = 0
    @State private var showShortcutsSheet = false
    @State private var showAdditionalControlsSheet = false
    @State private var showGestureInfo = false

    private let sidebarWidth: CGFloat = 175
    private var editorWidth: CGFloat {
        SwiftUISettingsWindow.contentWidth - sidebarWidth - 1
    }

    private var shortcutCount: Int { store.shortcutCount }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ShortcutSidebarView(
                    count: store.shortcutCountBinding,
                    selectedIndex: $selectedIndex,
                    maxCount: Preferences.maxShortcutCount,
                    minCount: Preferences.minShortcutCount,
                    isProLocked: proTracker.isProLocked,
                    onProGateViolation: {
                        NotificationCenter.default.post(
                            name: Notification.Name("NavigateToUpgradeTab"),
                            object: nil
                        )
                    }
                )
                .frame(width: sidebarWidth)

                Rectangle().fill(.separator).frame(width: 1)

                // Editor pane
                SwiftUI.ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        editorContent
                    }
                    .frame(width: editorWidth)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                }
            }
            .frame(minHeight: 400)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )

            // Tool buttons
            HStack {
                Spacer()
                SwiftUI.Button(
                    NSLocalizedString("Additional controls…", comment: "")
                ) {
                    showAdditionalControlsSheet = true
                }
                SwiftUI.Button(
                    NSLocalizedString("Shortcuts when active…", comment: "")
                ) {
                    showShortcutsSheet = true
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $showShortcutsSheet) {
            ShortcutsWhenActiveSheetView()
                .environmentObject(store)
                .environmentObject(proTracker)
                .frame(width: 500)
        }
        .sheet(isPresented: $showAdditionalControlsSheet) {
            AdditionalControlsSheetView()
                .environmentObject(store)
                .frame(width: 500)
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if selectedIndex == Preferences.gestureIndex {
            gestureEditor
        } else {
            shortcutEditor(for: selectedIndex)
        }
    }

    // MARK: - Shortcut editor

    @ViewBuilder
    private func shortcutEditor(for index: Int) -> some View {
        let vm = ShortcutViewModel(index: index)

        VStack(alignment: .leading, spacing: 0) {
            // Trigger row
            GroupBox {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("Hold", comment: ""))
                    ShortcutRecorderField(
                        shortcut: store.shortcutBinding(
                            for: vm.holdShortcutKey
                        ),
                        label: NSLocalizedString("Hold", comment: ""),
                        preferenceKey: vm.holdShortcutKey
                    )
                    .frame(height: 22)

                    Text(NSLocalizedString("and press", comment: ""))
                    ShortcutRecorderField(
                        shortcut: store.shortcutBinding(
                            for: vm.nextWindowShortcutKey
                        ),
                        label: NSLocalizedString(
                            "Select next window",
                            comment: ""
                        ),
                        preferenceKey: vm.nextWindowShortcutKey
                    )
                    .frame(height: 22)
                    Text(NSLocalizedString("Select next window", comment: ""))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            } label: {
                Text(NSLocalizedString("Trigger", comment: ""))
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer().frame(height: 10)

            ShortcutTabContentSection(index: index, selectedSegment: $selectedSegment, editorWidth: editorWidth)
        }
    }

    // MARK: - Gesture editor

    private var gestureEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox {
                HStack(spacing: 8) {
                    Picker(
                        "",
                        selection: store.macroBinding(
                            for: "nextWindowGesture",
                            GesturePreference.allCases
                        )
                    ) {
                        ForEach(GesturePreference.allCases, id: \.self) { g in
                            Text(g.localizedString).tag(g)
                        }
                    }

                    SwiftUI.Button(action: { showGestureInfo = true }) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .popover(isPresented: $showGestureInfo) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("You may need to disable some conflicting system gestures", comment: ""))
                                .fixedSize(horizontal: false, vertical: true)
                            SwiftUI.Button(NSLocalizedString("Open Trackpad Settings…", comment: "")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                            }
                        }
                        .padding(12)
                        .frame(width: 280)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            } label: {
                Text(NSLocalizedString("Trigger", comment: ""))
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer().frame(height: 10)

            ShortcutTabContentSection(index: Preferences.gestureIndex, selectedSegment: $selectedSegment, editorWidth: editorWidth)
        }
    }
}

// MARK: - Shared tab content section (Filtering / Appearance / Ordering)

@available(macOS 13.0, *)
struct ShortcutTabContentSection: View {
    let index: Int
    @Binding var selectedSegment: Int
    let editorWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedSegment) {
                Text(NSLocalizedString("Filtering", comment: "")).tag(0)
                Text(NSLocalizedString("Appearance", comment: "")).tag(1)
                Text(NSLocalizedString("Ordering & Grouping", comment: "")).tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: editorWidth - 32)

            Spacer().frame(height: 8)

            Group {
                switch selectedSegment {
                case 0: FilteringSection(index: index)
                case 1: AppearanceOverrideSectionView(index: index)
                case 2: OrderingSectionView(index: index)
                default: EmptyView()
                }
            }
            .frame(minHeight: 300)
        }
    }
}

// MARK: - Shortcut sidebar

@available(macOS 13.0, *)
struct ShortcutSidebarView: View {
    @Binding var count: Int
    @Binding var selectedIndex: Int
    let maxCount: Int
    let minCount: Int
    let isProLocked: Bool
    let onProGateViolation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SwiftUI.ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        shortcutRowView(index: index)
                    }
                    Divider().padding(.horizontal, 10)
                    gestureRowView
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                SwiftUI.Button(action: {
                    guard count < maxCount else { return }
                    if count >= 1 && isProLocked {
                        onProGateViolation()
                        return
                    }
                    count += 1
                }) { Image(systemName: "plus").frame(width: 16, height: 16) }
                .disabled(count >= maxCount)

                SwiftUI.Button(action: {
                    guard count > minCount else { return }
                    count -= 1
                    if selectedIndex >= count
                        && selectedIndex < Preferences.gestureIndex
                    {
                        selectedIndex = count - 1
                    }
                }) { Image(systemName: "minus").frame(width: 16, height: 16) }
                .disabled(count <= minCount)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func shortcutRowView(index: Int) -> some View {
        ShortcutSidebarRowView(index: index, isSelected: selectedIndex == index)
            .contentShape(Rectangle())
            .onTapGesture {
                if isProLocked && index >= 1 {
                    onProGateViolation()
                } else {
                    selectedIndex = index
                }
            }
            .background(
                selectedIndex == index ? Color.accentColor : Color.clear
            )
            .cornerRadius(4)
    }

    private var gestureRowView: some View {
        ShortcutSidebarRowView(
            index: Preferences.gestureIndex,
            isSelected: selectedIndex == Preferences.gestureIndex
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isProLocked {
                onProGateViolation()
            } else {
                selectedIndex = Preferences.gestureIndex
            }
        }
        .background(
            selectedIndex == Preferences.gestureIndex
                ? Color.accentColor : Color.clear
        )
        .cornerRadius(4)
    }
}

@available(macOS 13.0, *)
struct ShortcutSidebarRowView: View {
    @EnvironmentObject var proTracker: ProStateTracker
    let index: Int
    let isSelected: Bool

    private var vm: ShortcutViewModel { ShortcutViewModel(index: index) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(vm.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    if index >= 1 && proTracker.isProLocked {
                        ProBadgeLabel()
                    }
                }
                Text(vm.summary)
                    .font(.system(size: 11))
                    .foregroundColor(
                        isSelected ? .white.opacity(0.7) : .secondary
                    )
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white.opacity(0.5) : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - Filtering section (7 dropdowns)

@available(macOS 13.0, *)
struct FilteringSection: View {
    @EnvironmentObject var store: PreferencesStore
    let index: Int

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                filteringPicker(
                    NSLocalizedString(
                        "Show windows from applications",
                        comment: ""
                    ),
                    baseName: "appsToShow",
                    allCases: AppsToShowPreference.allCases
                )
                Divider().padding(.leading, 10)
                filteringPicker(
                    NSLocalizedString("Show windows from Spaces", comment: ""),
                    baseName: "spacesToShow",
                    allCases: SpacesToShowPreference.allCases
                )
                Divider().padding(.leading, 10)
                filteringPicker(
                    NSLocalizedString("Show windows from screens", comment: ""),
                    baseName: "screensToShow",
                    allCases: ScreensToShowPreference.allCases
                )
                Divider().padding(.leading, 10)
                filteringPicker(
                    NSLocalizedString("Show minimized windows", comment: ""),
                    baseName: "showMinimizedWindows",
                    allCases: ShowHowPreference.allCases
                )
                Divider().padding(.leading, 10)
                filteringPicker(
                    NSLocalizedString("Show hidden windows", comment: ""),
                    baseName: "showHiddenWindows",
                    allCases: ShowHowPreference.allCases
                )
                Divider().padding(.leading, 10)
                filteringPicker(
                    NSLocalizedString("Show fullscreen windows", comment: ""),
                    baseName: "showFullscreenWindows",
                    allCases: ShowHowPreference.allCases.filter {
                        $0 != .showAtTheEnd
                    }
                )
                Divider().padding(.leading, 10)
                filteringPicker(
                    NSLocalizedString(
                        "Show apps with no open window",
                        comment: ""
                    ),
                    baseName: "showWindowlessApps",
                    allCases: ShowHowPreference.allCases
                )
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
    }

    private func filteringPicker<
        T: MacroPreference & CaseIterable & Equatable & Hashable
    >(
        _ label: String,
        baseName: String,
        allCases: [T]
    ) -> some View {
        let key = Preferences.indexToName(baseName, index)
        return HStack {
            Text(label)
            Spacer()
            Picker("", selection: store.macroBinding(for: key, allCases)) {
                ForEach(allCases, id: \.self) { v in
                    Text(v.localizedString).tag(v)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Appearance override section (5 controls)

@available(macOS 13.0, *)
struct AppearanceOverrideSectionView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var proTracker: ProStateTracker
    let index: Int

    private var vm: ShortcutViewModel { ShortcutViewModel(index: index) }

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
        GroupBox {
            VStack(spacing: 0) {
                overrideStyleRow
                Divider().padding(.leading, 10)
                overrideSizeRow
                Divider().padding(.leading, 10)
                overrideThemeRow
                Divider().padding(.leading, 10)
                overrideAfterReleaseRow
                Divider().padding(.leading, 10)
                overridePreviewRow
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
    }

    private var overrideStyleRow: some View {
        let styleKey = Preferences.indexToName("appearanceStyleOverride", index)
        return HStack(alignment: .center, spacing: 12) {
            if vm.hasOverride("appearanceStyleOverride") {
                unlinkButton(baseName: "appearanceStyleOverride")
            }
            ImageRadioGroup(
                selection: store.macroBinding(
                    for: styleKey,
                    AppearanceStylePreference.allCases
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
                proGatedIndices: [1, 2],
                onProLockedTap: notifyProLocked
            )
        }
        .padding(.vertical, 6)
    }

    private var overrideSizeRow: some View {
        let key = Preferences.indexToName("appearanceSizeOverride", index)
        return LabeledRow(NSLocalizedString("Size", comment: "")) {
            HStack(spacing: 4) {
                if vm.hasOverride("appearanceSizeOverride") {
                    unlinkButton(baseName: "appearanceSizeOverride")
                }
                SegmentedPicker(
                    options: AppearanceSizePreference.allCases.map { pref in
                        SegmentOption(
                            value: pref,
                            icon: pref.symbol.rawValue,
                            title: pref.localizedString,
                            width: 100
                        )
                    },
                    selection: store.macroBinding(
                        for: key,
                        AppearanceSizePreference.allCases
                    ),
                    proSegmentIndex: 3,
                    onProLockedTap: notifyProLocked
                )
            }
        }
    }

    private var overrideThemeRow: some View {
        let key = Preferences.indexToName("appearanceThemeOverride", index)
        return LabeledRow(NSLocalizedString("Theme", comment: "")) {
            HStack(spacing: 4) {
                if vm.hasOverride("appearanceThemeOverride") {
                    unlinkButton(baseName: "appearanceThemeOverride")
                }
                SegmentedPicker(
                    options: AppearanceThemePreference.allCases.map { pref in
                        SegmentOption(
                            value: pref,
                            icon: pref.symbol.rawValue,
                            title: pref.localizedString,
                            width: 100
                        )
                    },
                    selection: store.macroBinding(
                        for: key,
                        AppearanceThemePreference.allCases
                    ),
                    proSegmentIndex: nil
                )
            }
        }
    }

    private var overrideAfterReleaseRow: some View {
        let key = Preferences.indexToName("shortcutStyleOverride", index)
        return LabeledRow(
            NSLocalizedString("After keys are released", comment: "")
        ) {
            HStack(spacing: 4) {
                if vm.hasOverride("shortcutStyleOverride") {
                    unlinkButton(baseName: "shortcutStyleOverride")
                }
                SegmentedPicker(
                    options: ShortcutStylePreference.allCases.map { pref in
                        SegmentOption(
                            value: pref,
                            icon: pref.symbol.rawValue,
                            title: pref.localizedString,
                            width: 100
                        )
                    },
                    selection: store.macroBinding(
                        for: key,
                        ShortcutStylePreference.allCases
                    ),
                    proSegmentIndex: 2,
                    onProLockedTap: notifyProLocked
                )
            }
        }
    }

    private var overridePreviewRow: some View {
        let key = Preferences.indexToName("previewFocusedWindowOverride", index)
        return LabeledRow(
            NSLocalizedString("Preview selected window", comment: "")
        ) {
            HStack(spacing: 8) {
                if vm.hasOverride("previewFocusedWindowOverride") {
                    unlinkButton(baseName: "previewFocusedWindowOverride")
                }
                Toggle("", isOn: store.boolBinding(for: key))
                    .toggleStyle(.switch)
            }
        }
    }

    private func unlinkButton(baseName: String) -> some View {
        SwiftUI.Button(action: {
            store.removeOverride(baseName, index)
        }) {
            Image(systemName: "link")
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .help(NSLocalizedString("Remove override", comment: ""))
    }
}

// MARK: - Ordering section (3 dropdowns)

@available(macOS 13.0, *)
struct OrderingSectionView: View {
    @EnvironmentObject var store: PreferencesStore
    let index: Int

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                orderingPicker(
                    NSLocalizedString("Group apps", comment: ""),
                    baseName: "showAppsOrWindows",
                    allCases: GroupAppsPreference.allCases
                )
                Divider().padding(.leading, 10)
                orderingPicker(
                    NSLocalizedString("Group tabs", comment: ""),
                    baseName: "showTabsAsWindows",
                    allCases: GroupTabsPreference.allCases
                )
                Divider().padding(.leading, 10)
                orderingPicker(
                    NSLocalizedString("Order windows by", comment: ""),
                    baseName: "windowOrder",
                    allCases: WindowOrderPreference.allCases
                )
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
    }

    private func orderingPicker<
        T: MacroPreference & CaseIterable & Equatable & Hashable
    >(
        _ label: String,
        baseName: String,
        allCases: [T]
    ) -> some View {
        let key = Preferences.indexToName(baseName, index)
        return HStack {
            Text(label)
            Spacer()
            Picker("", selection: store.macroBinding(for: key, allCases)) {
                ForEach(allCases, id: \.self) { v in
                    Text(v.localizedString).tag(v)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Sheet stubs

@available(macOS 13.0, *)
struct ShortcutsWhenActiveSheetView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var proTracker: ProStateTracker
    @Environment(\.presentationMode) private var presentationMode

    private let keyLabels: [(String, String, Bool)] = [
        ("Focus selected window", "focusWindowShortcut", false),
        ("Select previous window", "previousWindowShortcut", false),
        ("Cancel", "cancelShortcut", false),
        ("Search", "searchShortcut", true),
        ("Lock search", "lockSearchShortcut", true),
        ("Close window", "closeWindowShortcut", false),
        ("Minimize/Deminimize window", "minDeminWindowShortcut", false),
        (
            "Fullscreen/Defullscreen window", "toggleFullscreenWindowShortcut",
            false
        ),
        ("Quit app", "quitAppShortcut", false),
        ("Hide/Show app", "hideShowAppShortcut", false),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Shortcuts When Active", comment: ""))
                .font(.headline)
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Array(keyLabels.enumerated()), id: \.offset) {
                        index,
                        item in
                        let (label, key, isProGated) = item
                        HStack {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString(label, comment: ""))
                                if isProGated && proTracker.isProLocked {
                                    ProBadgeLabel()
                                }
                            }
                            .frame(width: 220, alignment: .leading)
                            ShortcutRecorderField(
                                shortcut: store.shortcutBinding(for: key),
                                label: NSLocalizedString(label, comment: ""),
                                preferenceKey: key
                            )
                            .frame(height: 22)
                            Spacer()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        if index < keyLabels.count - 1 {
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
            SwiftUI.Button(NSLocalizedString("Done", comment: "")) {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.return)
        }.padding(20)
    }
}

@available(macOS 13.0, *)
struct AdditionalControlsSheetView: View {
    @EnvironmentObject var store: PreferencesStore
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Additional controls", comment: ""))
                .font(.headline)
            GroupBox {
                VStack(spacing: 0) {
                    LabeledRow(
                        NSLocalizedString(
                            "Select windows using arrow keys",
                            comment: ""
                        )
                    ) {
                        Toggle(
                            "",
                            isOn: store.boolBinding(for: "arrowKeysEnabled")
                        )
                        .toggleStyle(.switch)
                    }
                    Divider().padding(.leading, 10)
                    LabeledRow(
                        NSLocalizedString(
                            "Select windows using vim keys",
                            comment: ""
                        )
                    ) {
                        Toggle(
                            "",
                            isOn: store.boolBinding(for: "vimKeysEnabled")
                        )
                        .toggleStyle(.switch)
                    }
                    Divider().padding(.leading, 10)
                    LabeledRow(
                        NSLocalizedString(
                            "Select windows on mouse hover",
                            comment: ""
                        )
                    ) {
                        Toggle(
                            "",
                            isOn: store.boolBinding(for: "mouseHoverEnabled")
                        )
                        .toggleStyle(.switch)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Text(NSLocalizedString("Additional controls", comment: ""))
            }

            GroupBox {
                VStack(spacing: 0) {
                    LabeledRow(
                        NSLocalizedString("Cursor follows focus", comment: "")
                    ) {
                        Picker(
                            "",
                            selection: store.macroBinding(
                                for: "cursorFollowFocus",
                                CursorFollowFocus.allCases
                            )
                        ) {
                            ForEach(CursorFollowFocus.allCases, id: \.self) {
                                v in
                                Text(v.localizedString).tag(v)
                            }
                        }
                    }
                    Divider().padding(.leading, 10)
                    LabeledRow(
                        NSLocalizedString(
                            "Trackpad haptic feedback",
                            comment: ""
                        )
                    ) {
                        Toggle(
                            "",
                            isOn: store.boolBinding(
                                for: "trackpadHapticFeedbackEnabled"
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Text(NSLocalizedString("Miscellaneous", comment: ""))
            }

            SwiftUI.Button(NSLocalizedString("Done", comment: "")) {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.return)
        }
        .padding(20)
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
#Preview("Controls Tab - Mock Data") {
    Preferences.registerDefaults()

    let mockDefaults: [String: Any] = [
        "shortcutCount": "2",
        "shortcut_0_hold": "⌥",
        "shortcut_0_nextWindow": "⇥",
        "shortcut_1_hold": "⌥⇧",
        "shortcut_1_nextWindow": "⇥",
        "nextWindowGesture": "0",
    ]

    for (key, value) in mockDefaults {
        Preferences.set(key, value as! String)
    }

    return ControlsTabView()
        .environmentObject(PreferencesStore())
        .environmentObject(ProStateTracker())
        .environmentObject(SearchViewModel())
}

@available(macOS 13.0, *)
#Preview("Controls Tab (Pro Locked)") {
    Preferences.registerDefaults()

    let mockDefaults: [String: Any] = [
        "shortcutCount": "2",
        "shortcut_0_hold": "⌥",
        "shortcut_0_nextWindow": "⇥",
        "shortcut_1_hold": "⌥⇧",
        "shortcut_1_nextWindow": "⇥",
        "nextWindowGesture": "0",
    ]

    for (key, value) in mockDefaults {
        Preferences.set(key, value as! String)
    }

    let proState = ProStateTracker()
    proState.isProLocked = true

    return ControlsTabView()
        .environmentObject(PreferencesStore())
        .environmentObject(proState)
        .environmentObject(SearchViewModel())
}

@available(macOS 13.0, *)
#Preview("Shortcuts When Active Sheet") {
    Preferences.registerDefaults()
    return ShortcutsWhenActiveSheetView()
        .environmentObject(PreferencesStore())
        .environmentObject(ProStateTracker())
        .frame(width: 500)
}

@available(macOS 13.0, *)
#Preview("Shortcuts When Active Sheet (Pro Locked)") {
    Preferences.registerDefaults()
    let proState = ProStateTracker()
    proState.isProLocked = true
    return ShortcutsWhenActiveSheetView()
        .environmentObject(PreferencesStore())
        .environmentObject(proState)
        .frame(width: 500)
}

@available(macOS 13.0, *)
#Preview("Additional Controls Sheet") {
    Preferences.registerDefaults()
    return AdditionalControlsSheetView()
        .environmentObject(PreferencesStore())
        .environmentObject(SearchViewModel())
        .frame(width: 500)
}
