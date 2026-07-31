import Foundation

/// Свод по сменам за период.
///
/// Сервер отдаёт сырые отметки (кто, где, когда открыл и закрыл смену), а суммы
/// считаются здесь: часы, выезды, сколько человек и сколько ещё не закрыли смену.
/// Незакрытая смена считается идущей до текущего момента — иначе «часы за период»
/// занижались бы ровно на тех, кто сейчас работает.
enum ShiftsSummary {

    /// Разрез сводки.
    enum Slice: String, CaseIterable, Identifiable {
        case people = "Люди"
        case companies = "Компании"
        case events = "Мероприятия"
        var id: String { rawValue }
    }

    /// Период показа.
    enum Period: String, CaseIterable, Identifiable {
        case day = "День"
        case week = "Неделя"
        case month = "Месяц"
        var id: String { rawValue }

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }
    }

    /// Строка таблицы: имя, необязательный подзаголовок и три числа.
    struct Row: Identifiable {
        let id: String
        let title: String
        /// Компания для мероприятия, иначе пусто.
        let subtitle: String?
        /// Сколько людей (только в разрезах «Компании» и «Мероприятия»).
        let people: Int?
        let trips: Int
        let onShift: Int
        let seconds: TimeInterval
    }

    struct Totals {
        var seconds: TimeInterval = 0
        var trips = 0
        var people = 0
        var onShift = 0
    }

    /// Длительность одной отметки. Незакрытая идёт до «сейчас».
    static func duration(_ row: ShiftRowDTO, now: Date = Date()) -> TimeInterval {
        guard let start = DateParse.iso(row.checked_at) else { return 0 }
        let end = row.finished_at.flatMap(DateParse.iso) ?? now
        return max(0, end.timeIntervalSince(start))
    }

    static func totals(_ rows: [ShiftRowDTO], now: Date = Date()) -> Totals {
        var t = Totals()
        t.trips = rows.count
        t.people = Set(rows.map(\.worker_id)).count
        t.onShift = rows.filter { $0.finished_at == nil }.count
        t.seconds = rows.reduce(0) { $0 + duration($1, now: now) }
        return t
    }

    /// Свести отметки в строки нужного разреза, от больших часов к меньшим.
    static func rows(_ shifts: [ShiftRowDTO], slice: Slice, now: Date = Date()) -> [Row] {
        switch slice {
        case .people:
            return group(shifts, key: { String($0.worker_id) },
                         title: { $0.fio.isEmpty ? "Без имени" : $0.fio },
                         subtitle: { _ in nil }, countPeople: false, now: now)
        case .companies:
            return group(shifts, key: { $0.company_name?.isEmpty == false ? $0.company_name! : "—" },
                         title: { $0.company_name?.isEmpty == false ? $0.company_name! : "Без компании" },
                         subtitle: { _ in nil }, countPeople: true, now: now)
        case .events:
            return group(shifts, key: { String($0.event_id) },
                         title: { $0.event_name },
                         subtitle: { $0.company_name?.isEmpty == false ? $0.company_name : nil },
                         countPeople: true, now: now)
        }
    }

    private static func group(_ shifts: [ShiftRowDTO],
                              key: (ShiftRowDTO) -> String,
                              title: (ShiftRowDTO) -> String,
                              subtitle: (ShiftRowDTO) -> String?,
                              countPeople: Bool,
                              now: Date) -> [Row] {
        var buckets: [String: [ShiftRowDTO]] = [:]
        var order: [String] = []
        for shift in shifts {
            let k = key(shift)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(shift)
        }
        return order.compactMap { k -> Row? in
            guard let group = buckets[k], let first = group.first else { return nil }
            return Row(
                id: k,
                title: title(first),
                subtitle: subtitle(first),
                people: countPeople ? Set(group.map(\.worker_id)).count : nil,
                trips: group.count,
                onShift: group.filter { $0.finished_at == nil }.count,
                seconds: group.reduce(0) { $0 + duration($1, now: now) }
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    /// «20 ч 55 мин», «56 мин», «0 мин» — как в веб-версии.
    static func hours(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
    }
}
