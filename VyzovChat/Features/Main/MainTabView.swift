import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var router = Router.shared

    private var showsDashboard: Bool { session.currentUser?.canViewAdmin ?? false }

    /// `TabView` остаётся ради того, ради чего он и нужен: он держит все вкладки
    /// живыми, и возврат на вкладку не перезагружает её с нуля. А вот полосу он
    /// больше не рисует — её рисует каждый корневой экран у себя, чтобы она
    /// уезжала в переход вместе с ним. Подробности в `AppTabBar`.
    var body: some View {
        TabView(selection: $router.tab) {
            ChatListView().tag(AppTab.chats)
            DealListView().tag(AppTab.deals)
            if showsDashboard {
                DashboardView().tag(AppTab.dashboard)
            }
            DiskView().tag(AppTab.disk)
            ProfileView().tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .onChange(of: router.wantsChatsTab) {
            if router.wantsChatsTab { router.tab = .chats; router.wantsChatsTab = false }
        }
    }
}
