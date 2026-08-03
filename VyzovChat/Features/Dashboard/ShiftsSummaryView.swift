import SwiftUI

/// Сводка смен: сколько отработано за период, кем и на каких мероприятиях.
///
/// Считается на клиенте из сырых отметок — отдельного «свода» сервер не отдаёт.
struct ShiftsSummaryView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var period: ShiftsSummary.Period = .month
    @State private var anchor = Date()
    @State private var slice: ShiftsSummary.Slice = .people
    @State private var shifts: [ShiftRowDTO] = []
    @State private var isLoading = true

    private var range: (from: Date, to: Date) {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: period.component, for: anchor)
        let from = interval?.start ?? anchor
        let to = interval?.end ?? anchor
        return (from, to)
    }

    private var totals: ShiftsSummary.Totals { ShiftsSummary.totals(shifts) }
    private var rows: [ShiftsSummary.Row] { ShiftsSummary.rows(shifts, slice: slice) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                periodBar
                totalsRow
                sliceBar
                if isLoading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                } else if rows.isEmpty {
                    EmptyState(icon: "clock", title: "Смен нет",
                               message: "За выбранный период никто не отмечался.")
                } else {
                    table
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, Spacing.s)
        }
        .refreshable { await load() }
        .task(id: periodKey) { await load() }
    }

    /// Меняется при смене периода или сдвиге — по нему перезапрашиваем.
    private var periodKey: String { "\(period.rawValue)-\(range.from.timeIntervalSince1970)" }

    // MARK: - Период

    private var periodBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: 4) {
                ForEach(ShiftsSummary.Period.allCases) { p in
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { period = p }
                    } label: {
                        Text(p.rawValue)
                            .font(.caption.weight(period == p ? .semibold : .regular))
                            .foregroundStyle(period == p ? Theme.textOnAccent : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(period == p ? Theme.accent : Theme.panel2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 32)
                }
                Spacer()
                Text(periodTitle).font(Typography.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 32)
                }
            }
            .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        }
    }

    private func shift(_ delta: Int) {
        anchor = Calendar.current.date(byAdding: period.component, value: delta, to: anchor) ?? anchor
    }

    private var periodTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        switch period {
        case .day:   f.dateFormat = "d MMMM yyyy"
        case .week:  f.dateFormat = "d MMM"
        case .month: f.dateFormat = "LLLL yyyy"
        }
        if period == .week {
            let end = Calendar.current.date(byAdding: .day, value: -1, to: range.to) ?? range.to
            return f.string(from: range.from) + " — " + f.string(from: end)
        }
        return f.string(from: range.from).capitalized
    }

    // MARK: - Итоги

    private var totalsRow: some View {
        HStack(spacing: Spacing.xs) {
            tile(ShiftsSummary.hours(totals.seconds), "всего за период", Theme.textPrimary)
            tile("\(totals.trips)", "выездов", Theme.textPrimary)
            tile("\(totals.people)", "человек", Theme.textPrimary)
            tile("\(totals.onShift)", "ещё на смене", Theme.success)
        }
    }

    private func tile(_ value: String, _ caption: String, _ color: Color) -> some View {
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

    // MARK: - Разрезы

    private var sliceBar: some View {
        HStack(spacing: 4) {
            ForEach(ShiftsSummary.Slice.allCases) { s in
                Button {
                    withAnimation(.smooth(duration: 0.2)) { slice = s }
                } label: {
                    Text(s.rawValue)
                        .font(.caption.weight(slice == s ? .semibold : .regular))
                        .foregroundStyle(slice == s ? Theme.textOnAccent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(slice == s ? Theme.accent : Theme.panel2, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var table: some View {
        // Раскладываем отметки по ключу разреза один раз: NavigationLink
        // собирает свой экран сразу при появлении строки, и фильтровать весь
        // список заново для каждой строки было бы накладно.
        let grouped = Dictionary(grouping: shifts) {
            slice == .people ? String($0.worker_id) : String($0.event_id)
        }
        return VStack(spacing: Spacing.xs) {
            HStack {
                Text(slice == .people ? "СОТРУДНИК" : (slice == .companies ? "КОМПАНИЯ" : "МЕРОПРИЯТИЕ"))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("ВЫЕЗДОВ").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary).frame(width: 62, alignment: .trailing)
                Text("ЧАСЫ").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary).frame(width: 86, alignment: .trailing)
            }
            .padding(.horizontal, Spacing.s)

            ForEach(rows) { row in
                // В «Компаниях» проваливаться некуда: там нет ни одного
                // человека и ни одного мероприятия — только сумма.
                if slice == .companies {
                    tableRow(row)
                } else {
                    NavigationLink {
                        destination(for: row, own: grouped[row.id] ?? [])
                    } label: {
                        tableRow(row)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    /// Куда ведёт строка: человек — в свою сводку, мероприятие — в состав смен.
    @ViewBuilder
    private func destination(for row: ShiftsSummary.Row, own: [ShiftRowDTO]) -> some View {
        switch slice {
        case .people:
            WorkerShiftsDetailView(fio: row.title, rows: own)
        case .events:
            EventShiftsDetailView(eventId: Int(row.id) ?? 0,
                                  eventName: row.title,
                                  company: row.subtitle,
                                  rows: own)
        case .companies:
            EmptyView()
        }
    }

    private func tableRow(_ row: ShiftsSummary.Row) -> some View {
        HStack(spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary).lineLimit(2)
                HStack(spacing: 6) {
                    if let subtitle = row.subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    if let people = row.people {
                        Text("\(people) чел.").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    // «На смене» показываем только когда есть кого показывать —
                    // иначе колонка с прочерками занимает место зря.
                    if row.onShift > 0 {
                        Text("на смене: \(row.onShift)")
                            .font(.caption2).foregroundStyle(Theme.success)
                    }
                }
            }
            Spacer(minLength: Spacing.xs)
            Text("\(row.trips)").font(Typography.callout)
                .foregroundStyle(Theme.textPrimary).frame(width: 62, alignment: .trailing)
            Text(ShiftsSummary.hours(row.seconds))
                .font(Typography.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 86, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
            // Стрелка — знак, что строка ведёт дальше.
            if slice != .companies {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func load() async {
        let r = range
        if let rows = await session.dashboard.allShifts(from: r.from, to: r.to) { shifts = rows }
        isLoading = false
    }
}
