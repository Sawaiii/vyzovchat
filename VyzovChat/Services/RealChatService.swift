import Foundation

/// Реальные чаты и история сообщений из API Vyzov Chat.
/// Отправка идёт только через сокет (`RealtimeService`); здесь — чтение.
final class RealChatService: ChatServicing {

    /// Кэш компаний: в мероприятии приходит только `company_id`, а показать надо название.
    private static var companiesById: [Int: String] = [:]

    private func loadCompanies() async {
        guard Self.companiesById.isEmpty,
              let list = try? await APIClient.shared.get("/api/companies", as: [CompanyDTO].self) else { return }
        Self.companiesById = Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Чаты мероприятий

    /// Быстрая загрузка списка: события + счётчики. Превью последних сообщений
    /// подтягиваются отдельно, чтобы список появлялся сразу.
    func fetchChats(for user: User) async -> [Chat] {
        await loadCompanies()
        do {
            async let eventsReq = APIClient.shared.get("/api/events", as: [EventDTO].self)
            async let unreadReq = APIClient.shared.get("/api/unread", as: UnreadDTO.self)
            let events = try await eventsReq
            let unread = try? await unreadReq
            // Комнаты сокета явные: без join сервер не пришлёт ни одного сообщения
            // по мероприятию, и лента будет молчать до перезахода.
            RealtimeService.shared.joinEvents(events.map(\.id))
            // Порядок сервера запоминаем: у мероприятия без сообщений даты нет,
            // и без этой опоры список тасовался бы при каждом обновлении.
            return events.enumerated().map { index, ev in
                var chat = Chat(event: ev,
                                unread: unread?.events[String(ev.id)] ?? 0,
                                companyName: ev.company_id.flatMap { Self.companiesById[$0] })
                chat.serverOrder = index
                return chat
            }
        } catch {
            return []
        }
    }

    /// Последнее сообщение чата — для превью в списке (подгружается фоном).
    func lastMessage(for chat: Chat) async -> Message? {
        if chat.isDirect {
            return await fetchDMMessages(otherId: chat.otherUserId ?? "")?.last
        }
        return await fetchMessages(chatId: chat.id)?.last
    }

    // MARK: - Личные чаты (ЛС)

    /// Сервер отдаёт готовые карточки переписок — с последним сообщением
    /// и счётчиком, отдельный запрос за непрочитанным здесь не нужен.
    func fetchDMChats(for user: User) async -> [Chat] {
        do {
            let threads = try await APIClient.shared.get("/api/dm/threads", as: [DMThreadDTO].self)
            // Сервер отдаёт переписки от свежих — сохраняем этот порядок.
            return threads.enumerated().map { index, thread in
                var chat = Chat(thread: thread)
                chat.serverOrder = index
                return chat
            }
        } catch {
            return []
        }
    }

    // MARK: - Сообщения

    func fetchMessages(chatId: String) async -> [Message]? {
        await fetchMessages(chatId: chatId, topicId: nil)
    }

    /// История темы: без topic_id сервер отдаёт канал «Общий».
    /// `nil` при сбое — иначе неудачный запрос выглядел бы как «сообщений нет»
    /// и стирал уже показанную ленту.
    func fetchMessages(chatId: String, topicId: Int?) async -> [Message]? {
        let eventId = chatId.replacingOccurrences(of: "chat-", with: "")
        var path = "/api/events/\(eventId)/messages"
        if let topicId { path += "?topic_id=\(topicId)" }
        guard let dtos = try? await APIClient.shared.get(path, as: [MessageDTO].self) else { return nil }
        return dtos.map { Message(dto: $0) }
    }

    /// Окно ленты вокруг найденного сообщения: переход из поиска должен работать
    /// и для старых сообщений, которых нет в последней сотне.
    func fetchMessages(chatId: String, topicId: Int?, around messageId: Int) async -> [Message]? {
        let eventId = chatId.replacingOccurrences(of: "chat-", with: "")
        var path = "/api/events/\(eventId)/messages?around=\(messageId)"
        if let topicId { path += "&topic_id=\(topicId)" }
        guard let dtos = try? await APIClient.shared.get(path, as: [MessageDTO].self) else { return nil }
        return dtos.map { Message(dto: $0) }
    }

    /// Поиск по сообщениям мероприятия — сразу по всем видимым темам.
    /// Сервер отвечает пустым списком на запрос короче двух символов.
    func searchMessages(dealId: String, query: String) async -> [Message] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        do {
            let dtos = try await APIClient.shared.get("/api/events/\(dealId)/search?q=\(q)", as: [MessageDTO].self)
            return dtos.map { Message(dto: $0) }
        } catch {
            return []
        }
    }

    // MARK: - Закреплённые сообщения

    /// Закрепы вкладки мероприятия: свои у «Общего» и у каждой темы.
    func pinnedMessages(dealId: String, topicId: Int?) async -> [Message] {
        let key = topicId.map(String.init) ?? "main"
        let dtos = try? await APIClient.shared.getOptional(
            "/api/events/\(dealId)/pin?topic_id=\(key)", as: [MessageDTO].self)
        return (dtos ?? []).map { Message(dto: $0) }
    }

    /// Закрепы личной переписки. Ключ переписки сервер собирает сам — от нас
    /// нужен только собеседник.
    func pinnedDMMessages(peerId: String) async -> [Message] {
        let dtos = try? await APIClient.shared.getOptional("/api/dm/\(peerId)/pin", as: [MessageDTO].self)
        return (dtos ?? []).map { Message(dto: $0) }
    }

    /// В мероприятии закрепляет админ чата, в личной переписке — любой из двоих.
    /// В ответ приходит весь список закрепов чата, а не одно сообщение.
    func pin(messageId: String) async throws -> [Message] {
        let dtos = try await APIClient.shared.post("/api/messages/\(messageId)/pin",
                                                   json: nil, as: [MessageDTO].self)
        return dtos.map { Message(dto: $0) }
    }

    func unpin(messageId: String) async throws -> [Message] {
        let dtos = try await APIClient.shared.delete("/api/messages/\(messageId)/pin",
                                                     as: [MessageDTO].self)
        return dtos.map { Message(dto: $0) }
    }

    // MARK: - Темы

    func fetchTopics(dealId: String) async -> [TopicDTO] {
        (try? await APIClient.shared.get("/api/events/\(dealId)/topics", as: [TopicDTO].self)) ?? []
    }

    /// Тема, открытая всем. Приватные (по ролям и поимённо) настраиваются отдельно
    /// через `PATCH /api/topics/{id}/access`.
    func createTopic(dealId: String, name: String) async throws -> TopicDTO {
        try await APIClient.shared.post(
            "/api/events/\(dealId)/topics",
            json: CreateTopicRequest(name: name, visibility: "all", roles: [], members: []),
            as: TopicDTO.self)
    }

    func deleteTopic(id: Int) async throws {
        _ = try await APIClient.shared.delete("/api/topics/\(id)", as: OKDTO.self)
    }

    /// Непрочитанное по лентам мероприятия: ключ "main" — «Общий», иначе id темы.
    func topicUnread(dealId: String) async -> [String: Int] {
        guard let raw = try? await APIClient.shared.get("/api/events/\(dealId)/topic-unread",
                                                        as: [String: TopicUnreadDTO].self) else { return [:] }
        return raw.mapValues(\.count)
    }

    /// Отметки прочтения шлёт `ChatViewModel` — у «Общего» и подтем свои ключи
    /// (`e<id>:main` / `t<id>`), отдельного эндпоинта под темы на сервере нет.
    func markTopicRead(dealId: String, topicId: Int?, lastRead: Int) async {
        let key = topicId.map { "t\($0)" } ?? "e\(dealId):main"
        _ = try? await APIClient.shared.post("/api/reads",
                                             json: ReadRequest(chatKey: key, lastRead: lastRead),
                                             as: OKDTO.self)
    }

    func fetchDMMessages(otherId: String) async -> [Message]? {
        guard let dtos = try? await APIClient.shared.get("/api/dm/\(otherId)/messages",
                                                          as: [MessageDTO].self) else { return nil }
        return dtos.map { Message(dto: $0, chatId: "dm-\(otherId)") }
    }

    // Отправка — только через сокет (RealtimeService). Локальное эхо для совместимости.
    func send(text: String, chatId: String, senderId: String) async -> Message {
        Message(id: "local-\(UUID().uuidString)", chatId: chatId, senderId: senderId,
                text: text, attachments: [], sentAt: Date(), kind: .text)
    }
    func sendPhotos(_ count: Int, chatId: String, senderId: String) async -> Message {
        Message(id: "local-\(UUID().uuidString)", chatId: chatId, senderId: senderId,
                text: nil, attachments: [], sentAt: Date(), kind: .photo)
    }
}
