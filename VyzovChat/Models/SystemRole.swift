import SwiftUI

/// Роль сотрудника в системе (`workers.role`) — что ему доступно вне конкретного чата.
///
/// С 4 августа 2026 (миграция сервера 00044) **права даёт только роль**: отдельной
/// галочки «полные права администратора» больше нет, `is_admin` сервер считает сам
/// (`owner`/`leader`) и присланное значение игнорирует. Поэтому в карточке сотрудника
/// выбирается именно роль, а не набор флагов.
enum SystemRole: String, CaseIterable, Identifiable {
    case worker
    case curator
    case implementer
    case leader
    case owner

    var id: String { rawValue }

    init(_ raw: String?) {
        self = SystemRole(rawValue: raw ?? "") ?? .worker
    }

    var title: String {
        switch self {
        case .worker:      return "Работник"
        case .curator:     return "Куратор"
        case .implementer: return "Реализатор"
        case .leader:      return "Руководитель"
        case .owner:       return "Админ"
        }
    }

    var hint: String {
        switch self {
        case .worker:      return "Свои мероприятия и чаты"
        case .curator:     return "Работник + зовёт подрядчиков по ссылке туда, где сам состоит"
        case .implementer: return "Хозяин своей компании: её чаты, люди, дашборд и смены"
        case .leader:      return "Всё, что у админа; входит сразу на дашборд"
        case .owner:       return "Всё: мероприятия, люди, роли, дашборд, смены, Диск и Фотобанк"
        }
    }

    /// Полные права. Считаем так же, как сервер, — чтобы список сотрудников
    /// рисовал плашку «админ» ровно там, где её нарисовал бы веб.
    var isAdmin: Bool { self == .owner || self == .leader }

    /// Реализатору нужна компания: без неё он «хозяин» пустого множества чатов.
    var needsCompany: Bool { self == .implementer }

    var color: Color {
        switch self {
        case .owner, .leader: return Theme.accent
        case .implementer:    return Theme.warning
        case .curator:        return Theme.success
        case .worker:         return Theme.textSecondary
        }
    }
}
