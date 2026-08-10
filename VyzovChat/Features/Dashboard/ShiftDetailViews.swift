import SwiftUI

/// Общее для двух разборов сводки смен: подписи, форматы, плитки.
///
/// Оба экрана считаются из тех же отметок, что уже загружены для сводки, —
/// ходить за ними второй раз незачем.
enum ShiftDetail {
    static func roleLabel(_ role: String?) -> String? {
        switch role {
        case "admin":     return "старший"
        case "manager":   return "менеджер"
        case "warehouse": return "склад"
        default:          return nil
        }
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// «09:00 → 18:30 · 9 ч 30 мин», у незакрытой смены — «09:00 → на смене».
    static func interval(_ row: ShiftRowDTO) -> String {
        let from = DateParse.iso(row.checked_at).map { time.string(from: $0) } ?? "—"
        guard let finished = row.finished_at.flatMap(DateParse.iso) else {
            return "\(from) → на смене"
        }
        return "\(from) → \(time.string(from: finished)) · \(ShiftsSummary.hours(ShiftsSummary.duration(row)))"
    }

    /// Кто проставил отметку за человека. Пусто — отметился сам, и писать
    /// об этом нечего.
    static func markedBy(_ row: ShiftRowDTO) -> String? {
        var parts: [String] = []
        if let opened = row.opened_by, !opened.isEmpty { parts.append("открыл: \(opened)") }
        if let closed = row.closed_by, !closed.isEmpty { parts.append("закрыл: \(closed)") }
        // Правка задним числом — тоже в эту строку: без неё в отчёте появляются
        // часы, которых никто не проставлял.
        if let edit = row.editNote { parts.append(edit) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func tile(_ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Typography.callout.weight(.semibold))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    static func roleChip(_ role: String?) -> some View {
        Group {
            if let label = roleLabel(role) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.16), in: Capsule())
            }
        }
    }

    static func chatButton(eventId: Int) -> some View {
        Button {
            Router.shared.openChat(id: "chat-\(eventId)")
        } label: {
            Label("Перейти в чат", systemImage: "bubble.left")
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Theme.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Личная сводка сотрудника за период: сколько отработал и на каких
/// мероприятиях был.
struct WorkerShiftsDetailView: View {
    let fio: String
    /// Отметки только этого человека за выбранный период.
    let rows: [ShiftRowDTO]
    @Environment(\.adaptiveMetrics) private var metrics

    private var totals: ShiftsSummary.Totals { ShiftsSummary.totals(rows) }
    /// Свежие выезды сверху — так же, как в ленте отчётов.
    private var sorted: [ShiftRowDTO] {
        rows.sorted { (DateParse.iso($0.checked_at) ?? .distantPast) > (DateParse.iso($1.checked_at) ?? .distantPast) }
    }
    /// На скольких разных мероприятиях был: выездов может быть больше, если
    /// смену за день открывали не один раз.
    private var eventCount: Int { Set(rows.map(\.event_id)).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.xs) {
                    ShiftDetail.tile(ShiftsSummary.hours(totals.seconds), "часов за период", Theme.textPrimary)
                    ShiftDetail.tile("\(totals.trips)", "выездов", Theme.textPrimary)
                    ShiftDetail.tile("\(eventCount)", "мероприятий", Theme.textPrimary)
                    if totals.onShift > 0 {
                        ShiftDetail.tile("\(totals.onShift)", "ещё на смене", Theme.success)
                    }
                }

                if sorted.isEmpty {
                    EmptyState(icon: "clock", title: "Смен нет",
                               message: "За выбранный период человек не отмечался.")
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(sorted) { row in eventRow(row) }
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, Spacing.s)
        }
        .background(AmbientBackground().ignoresSafeArea())
        .navigationTitle(fio)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eventRow(_ row: ShiftRowDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                Text(row.event_name).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(2)
                Spacer(minLength: Spacing.xs)
                if let company = row.company_name, !company.isEmpty {
                    CompanyBadge(name: company)
                }
            }

            HStack(spacing: 6) {
                if let start = DateParse.iso(row.checked_at) {
                    Text(ShiftDetail.day.string(from: start))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Text(ShiftDetail.interval(row))
                    .font(.caption2)
                    .foregroundStyle(row.finished_at == nil ? Theme.success : Theme.textSecondary)
                ShiftDetail.roleChip(row.role)
            }

            if let marked = ShiftDetail.markedBy(row) {
                Text(marked).font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
            }

            Button {
                Router.shared.openChat(id: "chat-\(row.event_id)")
            } label: {
                Label("В чат", systemImage: "bubble.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }
}

/// Мероприятие в разрезе смен: кто отмечался, с какими статусами и переход
/// в чат мероприятия.
struct EventShiftsDetailView: View {
    let eventId: Int
    let eventName: String
    let company: String?
    /// Отметки только по этому мероприятию за выбранный период.
    let rows: [ShiftRowDTO]
    @Environment(\.adaptiveMetrics) private var metrics

    private var totals: ShiftsSummary.Totals { ShiftsSummary.totals(rows) }

    /// Один человек мог открывать смену несколько раз — в списке участников он
    /// должен быть один, с суммой часов.
    private struct Person: Identifiable {
        let id: Int
        let fio: String
        let role: String?
        let shifts: [ShiftRowDTO]
        var seconds: TimeInterval { shifts.reduce(0) { $0 + ShiftsSummary.duration($1) } }
        var isOnShift: Bool { shifts.contains { $0.finished_at == nil } }
    }

    private var people: [Person] {
        var buckets: [Int: [ShiftRowDTO]] = [:]
        for row in rows { buckets[row.worker_id, default: []].append(row) }
        return buckets.compactMap { id, group -> Person? in
            guard let first = group.first else { return nil }
            return Person(id: id, fio: first.fio.isEmpty ? "Без имени" : first.fio,
                          role: first.role, shifts: group)
        }
        // Кто ещё на смене — сверху: по ним и вопросы.
        .sorted {
            $0.isOnShift == $1.isOnShift ? $0.seconds > $1.seconds : $0.isOnShift
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let company, !company.isEmpty {
                    CompanyBadge(name: company, compact: false)
                }

                HStack(spacing: Spacing.xs) {
                    ShiftDetail.tile(ShiftsSummary.hours(totals.seconds), "часов всего", Theme.textPrimary)
                    ShiftDetail.tile("\(totals.people)", "человек", Theme.textPrimary)
                    ShiftDetail.tile("\(totals.trips)", "выходов", Theme.textPrimary)
                    if totals.onShift > 0 {
                        ShiftDetail.tile("\(totals.onShift)", "на смене", Theme.success)
                    }
                }

                ShiftDetail.chatButton(eventId: eventId)

                if people.isEmpty {
                    EmptyState(icon: "person.2", title: "Отметок нет",
                               message: "За выбранный период на мероприятии никто не отмечался.")
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(people) { person in personRow(person) }
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, Spacing.s)
        }
        .background(AmbientBackground().ignoresSafeArea())
        .navigationTitle(eventName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func personRow(_ person: Person) -> some View {
        // Из участника — в его личную сводку, но только по этому мероприятию:
        // разрез «Люди» покажет всё остальное.
        NavigationLink {
            WorkerShiftsDetailView(fio: person.fio, rows: person.shifts)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.xs) {
                    Avatar(name: person.fio, size: 28, id: String(person.id))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(person.fio).font(Typography.callout)
                                .foregroundStyle(Theme.textPrimary).lineLimit(1)
                            ShiftDetail.roleChip(person.role)
                        }
                        Text(person.isOnShift ? "на смене" : "смена закрыта")
                            .font(.caption2)
                            .foregroundStyle(person.isOnShift ? Theme.success : Theme.textSecondary)
                    }
                    Spacer(minLength: Spacing.xs)
                    Text(ShiftsSummary.hours(person.seconds))
                        .font(Typography.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }

                ForEach(person.shifts) { shift in
                    Text(ShiftDetail.interval(shift))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        }
        .buttonStyle(PressableStyle())
    }
}
