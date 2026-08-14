import SwiftUI

struct DealListView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @State private var deals: [Deal] = []
    @State private var isLoading = true
    @State private var didLoadOnce = false
    @State private var showArchive = false
    @State private var showCreate = false
    @State private var segment = "Все"
    @State private var companies: [String] = []
    @Namespace private var segmentPill

    private static let allTab = "Все"

    /// Заказы скрытых для сотрудника компаний не показываем вовсе.
    private var visibleDeals: [Deal] {
        let me = session.currentUser?.id ?? ""
        return deals.filter { !CompanyAccessStore.isHidden($0.company, for: me) }
    }

    /// Вкладки: «Все» + все компании с сервера (АРТ, ПРО, А+, РЕНТ4, АБА), даже
    /// если заказов у компании пока нет — иначе вкладка просто не появлялась.
    /// Плюс компании из самих заказов: вдруг бренд убрали из списка.
    private var segments: [String] {
        let me = session.currentUser?.id ?? ""
        var names = Set(companies)
        for deal in visibleDeals { if let company = deal.company { names.insert(company) } }
        return [Self.allTab] + names.filter { !CompanyAccessStore.isHidden($0, for: me) }.sorted()
    }

    private func deals(for segment: String) -> [Deal] {
        segment == Self.allTab ? visibleDeals : visibleDeals.filter { $0.company == segment }
    }

    private func activeDeals(_ list: [Deal]) -> [Deal] { list.filter { !$0.archived } }
    private func archivedDeals(_ list: [Deal]) -> [Deal] { list.filter { $0.archived } }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                if isLoading {
                    LoadingList()
                } else if visibleDeals.isEmpty {
                    ScrollView {
                        EmptyState(icon: "briefcase",
                                   title: "Нет заказов",
                                   message: "Здесь появятся сделки из Битрикса, на которые вы назначены.")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                    }
                    .refreshable { await load() }
                } else {
                    VStack(spacing: Spacing.s) {
                        // Разделение по компаниям — как только компании вообще есть.
                        if segments.count > 1 { segmentBar }
                        pager
                    }
                    .padding(.top, metrics.contentTopPadding)
                }
            }
            .navigationTitle("Заказы")
            // Крупный заголовок съедал полсотни точек над полосой компаний.
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            // Внутри стека: полоса уезжает вместе с экраном при переходе.
            .appTabBar()
            .toolbar {
                if session.currentUser?.isAdmin == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCreate = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateEventView(onCreated: { Task { await load() } })
                    .environmentObject(session)
            }
            .task { await load() }
            .onReceive(RealtimeService.shared.eventsChanged) { _ in Task { await load() } }
        }
    }

    /// Тот же переключатель, что и «Мероприятия — Личные — Архив» в чатах:
    /// синяя капсула перетекает между компаниями.
    private var segmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 4) {
                    ForEach(segments, id: \.self) { seg in
                        let isSelected = segment == seg
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { segment = seg }
                        } label: {
                            Text(seg)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundStyle(isSelected ? Theme.textOnAccent : Theme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background {
                                    if isSelected {
                                        Capsule().fill(Theme.accent)
                                            .matchedGeometryEffect(id: "dealPill", in: segmentPill)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(seg)
                    }
                }
                .padding(3)
                .background(Theme.panel2, in: Capsule())
                // Компанию переключают и свайпом списка — тогда её вкладка может
                // оказаться за краем экрана. Подтягиваем выбранную к центру.
                .onChange(of: segment) {
                    withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(segment, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(segment, anchor: .center) }
            }
        }
        .horizontalStrip()
        .padding(.horizontal, metrics.horizontalPadding)
    }

    /// Свайпы между компаниями — как между вкладками чатов.
    private var pager: some View {
        TabView(selection: $segment.animation(.smooth(duration: 0.25))) {
            ForEach(segments, id: \.self) { seg in
                dealColumn(for: seg).tag(seg)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func dealColumn(for seg: String) -> some View {
        let list = deals(for: seg)
        let active = activeDeals(list)
        let archived = archivedDeals(list)

        if list.isEmpty {
            ScrollView {
                EmptyState(icon: "briefcase", title: "Нет заказов",
                           message: "У компании \(seg) пока нет мероприятий.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
            .refreshable { await load() }
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.s) {
                    ForEach(active) { deal in dealLink(deal) }

                    if !archived.isEmpty {
                        Button {
                            withAnimation(.smooth) { showArchive.toggle() }
                        } label: {
                            HStack {
                                Image(systemName: "archivebox.fill")
                                Text("Архив (\(archived.count))")
                                Spacer()
                                Image(systemName: showArchive ? "chevron.up" : "chevron.down")
                            }
                            .font(Typography.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(Spacing.s)
                            .glass(cornerRadius: Theme.cornerMedium, elevated: false)
                        }
                        .buttonStyle(PressableStyle())

                        if showArchive {
                            ForEach(archived) { deal in dealLink(deal).opacity(0.7) }
                        }
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xl)
            }
            // Обновление — на самом списке. На экране целиком его подхватывала
            // и полоса компаний: она тянулась вниз пальцем и пробовала
            // перезагрузить заказы.
            .refreshable { await load() }
        }
    }

    private func dealLink(_ deal: Deal) -> some View {
        NavigationLink { DealDetailView(deal: deal) } label: { DealRow(deal: deal) }
            .buttonStyle(PressableStyle())
    }

    private func load() async {
        guard let user = session.currentUser else { return }
        if !didLoadOnce { isLoading = true }
        async let loadedDeals = session.directory.fetchDeals(for: user)
        async let loadedCompanies = session.directory.fetchCompanies()
        // Вкладки строятся по названиям компаний, id здесь не нужен.
        let (fetchedDeals, fetchedCompanies) = await (loadedDeals, loadedCompanies)
        deals = fetchedDeals
        companies = fetchedCompanies.map(\.name)
        // Компания могла исчезнуть из списка — не остаёмся на пустой вкладке.
        if !segments.contains(segment) { segment = Self.allTab }
        isLoading = false
        didLoadOnce = true
    }
}

struct DealRow: View {
    let deal: Deal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                Text(deal.title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // «Вы старший» и прочие роли: в списке важно сразу видеть, где с
                // тебя спрос больше, чем с участника.
                if let role = deal.myRoleChip { RoleChip(role: role) }
            }

            DealStatusBadges(deal: deal)

            if let address = deal.address {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack {
                Label("#\(deal.id)", systemImage: "number")
                Spacer()
                if let date = deal.eventDate {
                    Label(RelativeDate.short(date), systemImage: "calendar")
                }
            }
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.m)
        .glass(cornerRadius: Theme.cornerMedium)
        .contentShape(Rectangle())
    }
}

/// Бейджи статусов мероприятия (активно / нет отчёта / архив …).
struct DealStatusBadges: View {
    let deal: Deal
    var body: some View {
        HStack(spacing: 5) {
            if let company = deal.company { CompanyBadge(name: company, compact: false) }
            StatusBadgesRow(badges: deal.statusBadges)
        }
    }
}

struct StageBadge: View {
    let stage: Deal.Stage

    var body: some View {
        Text(stage.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch stage {
        case .new: return Theme.textSecondary
        case .prepare: return Theme.warning
        case .inProgress: return Theme.accent
        case .photoReport: return Theme.accentSecondary
        case .done: return Theme.success
        }
    }
}
