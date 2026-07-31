import SwiftUI

/// Дашборд руководителя: сданные отчёты и сводка смен.
///
/// Раздел серверный и целиком админский — эндпоинты отвечают `admin_only`
/// обычному сотруднику, поэтому вкладку ему и не показываем.
struct DashboardView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics

    enum Mode: Hashable { case reports, shifts }
    @State private var mode: Mode = .reports

    @State private var companies: [DashCompanyDTO] = []
    @State private var days: [CalendarDayDTO] = []
    /// Выбранный день (YYYY-MM-DD); nil — показываем все отчёты по компаниям.
    @State private var selectedDay: String?
    @State private var dayEvents: [DashEventDTO] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var mediaPreview: MediaPreview?
    @State private var showCalendar = true
    @State private var calendarMonth = Date()
    @State private var companyFilterName: String?
    /// Сколько человек в составе каждого мероприятия — знаменатель «На смене: 1/5».
    @State private var membersCount: [Int: Int] = [:]

    private var daysByDate: [String: CalendarDayDTO] {
        Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground().ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    // Пейджер, а не switch: между «Отчётами» и «Сменами» должно
                    // листаться свайпом, как между темами чата и вкладками Диска.
                    TabView(selection: $mode) {
                        page { reportsContent }.tag(Mode.reports)
                        // Смены — свой экран со сводкой за период; общий page
                        // с отступами ему не нужен.
                        ShiftsSummaryView().tag(Mode.shifts)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle(mode == .reports ? "Отчёты" : "Смены")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        Text("Отчёты").tag(Mode.reports)
                        Text("Смены").tag(Mode.shifts)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
            .task { await load() }
            .onChange(of: mode) { Task { await load() } }
            .fullScreenCover(item: $mediaPreview) { p in
                MediaPager(items: p.items, startIndex: p.index)
            }
        }
    }

    /// Одна страница пейджера: прокрутка с общими отступами.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) { content() }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, Spacing.s)
        }
        .refreshable { await load() }
    }

    // MARK: - Отчёты

    private var reportsContent: some View {
        Group {
            // Две подстраницы, как в вебе: календарь и общий список.
            HStack(spacing: 4) {
                subTab("Календарь", isOn: showCalendar) { showCalendar = true }
                subTab("Все отчёты", isOn: !showCalendar) { showCalendar = false; selectedDay = nil }
            }

            if showCalendar {
                ReportCalendar(days: daysByDate, month: $calendarMonth,
                               selected: selectedDay) { key in
                    Task { await select(key) }
                }
                if let selectedDay {
                    Text(dayEvents.isEmpty ? "За этот день отчётов нет" : "Отчёты за \(Self.humanDay(selectedDay))")
                        .font(Typography.caption).foregroundStyle(Theme.textSecondary)
                    ForEach(dayEvents) { event in eventCard(event, company: nil) }
                }
            } else {
                companyFilter
                if filteredEvents.isEmpty {
                    EmptyState(icon: "tray", title: "Отчётов нет",
                               message: "Здесь появятся мероприятия с отправленным фотоотчётом.")
                }
                ForEach(filteredEvents, id: \.event.id) { pair in
                    eventCard(pair.event, company: pair.company)
                }
            }
        }
    }

    private func subTab(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Theme.textOnAccent : Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(isOn ? Theme.accent : Theme.panel2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Отчёты плоским списком с компанией у каждого — так их можно фильтровать
    /// чипами, не теряя, к какой компании относится мероприятие.
    private var allEvents: [(event: DashEventDTO, company: String)] {
        companies.flatMap { company in
            company.events.map { (event: $0, company: company.name) }
        }
    }

    private var filteredEvents: [(event: DashEventDTO, company: String)] {
        guard let companyFilterName else { return allEvents }
        return allEvents.filter { $0.company == companyFilterName }
    }

    private var companyFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("Все", count: allEvents.count, isOn: companyFilterName == nil) {
                    companyFilterName = nil
                }
                ForEach(companies) { company in
                    filterChip(company.name.isEmpty ? "Без компании" : company.name,
                               count: company.events.count,
                               isOn: companyFilterName == company.name) {
                        companyFilterName = company.name
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.caption.weight(isOn ? .semibold : .regular))
                Text("\(count)").font(.system(size: 9))
                    .opacity(0.7)
            }
            .foregroundStyle(isOn ? Theme.textOnAccent : Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isOn ? Theme.accent : Theme.panel2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private static func humanDay(_ key: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: key) else { return key }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ru_RU")
        out.dateFormat = "d MMMM"
        return out.string(from: date)
    }

    private func select(_ date: String) async {
        selectedDay = date
        if let events = await session.dashboard.day(date) { dayEvents = events }
    }

    private func eventCard(_ event: DashEventDTO, company: String?) -> some View {
        let onShift = (event.checkins ?? []).filter { $0.finished_at == nil }.count
        let total = membersCount[event.id] ?? (event.checkins ?? []).count
        let openClaims = (event.claims ?? []).filter(\.isOpen).count
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text(event.name).font(Typography.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(3)
                    Spacer(minLength: Spacing.xs)
                    if let company, !company.isEmpty { CompanyBadge(name: company) }
                    if event.viewed != true {
                        Text("новое").font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textOnAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }

                // Ответственные за мероприятие — их видно первыми: с них и спрос.
                if let admins = event.admins, !admins.isEmpty {
                    FlowLayout(spacing: 4) {
                        Text("Главный:").font(.caption2).foregroundStyle(Theme.textSecondary)
                        ForEach(admins) { admin in
                            Label(admin.fio, systemImage: "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Theme.panel2, in: Capsule())
                        }
                    }
                }

                if event.photos_restricted == true {
                    Label("ФОТО НЕЛЬЗЯ БРАТЬ", systemImage: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.danger, in: Capsule())
                }
                if openClaims > 0 {
                    Label("Претензия · \(openClaims)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.warning.opacity(0.15), in: Capsule())
                }

                photoStrip(event)

                HStack(spacing: Spacing.xs) {
                    chip("Документы: \((event.docs ?? []).isEmpty ? "нет" : "\((event.docs ?? []).count)")",
                         icon: "doc.text")
                    chip("На смене: \(onShift)/\(total)", icon: "person.badge.clock")
                    Spacer()
                    // Из отчёта можно сразу уйти в чат мероприятия и спросить.
                    Button {
                        Router.shared.openChat(id: "chat-\(event.id)")
                    } label: {
                        Label("В чат", systemImage: "bubble.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        // Открыли карточку — отчёт считается просмотренным; по этому же
        // признаку в календаре считается «новое».
        .onAppear {
            guard event.viewed != true else { return }
            Task { await session.dashboard.markViewed(dealId: String(event.id)) }
        }
    }

    private func photoStrip(_ event: DashEventDTO) -> some View {
        let photos = event.report_photos ?? []
        return Group {
            if photos.isEmpty {
                Text("Фото в отчёте нет.").font(.caption2).foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { idx, photo in
                            Button { open(photos, at: idx) } label: {
                                CachedAsyncImage(url: AppConfig.mediaURL(photo.thumb ?? photo.full)) {
                                    $0.resizable().scaledToFill()
                                } placeholder: {
                                    Theme.panel2
                                }
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func open(_ photos: [ReportPhotoDTO], at index: Int) {
        let items = photos.enumerated().map { idx, photo in
            Message.Attachment(id: "report-\(idx)",
                               remoteURL: AppConfig.mediaURL(photo.full ?? photo.thumb),
                               isVideo: false, isFile: false)
        }
        mediaPreview = MediaPreview(items: items, index: index)
    }

    private func chip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.panel2, in: Capsule())
    }

    private func load() async {
        // Повторные обновления и свайпы между страницами запускали загрузку
        // внахлёст: запросы отменяли друг друга, а неудача затирала показанное —
        // отчёты пропадали, если обновить пару раз подряд.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        switch mode {
        case .reports:
            // Месяц назад — месяц вперёд: столько же берёт веб-версия по умолчанию.
            let now = Date()
            let from = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            let to = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
            async let list = session.dashboard.dashboard()
            async let cal = session.dashboard.calendar(from: from, to: to)
            let (c, d) = await (list, cal)
            // nil = запрос не удался. Показанное не трогаем: пустой список здесь
            // означал бы «отчётов нет», а это неправда.
            if let c { companies = c }
            if let d { days = d }
            // Состав берём из общего списка мероприятий: в карточке отчёта его
            // нет, а без знаменателя «На смене» не посчитать.
            if let events = try? await APIClient.shared.get("/api/events", as: [EventDTO].self) {
                membersCount = Dictionary(events.compactMap { ev in
                    ev.members_count.map { (ev.id, $0) }
                }, uniquingKeysWith: { a, _ in a })
            }
            if let selectedDay, let events = await session.dashboard.day(selectedDay) {
                dayEvents = events
            }
        case .shifts:
            // Смены грузит свой экран — у него свой период.
            break
        }
        isLoading = false
    }
}
