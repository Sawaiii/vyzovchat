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
    /// Смены одного мероприятия целиком. Период здесь не применяется: мероприятие
    /// длится свои два дня, и «показать его смены» не должно зависеть от месяца,
    /// выбранного в сводке.
    func eventShifts(dealId: String) async -> [ShiftRowDTO]?
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

    func eventShifts(dealId: String) async -> [ShiftRowDTO]? {
        try? await APIClient.shared.get("/api/shifts?event=\(dealId)", as: [ShiftRowDTO].self)
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
    /// Вымышленная сводка руководителя: две компании, свежие и уже просмотренные
    /// мероприятия, смены за неделю — экран отчётов должен быть живым при съёмке.
    func dashboard() async -> [DashCompanyDTO]? {
        try? await Task.sleep(for: .milliseconds(400))
        return [
            DashCompanyDTO(name: "АРТ", events: [
                event(4102, "Конференция «Логистика 2026» — Крокус Экспо", viewed: false,
                      photos: 24, docs: 2, onShift: 3),
                event(4091, "Корпоратив «ТехноПром» — Резиденция", viewed: true,
                      photos: 61, docs: 3, onShift: 0),
                event(4077, "Выставка «АгроЭкспо» — павильон 3", viewed: true,
                      photos: 38, docs: 1, onShift: 0)
            ]),
            DashCompanyDTO(name: "А+", events: [
                event(4098, "Свадьба Королёвых — Loft Hall", viewed: false,
                      photos: 148, docs: 2, onShift: 1),
                event(4085, "Юбилей 50 лет — ресторан «Волга»", viewed: true,
                      photos: 74, docs: 4, onShift: 0)
            ])
        ]
    }

    func calendar(from: Date, to: Date) async -> [CalendarDayDTO]? {
        [
            CalendarDayDTO(date: "2026-08-17", total: 2, viewed: 0, new: 2),
            CalendarDayDTO(date: "2026-08-16", total: 1, viewed: 1, new: 0),
            CalendarDayDTO(date: "2026-08-15", total: 3, viewed: 2, new: 1),
            CalendarDayDTO(date: "2026-08-14", total: 1, viewed: 1, new: 0),
            CalendarDayDTO(date: "2026-08-12", total: 2, viewed: 2, new: 0)
        ]
    }

    func day(_ date: String) async -> [DashEventDTO]? {
        [event(4102, "Конференция «Логистика 2026» — Крокус Экспо", viewed: false,
                     photos: 24, docs: 2, onShift: 3)]
    }

    func markViewed(dealId: String) async {}

    func allShifts(from: Date?, to: Date?) async -> [ShiftRowDTO]? {
        try? await Task.sleep(for: .milliseconds(300))
        return [
            shift(1024, "Никитин Алексей Сергеевич", 4102, "Конференция «Логистика 2026»",
                  "АРТ", "senior", "2026-08-17T07:28:00Z", nil),
            shift(1090, "Ковалёв Игорь Павлович", 4102, "Конференция «Логистика 2026»",
                  "АРТ", "member", "2026-08-17T06:55:00Z", "2026-08-17T15:10:00Z"),
            shift(1118, "Гусев Артём", 4102, "Конференция «Логистика 2026»",
                  "АРТ", "storekeeper", "2026-08-17T08:05:00Z", nil),
            shift(1077, "Петров Дмитрий", 4098, "Свадьба Королёвых — Loft Hall",
                  "А+", "member", "2026-08-16T10:02:00Z", "2026-08-16T23:40:00Z"),
            shift(1103, "Ёлкина Марина Андреевна", 4098, "Свадьба Королёвых — Loft Hall",
                  "А+", "member", "2026-08-16T08:15:00Z", "2026-08-16T19:05:00Z")
        ]
    }

    func eventShifts(dealId: String) async -> [ShiftRowDTO]? {
        let rows = await allShifts(from: nil, to: nil) ?? []
        return rows.filter { String($0.event_id) == dealId }
    }

    /// Карточка мероприятия в сводке. Числа не бутафория: по ним экран
    /// показывает, сколько снимков в отчёте, сколько бумаг и кто ещё на смене.
    private func event(_ id: Int, _ name: String, viewed: Bool,
                       photos: Int, docs: Int, onShift: Int) -> DashEventDTO {
        DashEventDTO(id: id, name: name, viewed: viewed, photos_restricted: false,
                     admins: [DashAdminDTO(worker_id: 1050, fio: "Смирнова Ольга Ивановна")],
                     report_photos: (0..<photos).map { i in
                         let url = MockData.demoPhoto(i)?.absoluteString
                         return ReportPhotoDTO(thumb: url, full: url)
                     },
                     claims: nil,
                     docs: (0..<docs).map {
                         DocumentDTO(id: $0, type: "act", title: "Акт приёма оборудования",
                                     file_name: "akt-\(id)-\($0).pdf", file_size: 302_000,
                                     file_url: nil, download_url: nil, body: nil,
                                     sent_to_tony: $0 == 0, created_at: nil)
                     },
                     checkins: (0..<onShift).map {
                         CheckinDTO(worker_id: 1024 + $0, fio: ["Никитин А. С.", "Ковалёв И. П.", "Гусев А."][$0 % 3],
                                    role: "member", checked_at: "2026-08-17T07:28:00Z", finished_at: nil,
                                    geo_lat: 55.826, geo_lng: 37.392, finish_lat: nil, finish_lng: nil,
                                    opened_by: nil, closed_by: nil,
                                    edited_by: nil, edited_at: nil, edited_what: nil, photo_url: nil)
                     })
    }

    private func shift(_ workerId: Int, _ fio: String, _ eventId: Int, _ eventName: String,
                       _ company: String, _ role: String,
                       _ from: String, _ to: String?) -> ShiftRowDTO {
        ShiftRowDTO(worker_id: workerId, fio: fio, event_id: eventId, event_name: eventName,
                    company_name: company, role: role, checked_at: from, finished_at: to,
                    geo_lat: 55.826, geo_lng: 37.392, opened_by: nil, closed_by: nil,
                    edited_by: nil, edited_at: nil, edited_what: nil)
    }
}
