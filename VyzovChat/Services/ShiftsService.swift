import Foundation

/// Смены на мероприятии: «я на месте» и «завершить смену».
///
/// Координаты обязательны — отметка подтверждает, что человек действительно на
/// площадке, и без гео сервер отвечает `geo_required`. Если телефон не отдаёт
/// геопозицию (нет разрешения, сел GPS), смену за сотрудника открывает админ чата
/// вручную — тогда в отметке сохраняется, кто её проставил.
protocol ShiftsServicing {
    /// Смены мероприятия. Обычный сотрудник видит только свою,
    /// куратор — ещё и тех, кого позвал сам; админ чата — все.
    func shifts(dealId: String) async -> [CheckinDTO]
    /// Открыть смену. Селфи с площадки обязательно: геопозицию в телефоне подменить
    /// легко, снимок на фоне монтажа — нет. `photoKey` — ключ из presign.
    func checkIn(dealId: String, lat: Double, lng: Double, photoKey: String) async throws -> CheckinDTO
    func checkOut(dealId: String, lat: Double, lng: Double) async throws -> CheckinDTO
    /// Отметка за сотрудника (админ чата). Геометки здесь нет и быть не может —
    /// админ не на месте сотрудника.
    func checkInFor(dealId: String, workerId: String) async throws -> CheckinDTO
    func checkOutFor(dealId: String, workerId: String) async throws -> CheckinDTO

    // Правки задним числом — только руководству (`me_rights.shift_cancel`).
    /// Убрать смену целиком: открыли по ошибке или не тому человеку.
    func cancelShift(dealId: String, workerId: String) async throws
    /// Снять завершение: человек вернулся на площадку.
    func reopenShift(dealId: String, workerId: String) async throws -> CheckinDTO
    /// Проставить время смены руками. nil-поле не трогаем.
    func setShiftTimes(dealId: String, workerId: String,
                       checkedAt: Date?, finishedAt: Date?) async throws -> CheckinDTO
}

/// Ошибки смены с понятным человеку текстом.
enum ShiftError: LocalizedError {
    case geoUnavailable
    case notCheckedIn
    case warehouse
    case notMember
    case photoRequired
    case badPhoto

    var errorDescription: String? {
        switch self {
        case .geoUnavailable:
            return "Не удалось определить геопозицию. Разрешите доступ к геоданным в настройках — без координат отметить смену нельзя."
        case .notCheckedIn: return "Смена ещё не открыта"
        case .warehouse:    return "Складу смены не отмечают"
        case .notMember:    return "Вы не в составе этого мероприятия"
        case .photoRequired:
            return "Нужно селфи с площадки: без снимка отметить смену нельзя."
        case .badPhoto:
            return "Снимок не подошёл. Сделайте фото заново."
        }
    }

    /// Разбор кода ошибки сервера в понятный текст.
    static func from(_ error: Error) -> Error {
        guard case let APIError.http(_, message) = error, let message else { return error }
        switch message {
        case "geo_required":             return ShiftError.geoUnavailable
        case "photo_required":           return ShiftError.photoRequired
        case "bad_photo":                return ShiftError.badPhoto
        case "not_checked_in":           return ShiftError.notCheckedIn
        case "no_checkin_for_warehouse": return ShiftError.warehouse
        case "not_member":               return ShiftError.notMember
        default:                         return error
        }
    }
}

private struct GeoRequest: Encodable {
    let lat: Double
    let lng: Double
    /// Селфи с площадки — только при открытии смены.
    var photo_key: String? = nil
}

final class RealShiftsService: ShiftsServicing {
    func shifts(dealId: String) async -> [CheckinDTO] {
        // Отдельного эндпоинта нет — смены приходят в карточке мероприятия,
        // уже отфильтрованные сервером по правам смотрящего.
        guard let dto = try? await APIClient.shared.get("/api/events/\(dealId)", as: EventDetailsDTO.self) else { return [] }
        return dto.checkins ?? []
    }

    func checkIn(dealId: String, lat: Double, lng: Double, photoKey: String) async throws -> CheckinDTO {
        try await post("/api/events/\(dealId)/checkin",
                       body: GeoRequest(lat: lat, lng: lng, photo_key: photoKey))
    }

    func checkOut(dealId: String, lat: Double, lng: Double) async throws -> CheckinDTO {
        try await post("/api/events/\(dealId)/checkout", body: GeoRequest(lat: lat, lng: lng))
    }

    func checkInFor(dealId: String, workerId: String) async throws -> CheckinDTO {
        try await post("/api/events/\(dealId)/members/\(workerId)/checkin", body: EmptyBody())
    }

    func checkOutFor(dealId: String, workerId: String) async throws -> CheckinDTO {
        try await post("/api/events/\(dealId)/members/\(workerId)/checkout", body: EmptyBody())
    }

    func cancelShift(dealId: String, workerId: String) async throws {
        do {
            _ = try await APIClient.shared.delete("/api/events/\(dealId)/members/\(workerId)/checkin",
                                                  as: OKDTO.self)
        } catch {
            throw ShiftError.from(error)
        }
    }

    func reopenShift(dealId: String, workerId: String) async throws -> CheckinDTO {
        try await post("/api/events/\(dealId)/members/\(workerId)/reopen", body: EmptyBody())
    }

    func setShiftTimes(dealId: String, workerId: String,
                       checkedAt: Date?, finishedAt: Date?) async throws -> CheckinDTO {
        // Время шлём в ISO-8601 с зоной: сервер разбирает его как time.Time,
        // а «просто HH:mm» превратилось бы в чужой часовой пояс.
        struct TimesRequest: Encodable {
            let checked_at: String?
            let finished_at: String?
        }
        let iso = ISO8601DateFormatter()
        let body = TimesRequest(checked_at: checkedAt.map(iso.string(from:)),
                                finished_at: finishedAt.map(iso.string(from:)))
        do {
            return try await APIClient.shared.patch("/api/events/\(dealId)/members/\(workerId)/checkin",
                                                     json: body, as: CheckinDTO.self)
        } catch {
            throw ShiftError.from(error)
        }
    }

    private func post(_ path: String, body: Encodable) async throws -> CheckinDTO {
        do {
            return try await APIClient.shared.post(path, json: body, as: CheckinDTO.self)
        } catch {
            throw ShiftError.from(error)
        }
    }
}

final class MockShiftsService: ShiftsServicing {
    func shifts(dealId: String) async -> [CheckinDTO] { [] }
    func checkIn(dealId: String, lat: Double, lng: Double, photoKey: String) async throws -> CheckinDTO {
        throw ShiftError.geoUnavailable
    }
    func checkOut(dealId: String, lat: Double, lng: Double) async throws -> CheckinDTO { throw ShiftError.geoUnavailable }
    func checkInFor(dealId: String, workerId: String) async throws -> CheckinDTO { throw ShiftError.notMember }
    func checkOutFor(dealId: String, workerId: String) async throws -> CheckinDTO { throw ShiftError.notMember }
    func cancelShift(dealId: String, workerId: String) async throws {}
    func reopenShift(dealId: String, workerId: String) async throws -> CheckinDTO { throw ShiftError.notCheckedIn }
    func setShiftTimes(dealId: String, workerId: String,
                       checkedAt: Date?, finishedAt: Date?) async throws -> CheckinDTO {
        throw ShiftError.notCheckedIn
    }
}
