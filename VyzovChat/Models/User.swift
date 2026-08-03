import Foundation

/// Пользователь (сотрудник-выездник). На реальном бэкенде ключ — `id` (== workerId),
/// имя хранится одной строкой `fio`, вход по `login`.
struct User: Identifiable, Codable, Equatable, Hashable {
    let id: String            // внутренний id (== workerId)
    let workerId: String
    var lastName: String
    var firstName: String
    var middleName: String?
    var phone: String
    var position: String      // должность
    var department: String?
    var avatarURL: URL?

    // Поля реального API (заполняются при маппинге из WorkerDTO)
    var fio: String = ""
    var login: String = ""
    var email: String? = nil
    var isAdmin: Bool = false
    /// Руководитель — стартует на дашборде вместо списка чатов.
    var isLeader: Bool = false
    /// Куратор — может звать подрядчиков по ссылке.
    var isCurator: Bool = false
    /// Глобальная роль: worker | leader | owner | implementer | curator
    var globalRole: String = "worker"
    /// Компания реализатора: он админ всех её мероприятий.
    var companyId: Int? = nil
    var lastSeen: Date? = nil   // «последний раз в сети»
    /// Роль в конкретном мероприятии: admin | senior | member | observer | storekeeper
    var eventRole: String? = nil

    /// Реализатор — полный доступ к Диску/Фотобанку и к чатам своей компании.
    var isImplementer: Bool { globalRole == "implementer" }

    /// Права уровня админа чата внутри мероприятия (склад приравнен к админу).
    var isEventAdmin: Bool { eventRole == "admin" || eventRole == "warehouse" }

    /// ФИО целиком. Предпочитаем цельное `fio` из API, иначе собираем из частей.
    var fullName: String {
        if !fio.isEmpty { return fio }
        return [lastName, firstName, middleName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Краткое имя «Фамилия И.О.»
    var shortName: String {
        let source = fullName
        let parts = source.split(separator: " ")
        guard parts.count >= 2 else { return source }
        var result = String(parts[0])
        if let f = parts[1].first { result += " \(f)." }
        if parts.count >= 3, let m = parts[2].first { result += "\(m)." }
        return result
    }
}
