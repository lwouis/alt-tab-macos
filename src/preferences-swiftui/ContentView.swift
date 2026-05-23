import SwiftUI

@available(macOS 13.0, *)
enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance, controls, general, exceptions, upgrade
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: return NSLocalizedString("Appearance", comment: "")
        case .controls: return NSLocalizedString("Controls", comment: "")
        case .general: return NSLocalizedString("General", comment: "")
        case .exceptions: return NSLocalizedString("Exceptions", comment: "")
        case .upgrade: return NSLocalizedString("Upgrade", comment: "")
        }
    }
    var symbolName: String {
        switch self {
        case .appearance: return "paintpalette"
        case .controls: return "command"
        case .general: return "gearshape"
        case .exceptions: return "hand.raised"
        case .upgrade: return "star.fill"
        }
    }
}

@available(macOS 13.0, *)
struct ContentView: View {
    @EnvironmentObject var store: PreferencesStore
    @EnvironmentObject var proTracker: ProStateTracker
    @EnvironmentObject var searchVM: SearchViewModel
    @State private var selectedTab: SettingsTab? = .appearance
    @State private var columnVisibility = NavigationSplitViewVisibility
        .automatic

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SearchFieldView(text: $searchVM.query)
                    .frame(height: 36)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                List(filteredTabs, selection: $selectedTab) { tab in
                    Label(tab.title, systemImage: tab.symbolName)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                //                .safeAreaInset(edge: .bottom) {
                //                    VStack(spacing: 8) {
                //                        Divider()
                //                        upgradeButton.padding(.horizontal, 8)
                //                        quitButton.padding(.horizontal, 8).padding(.bottom, 8)
                //                    }
                //                    .background(.bar)
                //                }
                .navigationSplitViewColumnWidth(
                    SwiftUISettingsWindow.sidebarWidth
                )
            } detail: {
                detailContent
            }
//            .navigationSplitViewStyle(.prominentDetail)
        }
        .onAppear { searchVM.applySearch() }
        .onChange(of: searchVM.query) { _ in searchVM.applySearch() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToUpgradeTab"))) { _ in
            selectedTab = .upgrade
        }
    }

    // MARK: - Filtered sidebar items

    private var filteredTabs: [SettingsTab] {
        SettingsTab.allCases.filter { tab in
            if tab == .upgrade { return true }
            return searchVM.isTabVisible(tab.id)
        }
    }

    // MARK: - Upgrade button

    @ViewBuilder
    private var upgradeButton: some View {
        if case .pro = proTracker.licenseState {
            VStack(spacing: 2) {
                Text(
                    proTracker.isLifetimeVariant
                        ? NSLocalizedString(
                            "Pro Lifetime activated",
                            comment: ""
                        )
                        : NSLocalizedString("Pro activated", comment: "")
                )
                .font(.caption2).foregroundColor(.white.opacity(0.8))
                if let email = proTracker.customerEmail {
                    Text(email).font(.caption.weight(.semibold))
                        .foregroundColor(.white).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6).padding(
                .horizontal,
                8
            )
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { selectedTab = .upgrade }
        } else {
            let subtitle: String = {
                if case .trial(let days) = proTracker.licenseState {
                    return String(
                        format: NSLocalizedString(
                            "Trial: %d days remaining",
                            comment: ""
                        ),
                        days
                    )
                }
                return NSLocalizedString("Get Pro", comment: "")
            }()
            VStack(spacing: 2) {
                Text(subtitle).font(.caption2).foregroundColor(
                    .white.opacity(0.8)
                )
                Text(NSLocalizedString("Get Pro", comment: "")).font(
                    .caption.weight(.semibold)
                ).foregroundColor(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6).padding(
                .horizontal,
                8
            )
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { selectedTab = .upgrade }
        }
    }

    // MARK: - Quit button

    private var quitButton: some View {
        SwiftUI.Button(
            String(
                format: NSLocalizedString("Quit %@", comment: "%@ is AltTab"),
                App.name
            )
        ) {
            NSApp.terminate(nil)
        }
        .buttonStyle(.borderless).font(.caption)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .appearance: AppearanceTabView()
        case .controls: ControlsTabView()
        case .general: GeneralTabView()
        case .exceptions: ExceptionsTabView()
        case .upgrade: UpgradeTabView()
        case nil: emptyDetail
        }
    }

    private var emptyDetail: some View {
        Text(NSLocalizedString("Select a section", comment: ""))
            .foregroundColor(.secondary)
    }
}

@available(macOS 13.0, *)
#Preview {
    Preferences.registerDefaults()
    return ContentView()
        .environmentObject(PreferencesStore())
        .environmentObject(ProStateTracker())
        .environmentObject(SearchViewModel())
}
