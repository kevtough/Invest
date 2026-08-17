import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, watchlist, chat, agent, orders, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .watchlist: return "Watchlist"
        case .chat: return "Research Chat"
        case .agent: return "AI Agent"
        case .orders: return "Orders"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .watchlist: return "list.star"
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .agent: return "sparkles"
        case .orders: return "arrow.left.arrow.right.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .dashboard: DashboardView()
        case .watchlist: WatchlistView()
        case .chat: ChatView()
        case .agent: AgentView()
        case .orders: OrdersView()
        case .settings: SettingsView()
        }
    }
}

/// Adaptive shell: a sidebar on iPad (regular width), a tab bar on iPhone
/// (compact width). Both present the same six sections.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .navigationTitle("Invest")
            } detail: {
                NavigationStack {
                    (selection ?? .dashboard).destination
                        .navigationTitle((selection ?? .dashboard).title)
                }
            }
        } else {
            TabView(selection: Binding(get: { selection ?? .dashboard }, set: { selection = $0 })) {
                ForEach(AppSection.allCases) { section in
                    NavigationStack {
                        section.destination
                            .navigationTitle(section.title)
                    }
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
                }
            }
        }
    }
}
