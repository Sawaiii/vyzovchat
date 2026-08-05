import Foundation

/// Метка мероприятия: название + цвет из словаря организации.
struct ChatTag: Codable, Equatable, Hashable, Identifiable {
    let name: String
    let colorHex: String
    var id: String { name }
}

/// Чат. Бывает двух видов: чат мероприятия (по сделке) и личный (ЛС).
struct Chat: Identifiable, Codable, Equatable, Hashable {
    let id: String                    // "chat-<eventId>" или "dm-<otherId>"
    let dealId: String                // id мероприятия (для чата мероприятия)
    var title: String
    var participantIds: [String]
    var lastMessagePreview: String?
    var lastMessageDate: Date?
    /// Последнее сообщение — моё. Отдельным признаком, а не пометкой прямо в
    /// тексте превью: по тексту список сверяет, то же это сообщение или новое,
    /// и дописанное «Вы: » ломало сверку — строка каждый раз выглядела чужой,
    /// дата сбрасывалась и запрашивалась заново.
    var lastMessageIsMine: Bool = false
    var unreadCount: Int
    var isPhotoReportOpen: Bool

    var isDirect: Bool = false         // личный чат
    var otherUserId: String? = nil     // собеседник в ЛС
    var avatarURL: URL? = nil          // аватар собеседника (для ЛС)
    var isArchived: Bool = false       // чат прошедшего (архивного) мероприятия
    var rawStatus: String = "active"   // active | closed (из БД)
    var reportStatus: String = "none"  // none | sent (из БД)
    var colorHex: String? = nil        // цвет-обои чата (задаёт админ)
    var company: String? = nil         // компания/бренд мероприятия

    /// Я админ этого чата: показывать ли правки мероприятия, состав, темы.
    var isChatAdmin: Bool = false
    /// Моя роль в составе мероприятия (`my_role`) — из списка мероприятий.
    var myRole: String? = nil

    /// Плашка своей роли в списке чатов: «участника» не рисуем — это шум.
    var myRoleChip: EventRole? {
        guard !isDirect, let raw = myRole, !raw.isEmpty else { return nil }
        let role = EventRole(raw)
        return role.showsChip ? role : nil
    }
    /// Метки мероприятия из словаря организации.
    var tags: [ChatTag] = []
    var needsPhoto: Bool = false       // ждём фото с мероприятия
    var needsReport: Bool = false      // ждём отчёт
    var hasDocs: Bool = false          // есть документы (акты)
    var hasClaim: Bool = false         // есть претензия
    var photosRestricted: Bool = false // клиент запретил использовать фото
    /// Место чата в ответе сервера. Нужен как опора сортировки: у мероприятия
    /// без сообщений даты нет вовсе, а сортировка по «нет даты» неустойчива —
    /// список тасовался бы при каждом обновлении.
    var serverOrder: Int = 0
    /// Когда мероприятие начинается и заканчивается — показываем в шапке чата.
    var startsAt: Date? = nil
    var endsAt: Date? = nil
    /// В чате есть непрочитанное упоминание меня через @.
    var hasMention: Bool = false
    /// …или непрочитанный ответ на моё сообщение.
    var hasReply: Bool = false

    /// Статусы мероприятия для бейджей (у ЛС их нет).
    var statusBadges: [(text: String, kind: Deal.StatusKind)] {
        guard !isDirect else { return [] }
        var items: [(String, Deal.StatusKind)] = []
        items.append(rawStatus == "closed" ? ("Завершено", .neutral) : ("Активно", .active))
        items.append(reportStatus == "sent" ? ("Отчёт отправлен", .success) : ("Нет отчёта", .warning))
        if isArchived && rawStatus != "closed" { items.append(("Архив", .neutral)) }
        return items
    }

    // Equatable — синтезированный (по всем полям): иначе SwiftUI не замечает
    // обновление превью/счётчика непрочитанного и не перерисовывает строку.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Порядок в списке: сверху свежие по времени, а всё, о чём времени не знаем, —
    /// в том порядке, в каком отдал сервер (у него мероприятия идут от новых).
    static func byActivity(_ a: Chat, _ b: Chat) -> Bool {
        switch (a.lastMessageDate, b.lastMessageDate) {
        case let (x?, y?): return x == y ? a.serverOrder < b.serverOrder : x > y
        case (_?, nil):    return true
        case (nil, _?):    return false
        case (nil, nil):   return a.serverOrder < b.serverOrder
        }
    }
}
