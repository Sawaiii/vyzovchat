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
    /// …и весь набор компаний, которые он ведёт (отмечает сам в своей карточке).
    var companyIds: [Int] = []
    /// Уволен: в списках его нет, войти не может, история цела.
    var isArchived: Bool = false
    var lastSeen: Date? = nil   // «последний раз в сети»
    /// Роль в конкретном мероприятии: admin | senior | member | observer | storekeeper
    var eventRole: String? = nil

    /// Реализатор — полный доступ к Диску/Фотобанку и к чатам своей компании.
    var isImplementer: Bool { globalRole == "implementer" }

    /// Гость (с 14 августа 2026): смотрит систему целиком, но не меняет ничего.
    /// Сервер держит запрет сам — на любой изменяющий запрос отвечает
    /// `403 guest_readonly`, а в сокете принимает от гостя только `join`.
    /// Клиенту это нужно, чтобы не показывать кнопки, которые всё равно откажут.
    var isGuest: Bool { globalRole == "guest" }

    /// Пускать ли в разделы «Люди», «Журнал», дашборд. Гостю их показывают
    /// намеренно — весь смысл роли в том, чтобы увидеть систему; менять он там
    /// ничего не может, потому что все кнопки правки висят на `isAdmin`.
    var canViewAdmin: Bool { isAdmin || isGuest }

    /// Склады, за которые человек отвечает (справочник Tony). В чеклисте загрузки
    /// его склад раскрыт и стоит первым: позиций в заказе бывает под двадцать,
    /// а грузит он только свои.
    var warehouseIds: [String] = []

    /// Не заполнены почта и телефон. Без них человека не найти вне чата и не
    /// восстановить ему пароль — поэтому в карточке и на аватарке висит знак.
    var contactsMissing: Bool {
        phone.trimmingCharacters(in: .whitespaces).isEmpty
            || (email ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Права уровня админа чата внутри мероприятия.
    ///
    /// Склад сюда больше не входит: сервер с 4 августа 2026 считает админом чата
    /// только роль `admin` — кладовщик закрывает свои этапы, но чатом не правит.
    var isEventAdmin: Bool { eventRole == "admin" }

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
