import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var router = Router.shared
    @State private var tab: Tab = .chats

    enum Tab { case chats, deals, dashboard, disk, profile }

    /// Дашборд серверный и целиком админский: обычному сотруднику его эндпоинты
    /// отвечают «admin_only», поэтому и вкладку ему не показываем.
    private var showsDashboard: Bool { session.currentUser?.isAdmin ?? false }

    var body: some View {
        TabView(selection: $tab) {
            ChatListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.chats)

            DealListView()
                .tabItem { Label("Заказы", systemImage: "briefcase.fill") }
                .tag(Tab.deals)

            if showsDashboard {
                DashboardView()
                    .tabItem { Label("Отчёты", systemImage: "chart.bar.doc.horizontal.fill") }
                    .tag(Tab.dashboard)
            }

            DiskView()
                .tabItem { Label("Диск", systemImage: "externaldrive.fill") }
                .tag(Tab.disk)

            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .tint(Theme.accent)
        .onChange(of: router.wantsChatsTab) {
            if router.wantsChatsTab { tab = .chats; router.wantsChatsTab = false }
        }
    }
}
