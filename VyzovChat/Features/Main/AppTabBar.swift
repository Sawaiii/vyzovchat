import SwiftUI

/// Вкладка приложения. Живёт отдельно от `MainTabView`, потому что о ней знают
/// все корневые экраны — каждый рисует полосу вкладок сам.
enum AppTab: Hashable {
    case chats, deals, dashboard, disk, profile

    var title: String {
        switch self {
        case .chats:     return "Чаты"
        case .deals:     return "Заказы"
        case .dashboard: return "Отчёты"
        case .disk:      return "Диск"
        case .profile:   return "Профиль"
        }
    }

    var icon: String {
        switch self {
        case .chats:     return "bubble.left.and.bubble.right.fill"
        case .deals:     return "briefcase.fill"
        case .dashboard: return "chart.bar.doc.horizontal.fill"
        case .disk:      return "externaldrive.fill"
        case .profile:   return "person.crop.circle.fill"
        }
    }
}

/// Полоса вкладок — своя, а не системная.
///
/// Системная живёт снаружи экрана и от перехода не зависит: при входе в чат она
/// пропадала разом, а при возврате выскакивала поверх уже открытого списка.
/// Управлять этим нечем — видимость, объявленная внутри стека навигации,
/// действует на весь стек, а не на один экран.
///
/// Своя полоса лежит прямо в корневом экране, поэтому уезжает и приезжает
/// вместе с ним — в том числе за пальцем при свайпе назад. Платим за это тем,
/// что каждый корневой экран должен позвать `.appTabBar()` у себя.
struct AppTabBar: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var router = Router.shared

    /// Дашборд серверный и целиком админский — обычному сотруднику его
    /// эндпоинты отвечают «admin_only», поэтому и вкладки ему не даём.
    private var tabs: [AppTab] {
        let all: [AppTab] = [.chats, .deals, .dashboard, .disk, .profile]
        guard session.currentUser?.isAdmin != true else { return all }
        return all.filter { $0 != .dashboard }
    }

    /// Высота задана жёстко. Без неё полоса меряется по содержимому, и на
    /// переключении вкладок её мерили заново для каждой страницы — от этого она
    /// и дёргалась на пиксель туда-обратно.
    static let height: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    guard router.tab != tab else { return }
                    router.tab = tab
                    // Отклика здесь нет намеренно: у системных вкладок его тоже
                    // нет, а завод движка приходится ровно на смену страницы.
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 20))
                        Text(tab.title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(router.tab == tab ? Theme.accent : Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Self.height)
        .background {
            // Непрозрачная подложка с тонкой линией сверху: полоса лежит над
            // содержимым экрана, и просвечивать сквозь неё оно не должно.
            // Подложка уходит под нижний край экрана, сами кнопки — нет.
            Theme.panel
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

extension View {
    /// Поставить полосу вкладок в подвал экрана.
    ///
    /// Звать НУЖНО у содержимого внутри `NavigationStack`, а не у самого стека:
    /// иначе полоса окажется снаружи и останется висеть поверх открытого чата —
    /// ровно как системная, от которой мы и уходим.
    ///
    /// Обычным стеком, а не `safeAreaInset`. Вставка в безопасную область
    /// считается отдельным проходом раскладки и пересчитывается для каждой
    /// страницы при переключении вкладок — от этого полоса и подрагивала.
    /// В стеке место под неё известно сразу, одним проходом.
    func appTabBar() -> some View {
        VStack(spacing: 0) {
            self
            AppTabBar()
        }
        // Системную полосу гасим здесь же. Объявленная внутри стека видимость
        // действует на весь стек — ровно то, что нужно: системной полосы не
        // должно быть нигде, ни в списке, ни в открытом из него чате.
        .toolbar(.hidden, for: .tabBar)
    }
}
