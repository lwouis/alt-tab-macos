import SwiftUI
@available(macOS 13.0, *)
struct ExceptionsTabView: View {
    @EnvironmentObject var store: PreferencesStore
    @State private var exceptions: [ExceptionEntry] = []
    @State private var selectedIndex: Int?

    private let sidebarWidth: CGFloat = 280
    private let editorWidth: CGFloat = SwiftUISettingsWindow.contentWidth - 280 - 1

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                List(selection: $selectedIndex) {
                    ForEach(Array(exceptions.enumerated()), id: \.offset) { index, entry in
                        ExceptionSidebarRow(entry: entry, index: index)
                            .tag(index as Int?)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    SwiftUI.Button(action: addRunningApp) {
                        Image(systemName: "plus")
                    }
                    .help(NSLocalizedString("Add a running app", comment: ""))

                    SwiftUI.Button(action: addAppFromDisk) {
                        Image(systemName: "doc.badge.plus")
                    }
                    .help(NSLocalizedString("Add an app from disk", comment: ""))

                    Spacer()

                    SwiftUI.Button(action: removeSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedIndex == nil)
                    .help(NSLocalizedString("Remove selected", comment: ""))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(width: sidebarWidth)

            Rectangle().fill(.separator).frame(width: 1)

            // Editor
            if let index = selectedIndex, exceptions.indices.contains(index) {
                ExceptionEditorContentView(
                    entry: $exceptions[index],
                    onUpdate: { saveExceptions() }
                )
                .frame(width: editorWidth)
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
        .frame(minHeight: 470)
        .onAppear { exceptions = Preferences.exceptions }
    }

    private func saveExceptions() {
        Preferences.set("exceptions", exceptions)
    }

    private func addRunningApp() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleIdentifier }
            .filter { bid in !exceptions.contains(where: { $0.bundleIdentifier == bid }) }
        guard let bundleId = runningApps.first else { return }
        exceptions.append(ExceptionEntry(bundleIdentifier: bundleId, hide: .none, ignore: .none))
        selectedIndex = exceptions.count - 1
        saveExceptions()
    }

    private func addAppFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        exceptions.append(ExceptionEntry(bundleIdentifier: bundleId, hide: .none, ignore: .none))
        selectedIndex = exceptions.count - 1
        saveExceptions()
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
        SwiftUI.ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appUrl.path))
                            .resizable()
                            .frame(width: 56, height: 56)
                    }
                    Text(appName)
                        .font(.system(size: 15, weight: .semibold))
                }

                // Bundle ID
                GroupBox {
                    VStack(spacing: 0) {
                        SwiftUI.TextField("e.g. com.example.app", text: $entry.bundleIdentifier)
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .onChange(of: entry.bundleIdentifier) { _ in onUpdate() }
                    }
                } label: {
                    Text(NSLocalizedString("Bundle ID", comment: ""))
                }

                // Behavior
                GroupBox {
                    VStack(spacing: 0) {
                        hideRow
                            .padding(.vertical, 6).padding(.horizontal, 10)

                        if entry.hide == .windowTitleContains {
                            Divider().padding(.leading, 10)
                            patternsSection
                                .padding(.vertical, 6).padding(.horizontal, 10)
                        }

                        Divider().padding(.leading, 10)

                        ignoreRow
                            .padding(.vertical, 6).padding(.horizontal, 10)
                    }
                } label: {
                    Text(NSLocalizedString("Behavior", comment: ""))
                }
            }
            .padding(20)
        }
    }

    private var hideRow: some View {
        HStack {
            Text(NSLocalizedString("Hide windows", comment: ""))
            Spacer()
            Picker("", selection: $entry.hide.onChange { onUpdate() }) {
                ForEach(ExceptionHidePreference.allCases.filter { $0 != .none }, id: \.self) { pref in
                    Text(pref.localizedString).tag(pref)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
        }
    }

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let patterns = Binding<[String]>(
                get: { entry.windowTitleContains ?? [] },
                set: { entry.windowTitleContains = $0.isEmpty ? nil : $0; onUpdate() }
            )
            ForEach(Array(patterns.wrappedValue.enumerated()), id: \.offset) { idx, pattern in
                HStack {
                    SwiftUI.TextField(NSLocalizedString("e.g. Debug", comment: ""), text: Binding(
                        get: { patterns.wrappedValue.indices.contains(idx) ? patterns.wrappedValue[idx] : "" },
                        set: { newValue in
                            var arr = patterns.wrappedValue
                            if arr.indices.contains(idx) { arr[idx] = newValue; patterns.wrappedValue = arr }
                        }
                    ))
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
    }

    private var ignoreRow: some View {
        HStack {
            Text(NSLocalizedString("Ignore shortcuts", comment: ""))
            Spacer()
            Picker("", selection: $entry.ignore.onChange { onUpdate() }) {
                ForEach(ExceptionIgnorePreference.allCases, id: \.self) { pref in
                    Text(pref.localizedString == "" ? NSLocalizedString("Never", comment: "") : pref.localizedString).tag(pref)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
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
