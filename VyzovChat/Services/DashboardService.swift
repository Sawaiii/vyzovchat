import Foundation

/// Дашборд руководителя: сданные отчёты по компаниям и календарю, плюс сводка
/// смен по всем мероприятиям.
///
/// Все эти эндпоинты сервер отдаёт только админу (руководитель на сервере —
/// это тоже `is_admin`), поэтому обычному сотруднику раздел не показываем.
/// Возвращают `nil`, когда запрос не удался: это не то же самое, что «данных нет».
/// Раньше сбой отдавал пустой список, экран затирал им показанное — и отчёты
/// пропадали, если обновить пару раз подряд.
protocol DashboardServicing {
    /// Отчёты, сгруппированные по компаниям.
    func dashboard() async -> [DashCompanyDTO]?
    /// Сводка по дням: сколько отчётов сдано и сколько просмотрено.
    func calendar(from: Date, to: Date) async -> [CalendarDayDTO]?
    /// Отчёты за конкретный день.
    func day(_ date: String) async -> [DashEventDTO]?
    /// Отметить отчёт просмотренным — по нему считается «новое» в календаре.
    func markViewed(dealId: String) async
    /// Смены по всем мероприятиям за период.
    func allShifts(from: Date?, to: Date?) async -> [ShiftRowDTO]?
}

final class RealDashboardService: DashboardServicing {

    func dashboard() async -> [DashCompanyDTO]? {
        try? await APIClient.shared.get("/api/dashboard", as: DashboardDTO.self).companies
    }

    func calendar(from: Date, to: Date) async -> [CalendarDayDTO]? {
        let path = "/api/dashboard/calendar?from=\(Self.day(from))&to=\(Self.day(to))"
        return try? await APIClient.shared.get(path, as: CalendarDTO.self).days
    }

    func day(_ date: String) async -> [DashEventDTO]? {
        try? await APIClient.shared.get("/api/dashboard/day?date=\(date)", as: DashboardDayDTO.self).events
    }

    func markViewed(dealId: String) async {
        _ = try? await APIClient.shared.post("/api/events/\(dealId)/report-viewed",
                                             json: EmptyBody(), as: OKDTO.self)
    }

    func allShifts(from: Date?, to: Date?) async -> [ShiftRowDTO]? {
        var items: [String] = []
        if let from { items.append("from=\(Self.day(from))") }
        if let to { items.append("to=\(Self.day(to))") }
        let query = items.isEmpty ? "" : "?" + items.joined(separator: "&")
        return try? await APIClient.shared.get("/api/shifts\(query)", as: [ShiftRowDTO].self)
    }

    /// Сервер ждёт голую дату YYYY-MM-DD; границу «по» он сам растягивает на весь день.
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

final class MockDashboardService: DashboardServicing {
    func dashboard() async -> [DashCompanyDTO]? { [] }
    func calendar(from: Date, to: Date) async -> [CalendarDayDTO]? { [] }
    func day(_ date: String) async -> [DashEventDTO]? { [] }
    func markViewed(dealId: String) async {}
    func allShifts(from: Date?, to: Date?) async -> [ShiftRowDTO]? { [] }
}
