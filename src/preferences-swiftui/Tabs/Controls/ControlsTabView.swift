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

    private let sidebarWidth: CGFloat = 175
    private var editorWidth: CGFloat { SwiftUISettingsWindow.contentWidth - sidebarWidth - 1 }

    private var shortcutCount: Int { store.shortcutCount }

    var body: some View {
        HStack(spacing: 0) {
            ShortcutSidebarView(
                count: store.shortcutCountBinding,
                selectedIndex: $selectedIndex,
                maxCount: Preferences.maxShortcutCount,
                minCount: Preferences.minShortcutCount,
                isProLocked: proTracker.isProLocked,
                onProGateViolation: { /* TODO: navigate to upgrade */ }
            )
            .frame(width: sidebarWidth)

            Rectangle().fill(.separator).frame(width: 1)

            // Editor pane
            VStack(alignment: .leading, spacing: 0) {
                editorContent
            }
            .frame(width: editorWidth)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(20)
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
                        shortcut: store.shortcutBinding(for: vm.holdShortcutKey),
                        label: NSLocalizedString("Hold", comment: "")
                    )
                    .frame(height: 22)

                    Text(NSLocalizedString("and press", comment: ""))

                    Text(NSLocalizedString("Select next window", comment: ""))
                    ShortcutRecorderField(
                        shortcut: store.shortcutBinding(for: vm.nextWindowShortcutKey),
                        label: NSLocalizedString("Select next window", comment: "")
                    )
                    .frame(height: 22)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            } label: {
                Text(NSLocalizedString("Trigger", comment: ""))
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer().frame(height: 10)

            // Tab control
            Picker("", selection: $selectedSegment) {
                Text(NSLocalizedString("Filtering", comment: "")).tag(0)
                Text(NSLocalizedString("Appearance", comment: "")).tag(1)
                Text(NSLocalizedString("Ordering & Grouping", comment: "")).tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: editorWidth - 32)

            Spacer().frame(height: 8)

            // Tab content
            Group {
                switch selectedSegment {
                case 0: FilteringSection(index: index)
                case 1: AppearanceOverrideSectionView(index: index)
                case 2: OrderingSectionView(index: index)
                default: EmptyView()
                }
            }
            .frame(minHeight: 300)

            Spacer()

            // Tool buttons
            HStack(spacing: 12) {
                SwiftUI.Button(NSLocalizedString("Additional controls…", comment: "")) {
                    showAdditionalControlsSheet = true
                }
                SwiftUI.Button(NSLocalizedString("Shortcuts when active…", comment: "")) {
                    showShortcutsSheet = true
                }
            }
        }
        .sheet(isPresented: $showShortcutsSheet) {
            ShortcutsWhenActiveSheetView()
                .environmentObject(store)
                .environmentObject(proTracker)
                .frame(width: 500, height: 600)
        }
        .sheet(isPresented: $showAdditionalControlsSheet) {
            AdditionalControlsSheetView()
                .environmentObject(store)
                .frame(width: 500, height: 400)
        }
    }

    // MARK: - Gesture editor

    private var gestureEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox {
                HStack(spacing: 8) {
                    Picker("", selection: store.macroBinding(for: "nextWindowGesture", GesturePreference.allCases)) {
                        ForEach(GesturePreference.allCases, id: \.self) { g in
                            Text(g.localizedString).tag(g)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)

                    SwiftUI.Button(action: { /* open Trackpad Settings */ }) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .help(NSLocalizedString("You may need to disable some conflicting system gestures", comment: ""))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            } label: {
                Text(NSLocalizedString("Trigger", comment: ""))
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer()
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
                    if count >= 1 && isProLocked { onProGateViolation(); return }
                    count += 1
                }) { Image(systemName: "plus") }
                .disabled(count >= maxCount)

                SwiftUI.Button(action: {
                    guard count > minCount else { return }
                    count -= 1
                    if selectedIndex >= count && selectedIndex < Preferences.gestureIndex {
                        selectedIndex = count - 1
                    }
                }) { Image(systemName: "minus") }
                .disabled(count <= minCount)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func shortcutRowView(index: Int) -> some View {
        ShortcutSidebarRowView(index: index, isSelected: selectedIndex == index)
            .onTapGesture { selectedIndex = index }
            .background(selectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
    }

    private var gestureRowView: some View {
        ShortcutSidebarRowView(index: Preferences.gestureIndex, isSelected: selectedIndex == Preferences.gestureIndex)
            .onTapGesture { selectedIndex = Preferences.gestureIndex }
            .background(selectedIndex == Preferences.gestureIndex ? Color.accentColor.opacity(0.15) : Color.clear)
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
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
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
                filteringPicker(NSLocalizedString("Show windows from applications", comment: ""),
                                baseName: "appsToShow", allCases: AppsToShowPreference.allCases)
                Divider().padding(.leading, 10)
                filteringPicker(NSLocalizedString("Show windows from Spaces", comment: ""),
                                baseName: "spacesToShow", allCases: SpacesToShowPreference.allCases)
                Divider().padding(.leading, 10)
                filteringPicker(NSLocalizedString("Show windows from screens", comment: ""),
                                baseName: "screensToShow", allCases: ScreensToShowPreference.allCases)
                Divider().padding(.leading, 10)
                filteringPicker(NSLocalizedString("Show minimized windows", comment: ""),
                                baseName: "showMinimizedWindows", allCases: ShowHowPreference.allCases)
                Divider().padding(.leading, 10)
                filteringPicker(NSLocalizedString("Show hidden windows", comment: ""),
                                baseName: "showHiddenWindows", allCases: ShowHowPreference.allCases)
                Divider().padding(.leading, 10)
                filteringPicker(NSLocalizedString("Show fullscreen windows", comment: ""),
                                baseName: "showFullscreenWindows", allCases: ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
                Divider().padding(.leading, 10)
                filteringPicker(NSLocalizedString("Show apps with no open window", comment: ""),
                                baseName: "showWindowlessApps", allCases: ShowHowPreference.allCases)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
    }

    private func filteringPicker<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        _ label: String, baseName: String, allCases: [T]
    ) -> some View {
        let key = Preferences.indexToName(baseName, index)
        return HStack {
            Text(label).frame(width: 220, alignment: .leading)
            Spacer()
            Picker("", selection: store.macroBinding(for: key, allCases)) {
                ForEach(allCases, id: \.self) { v in
                    Text(v.localizedString).tag(v)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
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

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                overrideStyleRow
                Divider().padding(.leading, 10)
                overrideSegmentedRow(
                    NSLocalizedString("Size", comment: ""),
                    baseName: "appearanceSizeOverride",
                    allCases: AppearanceSizePreference.allCases
                )
                Divider().padding(.leading, 10)
                overrideSegmentedRow(
                    NSLocalizedString("Theme", comment: ""),
                    baseName: "appearanceThemeOverride",
                    allCases: AppearanceThemePreference.allCases
                )
                Divider().padding(.leading, 10)
                overrideSegmentedRow(
                    NSLocalizedString("After keys are released", comment: ""),
                    baseName: "shortcutStyleOverride",
                    allCases: ShortcutStylePreference.allCases
                )
                Divider().padding(.leading, 10)
                overrideToggleRow(
                    NSLocalizedString("Preview selected window", comment: ""),
                    baseName: "previewFocusedWindowOverride"
                )
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
    }

    private var overrideStyleRow: some View {
        let styleKey = Preferences.indexToName("appearanceStyleOverride", index)
        let binding = store.macroBinding(for: styleKey, AppearanceStylePreference.allCases)
        return HStack {
            ImageRadioGroup(
                selection: binding,
                entries: [
                    (.thumbnails, AppearanceStylePreference.thumbnails.localizedString, "thumbnails"),
                    (.appIcons, AppearanceStylePreference.appIcons.localizedString, "app_icons"),
                    (.titles, AppearanceStylePreference.titles.localizedString, "titles"),
                ],
                proGatedIndices: [1, 2]
            )
            Spacer()
            if vm.hasOverride("appearanceStyleOverride") {
                unlinkButton(baseName: "appearanceStyleOverride")
            }
        }
    }

    private func overrideSegmentedRow<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        _ label: String, baseName: String, allCases: [T]
    ) -> some View {
        let key = Preferences.indexToName(baseName, index)
        let binding = store.macroBinding(for: key, allCases)
        return HStack {
            Text(label).frame(width: 180, alignment: .leading)
            Picker("", selection: binding) {
                ForEach(allCases, id: \.self) { v in
                    Text(v.localizedString).tag(v)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
            if vm.hasOverride(baseName) {
                unlinkButton(baseName: baseName)
            }
        }
        .padding(.vertical, 6)
    }

    private func overrideToggleRow(_ label: String, baseName: String) -> some View {
        let key = Preferences.indexToName(baseName, index)
        let binding = store.boolBinding(for: key)
        return HStack {
            Text(label).frame(width: 180, alignment: .leading)
            Toggle("", isOn: binding)
            Spacer()
            if vm.hasOverride(baseName) {
                unlinkButton(baseName: baseName)
            }
        }
        .padding(.vertical, 6)
    }

    private func unlinkButton(baseName: String) -> some View {
        SwiftUI.Button(action: {
            vm.removeOverride(baseName)
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
                orderingPicker(NSLocalizedString("Group apps", comment: ""),
                               baseName: "showAppsOrWindows", allCases: ShowAppsOrWindowsPreference.allCases)
                Divider().padding(.leading, 10)
                orderingPicker(NSLocalizedString("Group tabs", comment: ""),
                               baseName: "showTabsAsWindows", allCases: GroupTabsPreference.allCases)
                Divider().padding(.leading, 10)
                orderingPicker(NSLocalizedString("Order windows by", comment: ""),
                               baseName: "windowOrder", allCases: WindowOrderPreference.allCases)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
        }
    }

    private func orderingPicker<T: MacroPreference & CaseIterable & Equatable & Hashable>(
        _ label: String, baseName: String, allCases: [T]
    ) -> some View {
        let key = Preferences.indexToName(baseName, index)
        return HStack {
            Text(label).frame(width: 220, alignment: .leading)
            Spacer()
            Picker("", selection: store.macroBinding(for: key, allCases)) {
                ForEach(allCases, id: \.self) { v in
                    Text(v.localizedString).tag(v)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
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
        ("Fullscreen/Defullscreen window", "toggleFullscreenWindowShortcut", false),
        ("Quit app", "quitAppShortcut", false),
        ("Hide/Show app", "hideShowAppShortcut", false),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Shortcuts When Active", comment: ""))
                .font(.headline)
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Array(keyLabels.enumerated()), id: \.offset) { index, item in
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
                                label: NSLocalizedString(label, comment: "")
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
        }
        .padding(20)
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
                    Toggle(NSLocalizedString("Select windows using arrow keys", comment: ""),
                           isOn: store.boolBinding(for: "arrowKeysEnabled"))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                    Divider().padding(.leading, 10)
                    Toggle(NSLocalizedString("Select windows using vim keys", comment: ""),
                           isOn: store.boolBinding(for: "vimKeysEnabled"))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                    Divider().padding(.leading, 10)
                    Toggle(NSLocalizedString("Select windows on mouse hover", comment: ""),
                           isOn: store.boolBinding(for: "mouseHoverEnabled"))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                }
            } label: {
                Text(NSLocalizedString("Additional controls", comment: ""))
            }

            GroupBox {
                VStack(spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("Cursor follows focus", comment: ""))
                        Spacer()
                        Picker("", selection: store.macroBinding(for: "cursorFollowFocus", CursorFollowFocus.allCases)) {
                            ForEach(CursorFollowFocus.allCases, id: \.self) { v in
                                Text(v.localizedString).tag(v)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    Divider().padding(.leading, 10)
                    Toggle(NSLocalizedString("Trackpad haptic feedback", comment: ""),
                           isOn: store.boolBinding(for: "trackpadHapticFeedbackEnabled"))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                }
            } label: {
                Text(NSLocalizedString("Miscellaneous", comment: ""))
            }

            SwiftUI.Button(NSLocalizedString("Done", comment: "")) {
                NSApp.keyWindow?.sheetParent?.endSheet(NSApp.keyWindow!)
            }
            .keyboardShortcut(.return)
        }
        .padding(20)
    }
}
