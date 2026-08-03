import SwiftUI

/// Роль в мероприятии (`event_workers.role`). Ключи серверные, подписи наши.
///
/// Ролей стало пять, и они не про «главнее — не главнее», а про то, кто какой
/// кусок работы закрывает: кладовщик отмечает погрузку и приёмку, старший —
/// середину, наблюдатель просто смотрит. Права считает сервер и присылает
/// готовым набором (`me_rights`); здесь только то, как роль называется и
/// выглядит.
enum EventRole: String, CaseIterable, Identifiable {
    case admin
    case senior
    case member
    case observer
    case storekeeper

    var id: String { rawValue }

    init(_ raw: String?) {
        self = EventRole(rawValue: raw ?? "") ?? .member
    }

    var title: String {
        switch self {
        case .admin:       return "Админ чата"
        case .senior:      return "Старший"
        case .member:      return "Участник"
        case .observer:    return "Наблюдатель"
        case .storekeeper: return "Кладовщик"
        }
    }

    /// Чем эта роль отличается — подсказка в списке выбора.
    var hint: String {
        switch self {
        case .admin:       return "Всё: состав, темы, закрепы, этапы, отчёт"
        case .senior:      return "Приезд, готовность, демонтаж, документы, претензии"
        case .member:      return "Читает, пишет, шлёт фото, отмечает смену"
        case .observer:    return "Как участник, но без отметки смены"
        case .storekeeper: return "Погрузка и приёмка, чеклист оборудования"
        }
    }

    var color: Color {
        switch self {
        case .admin:       return Theme.accent
        case .senior:      return Theme.success
        case .member:      return Theme.textSecondary
        case .observer:    return Theme.textSecondary
        case .storekeeper: return Theme.warning
        }
    }

    var icon: String {
        switch self {
        case .admin:       return "star.fill"
        case .senior:      return "person.fill.checkmark"
        case .member:      return "person.fill"
        case .observer:    return "eye"
        case .storekeeper: return "shippingbox.fill"
        }
    }

    /// Участник — роль по умолчанию, её плашку в списке не рисуем: это шум.
    var showsChip: Bool { self != .member }
}

/// Плашка роли в списках состава.
struct RoleChip: View {
    let role: EventRole

    var body: some View {
        Label(role.title, systemImage: role.icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(role.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(role.color.opacity(0.16), in: Capsule())
    }
}

/// Этап мероприятия. Порядок строгий: перепрыгнуть нельзя, снять можно только
/// последний отмеченный — иначе в цепочке появляется дыра вида «приёмка есть,
/// погрузки нет».
enum EventStage: String, CaseIterable, Identifiable {
    case load, mount, ready, dismantle, accept

    var id: String { rawValue }

    /// Названия те же, что сервер пишет в чат («закрыл(а) этап «Приём»») —
    /// иначе полоса этапов и строка о ней в ленте называют одно разными словами.
    var title: String {
        switch self {
        case .load:      return "Погрузка"
        case .mount:     return "Приезд/монтаж"
        case .ready:     return "Готовность"
        case .dismantle: return "Демонтаж"
        case .accept:    return "Приём"
        }
    }

    /// Кто закрывает этап. Погрузку и приёмку — только кладовщик: оборудование
    /// принимает и выдаёт склад, и подменить его не может даже админ чата.
    var owner: String {
        checklist == nil ? "админ чата или старший" : "кладовщик"
    }

    /// У погрузки и приёмки есть свой чеклист оборудования — без него этап
    /// не закрыть.
    var checklist: EquipCheckKind? {
        switch self {
        case .load:   return .loaded
        case .accept: return .returned
        default:      return nil
        }
    }
}
