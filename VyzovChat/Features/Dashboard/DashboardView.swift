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
    @State private var shifts: [ShiftRowDTO] = []
    @State private var days: [CalendarDayDTO] = []
    /// Выбранный день (YYYY-MM-DD); nil — показываем все отчёты по компаниям.
    @State private var selectedDay: String?
    @State private var dayEvents: [DashEventDTO] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var mediaPreview: MediaPreview?

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
                        page { shiftsContent }.tag(Mode.shifts)
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
            calendarStrip

            if let selectedDay {
                // Выбран день — показываем только его отчёты.
                if dayEvents.isEmpty {
                    EmptyState(icon: "calendar", title: "За этот день отчётов нет",
                               message: "Выберите другой день или вернитесь ко всем отчётам.")
                }
                ForEach(dayEvents) { event in eventCard(event) }
            } else {
                if companies.isEmpty {
                    EmptyState(icon: "tray", title: "Отчётов нет",
                               message: "Здесь появятся мероприятия с отправленным фотоотчётом.")
                }
                ForEach(companies) { company in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(company.name.isEmpty ? "Без компании" : company.name)
                            .font(Typography.headline).foregroundStyle(Theme.groupTitle)
                        ForEach(company.events) { event in eventCard(event) }
                    }
                }
            }
        }
    }

    /// Дни, за которые есть отчёты: сколько сдано и сколько ещё не смотрели.
    private var calendarStrip: some View {
        Group {
            if !days.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        dayChip(title: "Все", isOn: selectedDay == nil, badge: 0) {
                            selectedDay = nil
                        }
                        ForEach(days) { day in
                            dayChip(title: Self.shortDay(day.date),
                                    isOn: selectedDay == day.date,
                                    badge: max(day.total - day.viewed, 0)) {
                                Task { await select(day.date) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayChip(title: String, isOn: Bool, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.caption.weight(isOn ? .semibold : .regular))
                if badge > 0 { UnreadBadge(count: badge, background: isOn ? .white.opacity(0.3) : Theme.accent) }
            }
            .foregroundStyle(isOn ? Theme.textOnAccent : Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isOn ? Theme.accent : Theme.panel2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func select(_ date: String) async {
        selectedDay = date
        if let events = await session.dashboard.day(date) { dayEvents = events }
    }

    /// «31 июл» — в полосе дней место ограничено.
    private static func shortDay(_ iso: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.locale = Locale(identifier: "ru_RU")
        output.dateFormat = "d MMM"
        return output.string(from: date)
    }

    private func eventCard(_ event: DashEventDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name).font(Typography.callout.weight(.medium))
                            .foregroundStyle(Theme.textPrimary).lineLimit(3)
                        if let admins = event.admins, !admins.isEmpty {
                            Text("Ответственные: " + admins.map(\.fio).joined(separator: ", "))
                                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    if event.viewed != true {
                        Text("новое").font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textOnAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }

                if event.photos_restricted == true {
                    Label("Фото использовать нельзя", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Theme.warning)
                }
                if event.hasOpenClaim {
                    Label("Открыта претензия", systemImage: "exclamationmark.bubble.fill")
                        .font(.caption2).foregroundStyle(Theme.danger)
                }

                photoStrip(event)

                HStack(spacing: Spacing.m) {
                    stat("Смены", (event.checkins ?? []).count)
                    stat("Документы", (event.docs ?? []).count)
                    stat("Претензии", (event.claims ?? []).count)
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

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(Typography.callout.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(title).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Смены

    private var shiftsContent: some View {
        Group {
            if shifts.isEmpty {
                EmptyState(icon: "clock", title: "Смен нет",
                           message: "За последний месяц никто не отмечался.")
            }
            ForEach(shifts) { row in
                HStack(spacing: Spacing.s) {
                    Avatar(name: row.fio, size: 36, id: String(row.worker_id))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.fio).font(Typography.callout)
                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(row.event_name).font(.caption2)
                            .foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Text(interval(row)).font(.caption2).foregroundStyle(Theme.textSecondary)
                        if let note = markedBy(row) {
                            Text(note).font(.caption2).foregroundStyle(Theme.warning)
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(row.finished_at == nil ? Theme.success : Theme.textSecondary)
                        .frame(width: 8, height: 8)
                }
                .padding(Spacing.s)
                .glass(cornerRadius: Theme.cornerSmall, elevated: false)
            }
        }
    }

    private func interval(_ row: ShiftRowDTO) -> String {
        let start = Self.format(row.checked_at)
        guard let finished = row.finished_at else { return "с \(start) — на смене" }
        return "\(start) — \(Self.format(finished))"
    }

    private func markedBy(_ row: ShiftRowDTO) -> String? {
        let opened = row.opened_by?.isEmpty == false ? row.opened_by : nil
        let closed = row.closed_by?.isEmpty == false ? row.closed_by : nil
        switch (opened, closed) {
        case let (o?, c?) where o == c: return "отметил(а) \(o)"
        case let (o?, c?):              return "открыл(а) \(o), закрыл(а) \(c)"
        case let (o?, nil):             return "открыл(а) \(o)"
        case let (nil, c?):             return "закрыл(а) \(c)"
        default:                        return nil
        }
    }

    private static func format(_ iso: String) -> String {
        guard let date = DateParse.iso(iso) else { return "—" }
        return formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

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
            if let selectedDay, let events = await session.dashboard.day(selectedDay) {
                dayEvents = events
            }
        case .shifts:
            if let rows = await session.dashboard.allShifts(from: nil, to: nil) { shifts = rows }
        }
        isLoading = false
    }
}
