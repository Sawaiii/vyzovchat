import Foundation

/// Чаты «без звука».
///
/// Мероприятия и темы глушатся на сервере — иначе с телефона выключил, а с
/// компьютера всё равно звенит. Личные переписки сервер глушить не умеет, они
/// остаются на этом устройстве.
///
/// Снимок держим локально и обновляем после каждого изменения: проверка при
/// входящем сообщении должна быть мгновенной и без сети.
enum MuteStore {
    private static let dmKey = "vyzovchat.mutedChats"
    private static let eventsKey = "vyzovchat.mutedEvents"
    private static let topicsKey = "vyzovchat.mutedTopics"

    /// id мероприятий без звука.
    private(set) static var events: Set<Int> = Set(
        UserDefaults.standard.array(forKey: eventsKey) as? [Int] ?? []
    ) {
        didSet { UserDefaults.standard.set(Array(events), forKey: eventsKey) }
    }

    /// Темы без звука, ключ «мероприятие:тема».
    private(set) static var topics: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: topicsKey) ?? []
    ) {
        didSet { UserDefaults.standard.set(Array(topics), forKey: topicsKey) }
    }

    /// Личные переписки — только на этом устройстве.
    private(set) static var directs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: dmKey) ?? []
    ) {
        didSet { UserDefaults.standard.set(Array(directs), forKey: dmKey) }
    }

    static func topicKey(event: Int, topic: Int) -> String { "\(event):\(topic)" }

    /// id мероприятия из id чата («chat-16» → 16); у ЛС его нет.
    static func eventId(fromChatId chatId: String) -> Int? {
        guard chatId.hasPrefix("chat-") else { return nil }
        return Int(chatId.dropFirst("chat-".count))
    }

    static func isMuted(_ chatId: String) -> Bool {
        guard let eventId = eventId(fromChatId: chatId) else { return directs.contains(chatId) }
        return events.contains(eventId)
    }

    /// Заглушено ли конкретное сообщение: у мероприятия могут быть заглушены
    /// и оно целиком, и отдельная тема.
    static func isMuted(_ message: Message) -> Bool {
        guard let eventId = eventId(fromChatId: message.chatId) else {
            return directs.contains(message.chatId)
        }
        if events.contains(eventId) { return true }
        guard let topic = message.topicId else { return false }
        return topics.contains(topicKey(event: eventId, topic: topic))
    }

    static func isMuted(event: Int, topic: Int?) -> Bool {
        if events.contains(event) { return true }
        guard let topic else { return false }
        return topics.contains(topicKey(event: event, topic: topic))
    }

    /// Забрать список с сервера. Локальные ЛС не трогаем — сервер про них не знает.
    static func sync() async {
        guard !AppConfig.useMockData,
              let list = try? await APIClient.shared.get("/api/mutes", as: [MuteDTO].self) else { return }
        var nextEvents: Set<Int> = []
        var nextTopics: Set<String> = []
        for item in list {
            if let topic = item.topic_id {
                nextTopics.insert(topicKey(event: item.event_id, topic: topic))
            } else {
                nextEvents.insert(item.event_id)
            }
        }
        events = nextEvents
        topics = nextTopics
    }

    /// Переключить звук у мероприятия или темы. Возвращает новое состояние;
    /// при отказе сервера — прежнее, чтобы галочка не врала.
    @discardableResult
    static func setMuted(_ muted: Bool, event: Int, topic: Int? = nil) async -> Bool {
        do {
            _ = try await APIClient.shared.post("/api/mutes",
                                                json: SetMuteRequest(event_id: event, topic_id: topic, muted: muted),
                                                as: OKDTO.self)
        } catch {
            return isMuted(event: event, topic: topic)
        }
        apply(muted, event: event, topic: topic)
        return muted
    }

    private static func apply(_ muted: Bool, event: Int, topic: Int?) {
        if let topic {
            let key = topicKey(event: event, topic: topic)
            if muted { topics.insert(key) } else { topics.remove(key) }
        } else {
            if muted { events.insert(event) } else { events.remove(event) }
        }
    }

    /// Личная переписка: сервер её глушить не умеет, храним у себя.
    @discardableResult
    static func toggleDirect(_ chatId: String) -> Bool {
        if directs.contains(chatId) { directs.remove(chatId); return false }
        directs.insert(chatId)
        return true
    }

    /// Переключение из списка чатов: мероприятие уходит на сервер, ЛС остаётся здесь.
    @discardableResult
    static func toggle(_ chatId: String) async -> Bool {
        guard let event = eventId(fromChatId: chatId) else { return toggleDirect(chatId) }
        return await setMuted(!events.contains(event), event: event)
    }
}
