import SwiftUI

/// Календарь отчётов: месяц целиком, на днях — сколько сдано и сколько ещё не
/// смотрели. Полоса дней это не заменяла: по ней не видно, что в середине месяца
/// была дыра, и не полистать назад.
struct ReportCalendar: View {
    /// Данные по дням (ключ — «YYYY-MM-DD»).
    let days: [String: CalendarDayDTO]
    @Binding var month: Date
    let selected: String?
    let onSelect: (String) -> Void

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2      // неделя с понедельника
        return c
    }()

    var body: some View {
        VStack(spacing: Spacing.xs) {
            header
            weekdayRow
            grid
        }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 32)
            }
            Spacer()
            Text(monthTitle).font(Typography.callout.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 32)
            }
        }
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "вс"], id: \.self) { name in
                Text(name).font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let cells = makeCells()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(cells, id: \.self) { date in
                if let date {
                    dayCell(date)
                } else {
                    // Пустая клетка до начала месяца — держит сетку ровной.
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = Self.key(date)
        let info = days[key]
        let isSelected = selected == key
        let unseen = max((info?.total ?? 0) - (info?.viewed ?? 0), 0)
        return Button { onSelect(key) } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.caption.weight(info == nil ? .regular : .semibold))
                    .foregroundStyle(info == nil ? Theme.textSecondary : Theme.textPrimary)
                if let info, info.total > 0 {
                    Text("\(info.total)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textOnAccent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(unseen > 0 ? Theme.accent : Theme.textSecondary, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(info == nil)
    }

    private func shift(_ delta: Int) {
        month = cal.date(byAdding: .month, value: delta, to: month) ?? month
    }

    /// Клетки месяца: сначала пустые до первого дня, затем сами дни.
    private func makeCells() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        // Сколько пустых клеток слева: понедельник — первый столбец.
        let weekday = cal.component(.weekday, from: first)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for day in 0..<count {
            cells.append(cal.date(byAdding: .day, value: day, to: first))
        }
        return cells
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    static func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
