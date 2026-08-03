import SwiftUI

@MainActor
final class ChatListViewModel: ObservableObject {
    @Published var eventChats: [Chat] = []
    @Published var dmChats: [Chat] = []
    @Published var isLoading = true

    private var didLoadOnce = false
    private var previewTask: Task<Void, Never>?
    /// Идёт загрузка — не запускаем вторую параллельно (частые pull-to-refresh
    /// подряд иначе гоняли конкурирующие запросы, часть падала в пустой ответ,
    /// и список мигал/пропадал).
    private var isRefreshing = false
    /// Когда последний раз перезагружались из-за переподключения сокета.
    private var lastReconnectReload: Date?

    var activeEventChats: [Chat] { eventChats.filter { !$0.isArchived } }
    var archivedEventChats: [Chat] { eventChats.filter { $0.isArchived } }

    /// Перезагрузка по переподключению сокета — не чаще, чем раз в 15 секунд.
    ///
    /// На площадке связь рвётся постоянно, сокет поднимается и падает пачками, и
    /// каждое переподключение тянуло за собой полную перезагрузку списка. Свежесть
    /// от этого не растёт (живые сообщения и так приходят в сокет), а телефон и
    /// сервер получают шторм запросов ровно тогда, когда связь и без того плохая.
    func reloadAfterReconnect(session: AppSession) async {
        let now = Date()
        if let last = lastReconnectReload, now.timeIntervalSince(last) < 15 { return }
        lastReconnectReload = now
        await load(session: session)
    }

    func load(session: AppSession) async {
        guard let user = session.currentUser else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if !didLoadOnce { isLoading = true }   // скелетон только при первой загрузке

        // Быстрая фаза: списки появляются сразу (без ожидания истории каждого чата).
        async let events = session.chats.fetchChats(for: user)
        async let dms = session.chats.fetchDMChats(for: user)
        // «Без звука» живёт на сервере — забираем вместе со списками, чтобы
        // заглушённое с компьютера не звенело на телефоне.
        async let mutes: Void = MuteStore.sync()
        let (ev, dm, _) = await (events, dms, mutes)
        // Сливаем со старыми: быстрая фаза приходит без превью, и без слияния
        // список на миг терял текст последнего сообщения и даты.
        eventChats = merged(ev, with: eventChats)
        dmChats = merged(dm, with: dmChats)
        isLoading = false
        didLoadOnce = true
        // Метки упоминаний и ответов приходят отдельной сводкой.
        await refreshUnread(session: session)

        // Вторая фаза: превью последних сообщений подтягиваются фоном.
        previewTask?.cancel()
        previewTask = Task { await loadPreviews(session: session) }
    }

    /// Мы прочитали чат — обнуляем его счётчик мгновенно.
    func markChatRead(_ chatId: String) {
        if let i = eventChats.firstIndex(where: { $0.id == chatId }), eventChats[i].unreadCount != 0 {
            eventChats[i].unreadCount = 0
        }
        if let i = dmChats.firstIndex(where: { $0.id == chatId }), dmChats[i].unreadCount != 0 {
            dmChats[i].unreadCount = 0
        }
    }

    /// Пришло новое сообщение — сразу двигаем превью и счётчик нужного чата.
    func applyIncoming(_ message: Message) {
        let isMine = message.senderId == RealtimeService.shared.currentUserId
        let isOpen = RealtimeService.shared.activeChatId == message.chatId

        func update(_ list: inout [Chat]) -> Bool {
            guard let i = list.firstIndex(where: { $0.id == message.chatId }) else { return false }
            list[i].lastMessagePreview = message.previewText
            list[i].lastMessageDate = message.sentAt
            if !isMine && !isOpen { list[i].unreadCount += 1 }
            list.sort(by: Chat.byActivity)
            return true
        }

        if !update(&eventChats) { _ = update(&dmChats) }
    }

    /// Переносим уже загруженные превью в свежий список, чтобы при обновлении
    /// строки не «моргали» пустыми.
    private func merged(_ fresh: [Chat], with old: [Chat]) -> [Chat] {
        // Пустой ответ почти всегда = сбой сети/отмена запроса, а не «чатов нет».
        // Не затираем уже показанный список — иначе чаты пропадали до перезахода.
        guard !fresh.isEmpty else { return old }
        guard !old.isEmpty else { return fresh }
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return fresh.map { chat in
            var updated = chat
            // Быстрая фаза последнего сообщения не знает: у мероприятия его дата
            // приходит только вторым шагом. Уже загруженное превью и дату переносим,
            // иначе список пересортировался бы и «прыгнул» туда-обратно.
            if let prev = previous[chat.id], prev.lastMessagePreview != nil {
                updated.lastMessagePreview = prev.lastMessagePreview
                updated.lastMessageDate = prev.lastMessageDate
            }
            return updated
        }
        .sorted(by: Chat.byActivity)
    }

    /// Лёгкое обновление счётчиков непрочитанного (1 запрос) — при возврате из чата.
    func refreshUnread(session: AppSession) async {
        guard didLoadOnce, !AppConfig.useMockData else { return }
        guard let unread = try? await APIClient.shared.get("/api/unread", as: UnreadDTO.self) else { return }
        for i in eventChats.indices {
            let id = eventChats[i].dealId
            eventChats[i].unreadCount = unread.events[id] ?? 0
            // Упоминание и ответ подсвечиваем отдельно: их ждут адресно,
            // и терять их среди обычных непрочитанных нельзя.
            eventChats[i].hasMention = unread.mentions?[id] ?? false
            eventChats[i].hasReply = unread.replies?[id] ?? false
        }
        for i in dmChats.indices {
            dmChats[i].unreadCount = unread.dms[dmChats[i].otherUserId ?? ""] ?? 0
        }
    }

    /// Превью последних сообщений.
    ///
    /// Дорого: отдельного «последнее сообщение чата» на сервере нет, и за каждым
    /// превью приходится тянуть последнюю сотню сообщений мероприятия — сервер при
    /// этом подписывает ссылку на каждое медиа. Раньше это делалось для ВСЕХ чатов
    /// сразу при каждом обновлении: два десятка тяжёлых запросов разом, отсюда и
    /// «обновление длится вечность».
    ///
    /// Поэтому: личным перепискам превью не запрашиваем вовсе (сервер отдаёт его
    /// прямо в списке переписок), мероприятиям — только тем, где превью ещё нет,
    /// и не больше нескольких запросов одновременно. Дальше превью поддерживают
    /// живые сообщения из сокета.
    private func loadPreviews(session: AppSession) async {
        let pending = eventChats.filter { $0.lastMessagePreview == nil }
        guard !pending.isEmpty else { return }

        let window = 4
        var index = 0
        await withTaskGroup(of: (String, Message?).self) { group in
            func addNext() {
                guard index < pending.count else { return }
                let chat = pending[index]
                index += 1
                group.addTask { (chat.id, await session.chats.lastMessage(for: chat)) }
            }
            for _ in 0..<min(window, pending.count) { addNext() }

            while let (chatId, message) = await group.next() {
                if Task.isCancelled { return }
                if let message {
                    apply(chatId: chatId, preview: message.previewText, date: message.sentAt)
                }
                addNext()
            }
        }
        sortByActivity()
    }

    private func apply(chatId: String, preview: String, date: Date) {
        if let i = eventChats.firstIndex(where: { $0.id == chatId }) {
            eventChats[i].lastMessagePreview = preview
            eventChats[i].lastMessageDate = date
        } else if let i = dmChats.firstIndex(where: { $0.id == chatId }) {
            dmChats[i].lastMessagePreview = preview
            dmChats[i].lastMessageDate = date
        }
    }

    private func sortByActivity() {
        eventChats.sort(by: Chat.byActivity)
        dmChats.sort(by: Chat.byActivity)
    }
}
