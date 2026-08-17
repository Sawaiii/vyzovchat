import Foundation

/// Заблокированные люди: их сообщения и вложения не показываются.
///
/// Требование App Store (Guideline 1.2): раз в приложении есть переписка и
/// пользовательские фото, у человека должна быть возможность и пожаловаться,
/// и закрыть от себя того, кто ведёт себя недопустимо. Жалоба уже есть —
/// она уходит организатору мероприятия и разбирается людьми; блокировка
/// нужна как немедленное средство, работающее без чужого участия.
///
/// Список локальный, как и «без звука» у личных переписок: блокировка — это
/// «я не хочу это видеть», а не наказание. Скрывать человека сразу на всех
/// устройствах здесь не нужно, зато работает мгновенно и без сети.
enum BlockStore {
    private static let key = "vyzovchat.blockedUsers"

    /// id сотрудника → как его звали в момент блокировки.
    ///
    /// Имя храним рядом с id, чтобы список «Заблокированные» в профиле можно
    /// было показать без единого запроса: заблокированный человек мог уже уйти
    /// из всех общих мероприятий, и его карточка нам больше не приходит.
    private(set) static var blockedNames: [String: String] = loadStored() {
        didSet {
            UserDefaults.standard.set(blockedNames, forKey: key)
            NotificationCenter.default.post(name: .blockListChanged, object: nil)
        }
    }

    private static func loadStored() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static var blocked: Set<String> { Set(blockedNames.keys) }

    static func isBlocked(_ userId: String) -> Bool { blockedNames[userId] != nil }

    /// Себя заблокировать нельзя — иначе собственные сообщения исчезнут из ленты.
    @discardableResult
    static func toggle(_ userId: String, name: String, currentUserId: String) -> Bool {
        guard userId != currentUserId else { return false }
        if blockedNames[userId] != nil {
            blockedNames[userId] = nil
            return false
        }
        blockedNames[userId] = name
        return true
    }

    static func unblock(_ userId: String) { blockedNames[userId] = nil }
}

extension Notification.Name {
    /// Список блокировок изменился — ленты пересобираются.
    static let blockListChanged = Notification.Name("vyzovchat.blockListChanged")
}
