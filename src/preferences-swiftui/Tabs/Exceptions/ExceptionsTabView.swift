import SwiftUI

// MARK: - Exceptions tab

@available(macOS 13.0, *)
struct ExceptionsTabView: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var exceptions: [ExceptionEntry] = []
    @State private var selectedIndex: Int?

    private let sidebarWidth: CGFloat = 280
    private var editorWidth: CGFloat { SwiftUISettingsWindow.contentWidth - sidebarWidth - 1 }

    private var installedExceptions: [(index: Int, entry: ExceptionEntry)] {
        exceptions.enumerated().filter {
            let bundleId = $0.element.bundleIdentifier
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }.map { (index: $0.offset, entry: $0.element) }
    }

    var body: some View {
        HStack(spacing: 0) {
            exceptionsSidebar
                .frame(width: sidebarWidth)

            Rectangle().fill(.separator).frame(width: 1)

            exceptionsEditor
        }
        .frame(minHeight: 470)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .padding(20)
        .onAppear { exceptions = Preferences.exceptions }
    }

    // MARK: - Sidebar

    private var exceptionsSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedIndex) {
                ForEach(installedExceptions, id: \.index) { item in
                    ExceptionSidebarRow(entry: item.entry, index: item.index)
                        .tag(item.index as Int?)
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Menu {
                    ForEach(runningAppChoices, id: \.bundleIdentifier) { choice in
                        SwiftUI.Button(action: { addException(choice.bundleIdentifier) }) {
                            HStack {
                                if let path = choice.app.bundleURL?.path {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                Text(choice.name)
                            }
                        }
                    }
                    Divider()
                    SwiftUI.Button(
                        NSLocalizedString("Add an app from disk", comment: "")
                    ) {
                        addAppFromDisk()
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 16, height: 16)
                }
                .help(NSLocalizedString("Add a running app", comment: ""))

                Spacer()

                SwiftUI.Button(action: removeSelected) {
                    Image(systemName: "minus").frame(width: 16, height: 16)
                }
                .disabled(selectedIndex == nil)
                .help(NSLocalizedString("Remove selected", comment: ""))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var exceptionsEditor: some View {
        if let index = selectedIndex, exceptions.indices.contains(index) {
            SwiftUI.ScrollView {
                ExceptionEditorContentView(
                    entry: $exceptions[index],
                    onUpdate: { saveExceptions() }
                )
                .frame(width: editorWidth)
            }
        } else {
            VStack {
                Spacer()
                Text(NSLocalizedString("Select an app or add a new one", comment: ""))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(width: editorWidth)
        }
    }

    // MARK: - Running apps data

    private struct RunningAppChoice {
        let app: NSRunningApplication
        let bundleIdentifier: String
        let name: String
    }

    private var runningAppChoices: [RunningAppChoice] {
        let existingIds = Set(exceptions.map { $0.bundleIdentifier })
        var seen = Set<String>()
        var choices = [RunningAppChoice]()
        let candidates = (Windows.list.map { $0.application.runningApplication }
            + NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular })
        for app in candidates {
            guard let bundleId = app.bundleIdentifier,
                  !existingIds.contains(bundleId),
                  !seen.contains(bundleId) else { continue }
            seen.insert(bundleId)
            let name = app.localizedName ?? bundleId
            choices.append(RunningAppChoice(app: app, bundleIdentifier: bundleId, name: name))
        }
        return choices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Actions

    private func saveExceptions() {
        Preferences.set("exceptions", exceptions)
    }

    private func addException(_ bundleId: String) {
        if let existing = exceptions.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            selectedIndex = existing
            return
        }
        exceptions.append(ExceptionEntry(bundleIdentifier: bundleId, hide: .always, ignore: .none))
        selectedIndex = exceptions.count - 1
        saveExceptions()
    }

    private func addAppFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        addException(bundleId)
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        exceptions.remove(at: index)
        if exceptions.isEmpty { selectedIndex = nil }
        else if let idx = selectedIndex, idx >= exceptions.count { selectedIndex = exceptions.count - 1 }
        saveExceptions()
    }
}

// MARK: - Sidebar row

@available(macOS 13.0, *)
struct ExceptionSidebarRow: View {
    let entry: ExceptionEntry
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appUrl.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var appName: String {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier),
           let bundle = Bundle(url: appUrl) {
            return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? (appUrl.path as NSString).lastPathComponent
        }
        return entry.bundleIdentifier
    }

    private var summary: String {
        var parts = [String]()
        if entry.hide != .none {
            parts.append(entry.hide.localizedString)
        }
        if entry.ignore != .none {
            parts.append(entry.ignore.localizedString)
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Exception editor

@available(macOS 13.0, *)
struct ExceptionEditorContentView: View {
    @Binding var entry: ExceptionEntry
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            GroupBox {
                SwiftUI.TextField(
                    NSLocalizedString("e.g. com.example.app", comment: ""),
                    text: $entry.bundleIdentifier
                )
                .padding(.vertical, 6).padding(.horizontal, 10)
                .onChange(of: entry.bundleIdentifier) { _ in onUpdate() }
                .padding(.top, 4)
            } label: {
                SectionLabel(title: "Bundle ID")
            }

            GroupBox {
                VStack(spacing: 0) {
                    hideRow
                    if entry.hide == .windowTitleContains {
                        RowDivider()
                        patternsSection
                    }
                    RowDivider()
                    ignoreRow
                }
                .padding(.top, 4)
            } label: {
                SectionLabel(title: "Behavior")
            }
        }
        .padding(20)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appUrl.path))
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            Text(appName)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    // MARK: - Behavior rows

    private var hideRow: some View {
        LabeledRow(NSLocalizedString("Hide windows", comment: "")) {
            Picker("", selection: $entry.hide.onChange { onUpdate() }) {
                ForEach(ExceptionHidePreference.allCases, id: \.self) { pref in
                    Text(pref == .none
                        ? NSLocalizedString("Don't hide", comment: "")
                        : pref.localizedString
                    ).tag(pref)
                }
            }
        }
    }

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let patterns = Binding<[String]>(
                get: { entry.windowTitleContains ?? [] },
                set: { entry.windowTitleContains = $0.isEmpty ? nil : $0; onUpdate() }
            )
            ForEach(Array(patterns.wrappedValue.enumerated()), id: \.offset) { idx, _ in
                HStack {
                    SwiftUI.TextField(
                        NSLocalizedString("e.g. Debug", comment: ""),
                        text: Binding(
                            get: { patterns.wrappedValue.indices.contains(idx) ? patterns.wrappedValue[idx] : "" },
                            set: { newValue in
                                var arr = patterns.wrappedValue
                                if arr.indices.contains(idx) { arr[idx] = newValue; patterns.wrappedValue = arr }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    SwiftUI.Button(action: {
                        var arr = patterns.wrappedValue
                        if arr.indices.contains(idx) { arr.remove(at: idx); patterns.wrappedValue = arr }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            SwiftUI.Button(action: {
                var arr = patterns.wrappedValue
                arr.append("")
                patterns.wrappedValue = arr
            }) {
                Label(NSLocalizedString("Add a pattern", comment: ""), systemImage: "plus")
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
    }

    private var ignoreRow: some View {
        LabeledRow(NSLocalizedString("Ignore shortcuts", comment: "")) {
            Picker("", selection: $entry.ignore.onChange { onUpdate() }) {
                ForEach(ExceptionIgnorePreference.allCases, id: \.self) { pref in
                    Text(pref.localizedString == "" ? NSLocalizedString("Never", comment: "") : pref.localizedString)
                        .tag(pref)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var appName: String {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier),
           let bundle = Bundle(url: appUrl) {
            return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? (appUrl.path as NSString).lastPathComponent
        }
        return entry.bundleIdentifier
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

// MARK: - Binding onChange helper

@available(macOS 13.0, *)
extension Binding {
    func onChange(_ handler: @escaping () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0; handler() }
        )
    }
}
