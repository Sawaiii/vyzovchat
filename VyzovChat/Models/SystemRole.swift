import SwiftUI

/// Роль сотрудника в системе (`workers.role`) — что ему доступно вне конкретного чата.
///
/// С 4 августа 2026 (миграция сервера 00044) **права даёт только роль**: отдельной
/// галочки «полные права администратора» больше нет, `is_admin` сервер считает сам
/// и присланное значение игнорирует. Поэтому в карточке сотрудника выбирается
/// именно роль, а не набор флагов.
///
/// Названия — из `app/web/src/lib/roles.ts` (заказчик переименовал роли 17 августа
/// 2026; ключи в базе прежние). Список тут ПОЛНЫЙ: раньше в нём не было менеджера,
/// подрядчика и склада, и такой человек в карточке показывался «работником» — а при
/// сохранении карточки роль ему и правда меняли на `worker`.
enum SystemRole: String, CaseIterable, Identifiable {
    case worker
    case manager
    case contractor
    case warehouse
    case curator
    case implementer
    case guest
    case leader
    case owner

    var id: String { rawValue }

    init(_ raw: String?) {
        self = SystemRole(rawValue: raw ?? "") ?? .worker
    }

    var title: String {
        switch self {
        case .worker:      return "Выездная команда"
        case .manager:     return "Менеджер проекта"
        case .contractor:  return "Подрядчик"
        case .warehouse:   return "Складская структура"
        case .curator:     return "Координатор проекта"
        case .implementer: return "Отдел реализации"
        case .guest:       return "Гость (только просмотр)"
        case .leader:      return "Управляющий партнёр"
        case .owner:       return "Администратор проекта"
        }
    }

    var hint: String {
        switch self {
        case .worker:      return "Свои мероприятия и чаты"
        case .manager:     return "Права выездной команды; роль — подпись, кто ведёт проект"
        case .contractor:  return "Права выездной команды; подпись «человек со стороны»"
        case .warehouse:   return "Права выездной команды; в чате обычно кладовщик, видит все мероприятия"
        case .curator:     return "Выездная команда + зовёт подрядчиков по ссылке туда, где сам состоит"
        case .implementer: return "Всё, что у админа, кроме удаления мероприятия"
        case .guest:       return "Только просмотр: смотрит систему целиком, ничего не меняет"
        case .leader:      return "Всё, что у админа; входит сразу на дашборд"
        case .owner:       return "Всё: мероприятия, люди, роли, дашборд, смены, Диск и Фотобанк"
        }
    }

    /// Полные права. Считаем так же, как сервер (`adminByRole` в `rights.go`), —
    /// чтобы список сотрудников рисовал плашку «админ» ровно там, где её нарисовал
    /// бы веб. Реализатор добавлен 14 августа 2026: до этого он был хозяином своей
    /// компании, но компания проставлена у двоих из полусотни, и права не работали.
    var isAdmin: Bool { self == .owner || self == .leader || self == .implementer }

    /// Удалить мероприятие: единственное, что не отдали реализатору вместе с
    /// полными правами, — оно уходит со всей перепиской, и обратно её не достать.
    var canDeleteEvent: Bool { self == .owner || self == .leader }

    /// Реализатору нужна компания: без неё он «хозяин» пустого множества чатов.
    var needsCompany: Bool { self == .implementer }

    var color: Color {
        switch self {
        case .owner, .leader:          return Theme.accent
        case .implementer:             return Theme.warning
        case .curator:                 return Theme.success
        case .guest:                   return Theme.textSecondary
        case .manager, .warehouse,
             .contractor, .worker:     return Theme.textSecondary
        }
    }
}
