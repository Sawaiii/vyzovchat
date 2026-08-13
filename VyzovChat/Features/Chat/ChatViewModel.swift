import SwiftUI
import Combine

/// Элемент ленты чата: разделитель по дням или сообщение (с флагом, показывать ли
/// на нём статус прочтения — он только на последнем в череде моих подряд).
enum ChatFeedItem: Identifiable {
    case separator(title: String, key: String)
    case message(Message, showRead: Bool)
    /// Вложение, которое ещё загружается — плитка с кольцом прогресса.
    case uploading(ChatViewModel.PendingUpload)

    var id: String {
        switch self {
        case .separator(_, let key): return "sep-\(key)"
        case .message(let m, _): return m.id
        case .uploading(let p): return "up-\(p.id)"
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    // Ленту пересобираем СИНХРОННО при любом изменении сообщений/поиска — в той же
    // транзакции, что и сама правка. Через Combine (receive(on:main)) обновление
    // приходило на цикл позже: лента моргала пустой и «допрыгивала» (баунс).
    @Published var messages: [Message] = [] { didSet { rebuildActiveFeed() } }
    @Published var draft = ""
    /// Запрос в окне поиска. Ленту чата не трогает — см. `visibleMessages`.
    @Published var search = "" { didSet { scheduleServerSearch() } }
    /// Найденное сервером по всему мероприятию.
    @Published private(set) var searchResults: [Message] = []
    /// Идёт запрос поиска — чтобы «Ничего не найдено» не мигало раньше времени.
    @Published private(set) var isSearching = false
    @Published var isLoading = true
    @Published var replyingTo: Message?
    @Published var editingMessage: Message?
    /// Сообщение, на котором открыть чат (первое непрочитанное / последнее).
    @Published var initialAnchorId: String?
    /// Докуда собеседник прочитал переписку (id сообщения) — для галочек в ЛС.
    @Published var partnerReadUpTo = 0
    /// Когда собеседник прочитал (для «Прочитано в HH:MM»).
    @Published var partnerReadAt: Date?
    /// Я админ этого чата мероприятия (можно слать отчёт, добавлять участников).
    @Published var isChatAdmin = false
    /// Могу звать по ссылке — админ чата либо куратор.
    @Published var canInvite = false
    /// Что мне можно в этом чате. Считает сервер, мы только рисуем по этому
    /// набору кнопки: держать свою копию правил значит однажды разойтись с ним.
    @Published var rights: MeRightsDTO?

    var myEventRole: EventRole { EventRole(rights?.role) }
    var canDocs: Bool { rights?.docs ?? isChatAdmin }
    var canClaims: Bool { rights?.claims ?? isChatAdmin }
    /// Отбор фото; «Отчёт» и «Фотобанк» отдельно — они только у админа чата.
    var canPickPhotos: Bool { rights?.otbor ?? isChatAdmin }
    var canPickForReport: Bool { rights?.otbor_all ?? isChatAdmin }
    var canCheckin: Bool { rights?.checkin ?? true }
    var canEditEquipment: Bool { rights?.equip_edit ?? isChatAdmin }

    /// Можно ли ставить галочки в конкретном чеклисте. Свою половину отмечает
    /// только своя сторона: в этом весь смысл двойного чеклиста загрузки —
    /// подпись стоит и у склада, и у реализации.
    func canCheck(_ kind: EquipCheckKind) -> Bool {
        switch kind {
        case .loaded, .returned:    return rights?.equip_check ?? false
        case .loadedImpl:           return rights?.equip_check_impl ?? isChatAdmin
        case .arrived, .dismantled: return rights?.equip_check_site ?? isChatAdmin
        }
    }

    /// Опрос клиента: выдать ссылку и посмотреть отзывы.
    var canReview: Bool { rights?.review ?? isChatAdmin }
    var canAssignRoles: Bool { rights?.assign ?? false }
    /// Объявить важное с отметкой «Ознакомлен» — админ чата, старший, наблюдатель.
    var canAlarm: Bool { rights?.alarm ?? false }
    /// Отмечаться «ознакомлен» — участник и старший.
    var canAck: Bool { rights?.canAck ?? false }
    /// Править и отменять смены задним числом — только руководство.
    var canEditShifts: Bool { rights?.shift_cancel ?? false }
    /// Этапы, которые закрываю именно я: у админа все, у старшего середина,
    /// у кладовщика погрузка и приёмка.
    var myStages: Set<String> { Set(rights?.stages ?? []) }
    /// Кто докуда дочитал в мероприятии: workerId → id последнего прочитанного.
    @Published var groupReads: [String: Int] = [:]
    /// Всего участников мероприятия.
    @Published var memberCount = 0
    /// Состав мероприятия — нужен для подсказок при упоминании через @.
    @Published var members: [User] = []
    /// Отмеченные мной фото (id сообщений) — попадут в отчёт/фотобанк.
    @Published var pickedIds: Set<String> = []

    // MARK: - Темы (подканалы) мероприятия
    @Published var topics: [TopicDTO] = []
    /// Выбранная тема; nil — канал «Общий».
    @Published var selectedTopicId: Int?
    /// Тема, чья лента реально лежит в `messages` (см. selectTopic).
    @Published private(set) var loadedTopicId: Int?
    /// Непрочитанное по темам: "main" — «Общий», иначе id темы.
    @Published var topicUnread: [String: Int] = [:]
    /// Кэш лент по темам (для листания без пустых экранов).
    private var messagesByTopic: [String: [Message]] = [:]
    /// Готовые ленты неактивных тем — см. `staticFeed(for:)`.
    private var feedByTopic: [String: [ChatFeedItem]] = [:]

    /// Готовая лента активной темы (разделители + альбомы + пометки прочтения).
    /// Пересчитывается только при изменении `messages`/`search` — а НЕ на каждом
    /// рендере/нажатии клавиши, как было при группировке во вью.
    @Published private(set) var activeFeed: [ChatFeedItem] = []

    /// Что показывать в ленте.
    ///
    /// При поиске отдаём результаты сервера: он ищет по всему мероприятию и по всем
    /// видимым темам, а не по загруженной сотне сообщений открытой ленты. Пока ответ
    /// не пришёл, показываем отфильтрованное локально — иначе лента моргала бы пустой.
    /// Лента чата. Поиск её больше не подменяет: найденное живёт в своём окне,
    /// а чат под ним остаётся чатом — иначе переход к сообщению начинался с
    /// того, что лента сначала превращалась в список ссылок и обратно.
    var visibleMessages: [Message] { messages }

    /// Все фото/видео чата — для листания в полноэкранном просмотре.
    var mediaAttachments: [Message.Attachment] {
        messages.flatMap { $0.attachments.filter { $0.isImage || $0.isVideo } }
    }

    /// Все вложения чата (фото/видео/файлы) — для раздела «Вложения» в профиле.
    var allAttachments: [Message.Attachment] {
        messages.flatMap { $0.attachments }
    }

    let chat: Chat
    private let service: ChatServicing
    private let currentUserId: String
    private var usersById: [String: User] = [:]
    /// Докуда уже отмечено прочитанным — по КАЖДОЙ ленте отдельно.
    ///
    /// Был один счётчик на весь чат, и он ломал отметку: побывав в теме со
    /// свежими сообщениями, мы переставали отмечать «Общий» (там id меньше), а
    /// служебные строки — смены, этапы, состав — живут именно в «Общем». Они и
    /// висели непрочитанными, сколько их ни открывай.
    private var lastMarkedRead: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()
    /// Первичная загрузка завершена — только после неё имеет смысл досинхрон.
    private var didInitialLoad = false
    /// Дебаунс отметки прочтения/статуса собеседника при потоке входящих.
    private var readSyncTask: Task<Void, Never>?
    /// Дебаунс поиска по мероприятию.
    private var searchTask: Task<Void, Never>?
    /// Когда последний раз досинхронизировались после переподключения сокета.
    private var lastResync: Date?

    private var useRealtime: Bool { !AppConfig.useMockData }

    init(chat: Chat, service: ChatServicing, currentUserId: String) {
        self.chat = chat
        self.service = service
        self.currentUserId = currentUserId
        subscribeToRealtime()
        // Предел длины записи ловит строка ввода: ей нужно ещё и вернуть себе
        // обычный вид, а модель про её состояние ничего не знает.
    }

    /// Пересобрать ленту активной темы. Вызывается синхронно из didSet свойств
    /// messages/search, поэтому лента всегда согласована с текущими данными.
    private func rebuildActiveFeed() {
        var feed = buildFeed(visibleMessages)
        // Загружаемые вложения — в самом конце, после всех сообщений.
        feed.append(contentsOf: pendingUploads.map { ChatFeedItem.uploading($0) })
        activeFeed = feed
    }

    // MARK: - Realtime

    private func subscribeToRealtime() {
        guard useRealtime else { return }
        RealtimeService.shared.incoming
            .filter { [chatId = chat.id] in $0.chatId == chatId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in Task { @MainActor in self?.receiveLive(msg) } }
            .store(in: &cancellables)

        RealtimeService.shared.reactionUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (id, reactions) in
                Task { @MainActor in self?.applyReactions(id, reactions) }
            }
            .store(in: &cancellables)

        RealtimeService.shared.deletions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                Task { @MainActor in
                    // Закреплённое удалили — убираем и из полосы: сервер про
                    // это отдельным кадром не сообщает.
                    self?.dropPin(id)
                    self?.messages.removeAll { $0.id == id }
                    // Ответы на удалённое остаются с пустой цитатой до
                    // перезахода — гасим её сразу.
                    self?.dropReplyQuotes(to: id)
                }
            }
            .store(in: &cancellables)

        RealtimeService.shared.pinUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in self?.applyPin(update) }
            }
            .store(in: &cancellables)

        RealtimeService.shared.stagesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eventId in
                Task { @MainActor in
                    guard let self, eventId == self.chat.dealId else { return }
                    await self.loadStages()
                }
            }
            .store(in: &cancellables)

        RealtimeService.shared.edits
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (id, body, editedAt) in
                Task { @MainActor in self?.applyEdit(id, body, editedAt) }
            }
            .store(in: &cancellables)

        // Видео сервер обрабатывает уже после отправки: сначала вынимает обложку,
        // потом (если вышло легче) подменяет сам файл. Приходит двумя порциями,
        // поэтому переносим только те поля, что реально прислали.
        RealtimeService.shared.mediaPatches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] patch in
                Task { @MainActor in self?.applyMediaPatch(patch) }
            }
            .store(in: &cancellables)

        // Состав или чья-то роль изменились. Если это наше мероприятие — перечитываем
        // карточку: сменили роль мне, и кнопки этапов, чеклиста и претензий должны
        // появиться (или пропасть) сразу, а не после выхода из чата.
        RealtimeService.shared.membersChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eventId in
                Task { @MainActor in
                    guard let self, eventId == self.chat.dealId else { return }
                    await self.loadEventMeta()
                }
            }
            .store(in: &cancellables)

        // Кто-то отметился «ознакомлен»: счётчик под врезкой общий, растёт у всех.
        RealtimeService.shared.ackUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in self?.applyAck(update.messageId, count: update.count) }
            }
            .store(in: &cancellables)

        // Темы мероприятия изменились (создали/удалили).
        RealtimeService.shared.topicsChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in await self?.reloadTopics() } }
            .store(in: &cancellables)

        // Участник дочитал чат мероприятия — обновляем «прочитали N из M».
        RealtimeService.shared.groupReadUpdates
            .filter { [dealId = chat.dealId] in $0.eventId == dealId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                Task { @MainActor in
                    guard let self else { return }
                    self.groupReads[info.workerId] = max(self.groupReads[info.workerId] ?? 0, info.lastRead)
                }
            }
            .store(in: &cancellables)

        // Собеседник прочитал ЛС — обновляем галочки на лету.
        RealtimeService.shared.dmReads
            .filter { [otherId = chat.otherUserId] in $0.reader == otherId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                Task { @MainActor in
                    guard let self else { return }
                    self.partnerReadUpTo = max(self.partnerReadUpTo, info.lastRead)
                    if let at = info.readAt { self.partnerReadAt = at }
                }
            }
            .store(in: &cancellables)

        // (Пере)подключение сокета: Socket.IO НЕ переигрывает сообщения, пришедшие
        // пока мы были офлайн (сон/потеря сети). Досинхронизируем открытую ленту.
        // dropFirst — реагируем только на реальные переподключения, а не на текущее
        // значение при подписке (первичную загрузку делает load()).
        RealtimeService.shared.$isConnected
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in await self?.resyncAfterReconnect() } }
            .store(in: &cancellables)
    }

    /// Досинхрон после (пере)подключения: тянем свежую ленту и МЕРДЖИМ по id
    /// (не заменяем — иначе теряем live-сообщения, пришедшие во время запроса).
    private func resyncAfterReconnect() async {
        guard useRealtime, didInitialLoad else { return }
        // На плохой связи сокет поднимается и падает пачками. Досинхрон нужен, но
        // не на каждое мигание: иначе на слабом канале приложение молотит запросы
        // ровно тогда, когда канала и нет.
        let now = Date()
        if let last = lastResync, now.timeIntervalSince(last) < 15 { return }
        lastResync = now
        let fresh: [Message]?
        if chat.isDirect {
            fresh = await service.fetchDMMessages(otherId: chat.otherUserId ?? "")
        } else {
            fresh = await service.fetchMessages(chatId: chat.id, topicId: loadedTopicId)
        }
        if let fresh { mergeMessages(fresh) }
        scheduleReadSync()
        if !chat.isDirect {
            await loadEventMeta()
            await refreshTopicUnread()
        }
    }

    /// Слить свежую выборку с текущей лентой по id: серверная версия сообщения
    /// побеждает (правки/реакции), а live-сообщения, которых ещё нет в выборке,
    /// не теряются. Порядок — по времени, затем по id.
    private func mergeMessages(_ fresh: [Message]) {
        guard !fresh.isEmpty else { return }
        messages = mergedFeed(messages, fresh)
    }

    /// Слить две выборки по id: серверная версия побеждает, порядок по времени и id.
    private func mergedFeed(_ old: [Message], _ fresh: [Message]) -> [Message] {
        var byId: [String: Message] = [:]
        for m in old { byId[m.id] = m }
        for m in fresh { byId[m.id] = m }
        return byId.values.sorted {
            ($0.sentAt, Int($0.id) ?? 0) < ($1.sentAt, Int($1.id) ?? 0)
        }
    }

    /// Дебаунс отметки прочтения: при потоке входящих не шлём запрос на КАЖДОЕ
    /// сообщение — сворачиваем в один после паузы.
    private func scheduleReadSync() {
        readSyncTask?.cancel()
        readSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.markRead()
        }
    }

    // MARK: - Построение ленты

    /// Лента для отображения: разделители по дням + склейка альбомов + пометка,
    /// на каком сообщении показывать статус прочтения.
    func buildFeed(_ input: [Message]) -> [ChatFeedItem] {
        let source = collapseAlbums(input)
        let readIds = lastInMyRunIds(source)
        var result: [ChatFeedItem] = []
        var lastDay: String?
        for m in source {
            let day = RelativeDate.daySeparator(m.sentAt)
            if day != lastDay { result.append(.separator(title: day, key: day)); lastDay = day }
            result.append(.message(m, showRead: readIds.contains(m.id)))
        }
        return result
    }

    /// Лента неактивной темы (в пейджере) — берём готовую из кэша.
    ///
    /// Раньше она собиралась прямо здесь, на каждый вызов. А вызывается это из
    /// тела экрана, и в пейджере лежат сразу все темы: любое обновление чата —
    /// буква в поле ввода, чужой статус в сети, нажатие на микрофон — заново
    /// пересобирало ленту каждой темы, с разбором дат по всем её сотням
    /// сообщений. Отсюда и рывки на ровном месте.
    func staticFeed(for topicId: Int?) -> [ChatFeedItem] {
        feedByTopic[topicKey(topicId)] ?? []
    }

    /// Запомнить ленту темы вместе с уже разложенной раскладкой.
    private func cacheTopic(_ list: [Message], for key: String) {
        messagesByTopic[key] = list
        feedByTopic[key] = buildFeed(list)
    }

    /// Склейка альбома: несколько фото одной отправкой — одним сообщением-сеткой.
    private func collapseAlbums(_ input: [Message]) -> [Message] {
        var result: [Message] = []
        for message in input {
            if let album = message.albumId,
               var last = result.last,
               last.albumId == album,
               last.senderId == message.senderId {
                last.attachments.append(contentsOf: message.attachments)
                result[result.count - 1] = last
            } else {
                result.append(message)
            }
        }
        return result
    }

    /// ID сообщений, на которых показываем статус прочтения: только последнее в
    /// череде подряд идущих моих сообщений (на остальных дублировать незачем).
    private func lastInMyRunIds(_ msgs: [Message]) -> Set<String> {
        var ids = Set<String>()
        for i in msgs.indices where isMine(msgs[i]) {
            if i == msgs.count - 1 || !isMine(msgs[i + 1]) { ids.insert(msgs[i].id) }
        }
        return ids
    }

    private func applyMediaPatch(_ patch: RealtimeService.MediaPatch) {
        guard let idx = messages.firstIndex(where: { $0.id == patch.messageId }),
              !messages[idx].attachments.isEmpty else { return }
        if let url = patch.mediaURL { messages[idx].attachments[0].remoteURL = url }
        if let url = patch.downloadURL { messages[idx].attachments[0].downloadURL = url }
        if let url = patch.thumbURL { messages[idx].attachments[0].thumbURL = url }
        if let size = patch.mediaSize { messages[idx].attachments[0].sizeBytes = size }
    }

    private func applyEdit(_ id: String, _ body: String, _ editedAt: Date?) {
        // Правку видно и в полосе закрепов: там лежат копии сообщений, и без
        // этого она показывала бы старый текст до перезахода в чат.
        if let pinIdx = pins.firstIndex(where: { $0.id == id }) {
            pins[pinIdx].text = body
            pins[pinIdx].editedAt = editedAt ?? Date()
        }
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = body
        messages[idx].editedAt = editedAt ?? Date()
    }

    // MARK: - Редактирование

    func startEditing(_ message: Message) {
        editingMessage = message
        replyingTo = nil
        draft = message.text ?? ""
    }

    func cancelEditing() {
        editingMessage = nil
        draft = ""
    }

    private func performEdit(_ message: Message, newText: String) async {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx].text = newText          // оптимистично
            messages[idx].editedAt = Date()
        }
        if useRealtime {
            _ = try? await APIClient.shared.patch("/api/messages/\(message.id)",
                                                   json: EditMessageRequest(body: newText), as: OKDTO.self)
        }
    }

    func deleteMessage(_ message: Message) async {
        messages.removeAll { $0.id == message.id }   // оптимистично
        if useRealtime {
            _ = try? await APIClient.shared.delete("/api/messages/\(message.id)", as: OKDTO.self)
        }
    }

    private func receiveLive(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }

        // Сообщение из другой темы — в открытую ленту не кладём, но кладём
        // в её кэш: свайпнём туда и увидим свежее, а не устаревший срез.
        if !chat.isDirect, message.topicId != loadedTopicId {
            let key = topicKey(message.topicId)
            if var feed = messagesByTopic[key], !feed.contains(where: { $0.id == message.id }) {
                feed.append(message)
                cacheTopic(feed, for: key)
            }
            Task { await refreshTopicUnread() }
            return
        }

        messages.append(message)
        appendedMessageId = message.id
        scheduleReadSync()            // читаем на лету (дебаунс при потоке входящих)
    }

    // MARK: - Темы

    /// Все «страницы» чата мероприятия: «Общий» + темы (для свайпов).
    var topicPages: [Int?] { [nil] + topics.map { Optional($0.id) } }

    /// Подтема «Претензия» — её заводит сервер при первой претензии, в неё же
    /// уходит комментарий при урегулировании.
    var claimTopicId: Int? { topics.first { $0.name == "Претензия" }?.id }

    /// Слот темы в ответах сервера: «Общий» проходит как "main".
    private func topicKey(_ id: Int?) -> String { id.map(String.init) ?? "main" }

    /// Название темы для подписи — например, у найденного сообщения.
    func topicName(_ id: Int?) -> String? {
        guard !chat.isDirect else { return nil }
        guard let id else { return "Общий" }
        return topics.first { $0.id == id }?.name
    }

    /// Забрать счётчики тем и обнулить открытую.
    ///
    /// Обнуляем сами, не полагаясь на ответ: наша отметка о прочтении и этот
    /// запрос идут навстречу друг другу, и ответ, посчитанный до неё, возвращал
    /// бейдж на тему, в которой человек сидит прямо сейчас. Ровно так он и
    /// повисал на «Общем» при полностью прочитанном чате.
    private func refreshTopicUnread() async {
        var counts = await service.topicUnread(dealId: chat.dealId)
        counts[topicKey(loadedTopicId)] = 0
        topicUnread = counts
    }

    /// Кэш лент по темам — чтобы при перелистывании страница была не пустой.
    func cachedMessages(for id: Int?) -> [Message] {
        id == loadedTopicId ? messages : (messagesByTopic[topicKey(id)] ?? [])
    }

    /// Лента темы уже загружена (пусть даже пустая) — значит, спиннер не нужен.
    func isTopicLoaded(_ id: Int?) -> Bool {
        id == loadedTopicId || messagesByTopic[topicKey(id)] != nil
    }

    /// Тянем ленты всех тем фоном: иначе соседняя страница при свайпе пустая,
    /// и перелистывание выглядит как «еду по одной картинке».
    func prefetchTopics() async {
        // По две за раз: у мероприятия бывает пять-шесть тем, и все их ленты разом
        // — это столько же запросов по сотне сообщений каждый.
        // Ключи считаем ЗАРАНЕЕ: внутри группы задач код уже не привязан к главному
        // потоку, и звать оттуда методы модели нельзя.
        let pending: [(id: Int?, key: String)] = topicPages
            .filter { messagesByTopic[topicKey($0)] == nil && $0 != loadedTopicId }
            .map { (id: $0, key: topicKey($0)) }
        var index = 0
        await withTaskGroup(of: (String, [Message]?).self) { group in
            func addNext() {
                guard index < pending.count else { return }
                let item = pending[index]
                index += 1
                group.addTask { [service, chat] in
                    (item.key, await service.fetchMessages(chatId: chat.id, topicId: item.id))
                }
            }
            for _ in 0..<min(2, pending.count) { addNext() }
            // Не удалось — кэш темы не создаём: пустой кэш выглядел бы как
            // «в теме ничего нет», и свайп показывал бы пустую страницу.
            while let (key, feed) = await group.next() {
                if let feed { cacheTopic(feed, for: key) }
                addNext()
            }
        }
    }

    /// Переключение темы: показываем кэш мгновенно, затем освежаем с сервера.
    /// `selectedTopicId` мог уже поменяться (свайп двигает капсулу сразу),
    /// поэтому «что загружено» считаем отдельно.
    func selectTopic(_ id: Int?) async {
        guard loadedTopicId != id else { return }
        cacheTopic(messages, for: topicKey(loadedTopicId))   // запомнили текущую
        loadedTopicId = id
        selectedTopicId = id
        // Закрепы у каждой вкладки свои. Если тема уже открывалась — берём её
        // полосу из кэша сразу, без мигания; если нет — пусто до ответа сервера.
        pins = pinsByTopic[topicKey(id)] ?? []
        pinIndex = max(0, pins.count - 1)
        // Спиннер — только если про тему вообще ничего не знаем. Пустой КЭШ значит
        // «в теме нет сообщений», и показывать на секунду загрузку, чтобы затем
        // сказать «сообщений нет», — лишнее мельтешение.
        let known = messagesByTopic[topicKey(id)]
        let cached = known ?? []
        messages = cached
        isLoading = known == nil

        // Мерджим, а не заменяем: замена пустым ответом (сбой сети или отменённый
        // запрос при быстром свайпе) стирала ленту, а следующий ответ возвращал её
        // обратно — это и выглядело как «сообщения пропали и прилетели с баунсом».
        if let fresh = await service.fetchMessages(chatId: chat.id, topicId: id) {
            let merged = cached.isEmpty ? fresh : mergedFeed(cached, fresh)
            // В кэш темы кладём всегда — ответ по ней верный, даже если человек
            // уже ушёл дальше.
            cacheTopic(merged, for: topicKey(id))
            // А открытую ленту трогаем, ТОЛЬКО если это всё ещё та же тема.
            // При быстром свайпе через несколько тем ответ по первой приходил,
            // когда открыта уже третья, и подменял ей ленту чужими сообщениями —
            // отсюда «сообщения пропали, обновление не помогало, потом сами
            // вернулись» (возвращал их следующий ответ).
            guard loadedTopicId == id else { return }
            messages = merged
        }
        guard loadedTopicId == id else { return }
        isLoading = false
        // Смена темы — её лента открывается в конце (см. settleAtBottom во вью).
        initialAnchorId = nil

        // Отметка, закреп и счётчики независимы — разом, а не по очереди.
        async let read: Void = markRead()
        async let pins: Void = loadPins()
        _ = await (read, pins)
        // Счётчики — после отметки о прочтении, иначе ответ, посчитанный до неё,
        // вернул бы бейдж на только что открытую тему.
        await refreshTopicUnread()
    }

    // MARK: - Этапы мероприятия

    /// Пройденные этапы: ключ этапа → кто и когда отметил.
    @Published private(set) var stagesDone: [String: StageDTO] = [:]
    /// Сколько позиций оборудования отмечено на погрузке и на приёмке.
    @Published private(set) var equipProgress: EquipProgressDTO?
    /// Отказ по этапу — показываем словами.
    @Published var stageError: String?

    /// Первый неотмеченный этап — единственный, который сейчас можно закрыть.
    var nextStage: EventStage? { EventStage.allCases.first { stagesDone[$0.rawValue] == nil } }

    /// Этап мой и следующий по очереди.
    func canMark(_ stage: EventStage) -> Bool {
        myStages.contains(stage.rawValue) && nextStage == stage
    }

    /// Снять можно только последний отмеченный: иначе в цепочке появляется
    /// дыра вида «приёмка есть, погрузки нет».
    func canUndo(_ stage: EventStage) -> Bool {
        guard myStages.contains(stage.rawValue), stagesDone[stage.rawValue] != nil else { return false }
        let all = EventStage.allCases
        guard let next = nextStage else { return stage == all.last }
        guard let idx = all.firstIndex(of: next), idx > 0 else { return false }
        return all[idx - 1] == stage
    }

    /// Сколько позиций осталось отметить, чтобы закрыть этап. У загрузки чеклиста
    /// два — считаем по худшему: этап ждёт обе стороны.
    func checklistLeft(_ stage: EventStage) -> Int? {
        let kinds = stage.checklists
        guard !kinds.isEmpty, let p = equipProgress, p.total > 0 else { return nil }
        let done = kinds.map { p.done($0) }.min() ?? 0
        return max(0, p.total - done)
    }

    func loadStages() async {
        guard useRealtime, !chat.isDirect else { return }
        guard let dto = await StagesService.stages(dealId: chat.dealId) else { return }
        stagesDone = Dictionary(dto.stages.map { ($0.stage, $0) }, uniquingKeysWith: { a, _ in a })
        equipProgress = dto.equipment
    }

    func toggleStage(_ stage: EventStage) async {
        let undo = canUndo(stage) && stagesDone[stage.rawValue] != nil
        guard undo || canMark(stage) else { return }
        do {
            try await StagesService.setStage(dealId: chat.dealId, stage: stage, done: !undo)
            Haptics.success()
        } catch StagesService.StageError.order {
            stageError = nextStage.map { "Сначала пройдите этап «\($0.title)»" }
                ?? "Этапы отмечаются по порядку"
            Haptics.warning()
        } catch StagesService.StageError.checklist {
            // Числа берём свои: сервер в отказе их не повторяет, а человеку
            // важно знать, сколько именно позиций осталось.
            let left = checklistLeft(stage) ?? 0
            let total = equipProgress?.total ?? 0
            stageError = "Не отмечено оборудование: осталось \(left) из \(total). Откройте чеклист этапа."
            Haptics.warning()
        } catch {
            stageError = "Не удалось отметить этап"
            Haptics.warning()
        }
        await loadStages()
    }

    // MARK: - Закреплённые сообщения

    /// Закрепы открытого чата. У мероприятия свои на каждой вкладке, у личной
    /// переписки — свои, поэтому при смене темы список перезагружаем.
    @Published private(set) var pins: [Message] = []
    /// Какой из закрепов сейчас в полосе. Нажатие ведёт к нему и переходит
    /// к следующему — как в телеграме.
    @Published private(set) var pinIndex = 0
    /// Не смогли закрепить или открепить — показываем причину.
    @Published var pinError: String?

    var pinned: Message? {
        guard !pins.isEmpty else { return nil }
        return pins[min(pinIndex, pins.count - 1)]
    }

    /// В мероприятии закрепляет админ чата, в личной переписке — любой из
    /// двоих. Так решает сервер, и повторяем это здесь, чтобы не предлагать
    /// заведомо отказное действие.
    var canPin: Bool { chat.isDirect || isChatAdmin }

    /// Закрепы по темам — чтобы при листании полоса не мигала.
    ///
    /// Без кэша каждая смена темы гасила полосу и ждала ответа сервера: она
    /// пропадала и возвращалась, а вместе с ней прыгала высота шапки — это и
    /// выглядело как «чат глючит при свайпе».
    private var pinsByTopic: [String: [Message]] = [:]

    private func setPins(_ list: [Message], remember: Bool = true) {
        pins = list
        pinIndex = max(0, list.count - 1)   // по умолчанию показываем самый свежий
        if remember, !chat.isDirect { pinsByTopic[topicKey(loadedTopicId)] = list }
    }

    /// Сообщение удалили — цитаты на него больше ни на что не ведут.
    private func dropReplyQuotes(to id: String) {
        guard messages.contains(where: { $0.replyToId == id }) else { return }
        // Правим копию и присваиваем разом: у `messages` в didSet пересборка
        // ленты, и поэлементная правка пересобрала бы её на каждый ответ.
        var updated = messages
        for idx in updated.indices where updated[idx].replyToId == id {
            updated[idx].replySender = nil
            updated[idx].replyPreview = nil
        }
        messages = updated
    }

    /// Сообщение удалили — оно не может остаться в полосе.
    private func dropPin(_ id: String) {
        guard pins.contains(where: { $0.id == id }) else { return }
        setPins(pins.filter { $0.id != id })
    }

    /// Закрепы остальных тем — заранее, как и их ленты: тогда первый же свайп
    /// показывает полосу сразу, а не подмигивает ею через полсекунды.
    private func prefetchPins() async {
        guard !chat.isDirect else { return }
        let pending: [(id: Int?, key: String)] = topicPages
            .filter { pinsByTopic[topicKey($0)] == nil }
            .map { (id: $0, key: topicKey($0)) }
        guard !pending.isEmpty else { return }
        let dealId = chat.dealId
        await withTaskGroup(of: (String, [Message]).self) { group in
            for item in pending {
                group.addTask { [service] in
                    (item.key, await service.pinnedMessages(dealId: dealId, topicId: item.id))
                }
            }
            for await (key, list) in group { pinsByTopic[key] = list }
        }
    }

    func loadPins() async {
        if chat.isDirect {
            guard let peer = chat.otherUserId else { return }
            setPins(await service.pinnedDMMessages(peerId: peer))
            return
        }
        let id = loadedTopicId
        let list = await service.pinnedMessages(dealId: chat.dealId, topicId: id)
        // Пока ходили за закрепами, тему могли пролистать дальше — чужие
        // на чужой вкладке показывать нельзя.
        guard loadedTopicId == id else { return }
        setPins(list)
    }

    func pin(_ message: Message) async {
        do {
            setPins(try await service.pin(messageId: message.id))
            Haptics.success()
        } catch {
            pinError = "Не удалось закрепить сообщение"
            Haptics.warning()
        }
    }

    /// Открепляем то, что сейчас в полосе.
    func unpin() async {
        guard let current = pinned else { return }
        await unpin(current)
    }

    func unpin(_ message: Message) async {
        let previous = pins
        setPins(pins.filter { $0.id != message.id })   // полоса реагирует сразу
        do {
            setPins(try await service.unpin(messageId: message.id))
        } catch {
            setPins(previous)                          // не вышло — возвращаем на место
            pinError = "Не удалось открепить сообщение"
            Haptics.warning()
        }
    }

    /// К закреплённому: если оно уже в ленте — просто прокрутка, иначе грузим
    /// окно вокруг него, как при переходе из поиска. Затем полоса переходит
    /// к следующему закрепу.
    func goToPinned() async {
        guard let current = pinned else { return }
        if messages.contains(where: { $0.id == current.id }) {
            jumpNeedsSettle = false
            jumpToMessageId = current.id
        } else if chat.isDirect {
            // Личная переписка приходит последней сотней, и окна вокруг
            // сообщения у неё на сервере нет. Прокрутка к незагруженному
            // сообщению не сработает — молча оставаться на месте хуже, чем
            // сказать почему.
            pinError = "Закреплённое сообщение старше загруженной переписки — открыть его пока нельзя."
            return
        } else {
            await openFound(current)
        }
        guard pins.count > 1 else { return }
        pinIndex = (min(pinIndex, pins.count - 1) + pins.count - 1) % pins.count
    }

    /// Закрепы сменил кто-то другой. Берём только свой чат: кадр уходит всему
    /// мероприятию, а закрепы у «Общего» и у каждой темы свои.
    private func applyPin(_ update: RealtimeService.PinUpdate) {
        if let dmKey = update.dmKey {
            guard chat.isDirect, dmKey == myDMKey else { return }
        } else {
            guard !chat.isDirect,
                  update.eventId == chat.dealId,
                  update.topicKey == topicKey(loadedTopicId) else { return }
        }
        setPins(update.pins)
    }

    /// Ключ переписки как на сервере: «меньший-больший».
    private var myDMKey: String? {
        guard chat.isDirect, let other = chat.otherUserId,
              let a = Int(currentUserId), let b = Int(other) else { return nil }
        return a < b ? "\(a)-\(b)" : "\(b)-\(a)"
    }

    // MARK: - Без звука

    /// Тема заглушена — отдельно от мероприятия целиком.
    func isTopicMuted(_ topicId: Int) -> Bool {
        guard let event = Int(chat.dealId) else { return false }
        return MuteStore.topics.contains(MuteStore.topicKey(event: event, topic: topicId))
    }

    func toggleTopicMute(_ topicId: Int) async {
        guard let event = Int(chat.dealId) else { return }
        await MuteStore.setMuted(!isTopicMuted(topicId), event: event, topic: topicId)
        Haptics.selection()
    }

    func reloadTopics() async {
        guard !chat.isDirect else { return }
        topics = await service.fetchTopics(dealId: chat.dealId)
        await refreshTopicUnread()
        // Тему могли удалить, пока мы в ней — уходим в «Общий».
        if let selected = selectedTopicId, !topics.contains(where: { $0.id == selected }) {
            await selectTopic(nil)
        }
        await prefetchTopics()   // новые темы тоже готовим к свайпу
    }

    func createTopic(name: String) async {
        guard let topic = try? await service.createTopic(dealId: chat.dealId, name: name) else { return }
        Haptics.success()
        await reloadTopics()
        await selectTopic(topic.id)
    }

    func deleteTopic(_ id: Int) async {
        try? await service.deleteTopic(id: id)
        Haptics.success()
        if selectedTopicId == id { await selectTopic(nil) }
        await reloadTopics()
    }

    func unreadCount(for topicId: Int?) -> Int {
        topicUnread[topicKey(topicId)] ?? 0
    }

    // MARK: - Отчёт (только админ чата)

    /// Фото чата — кандидаты в отчёт (id = id сообщения).
    struct ReportPhoto: Identifiable {
        let id: String
        let url: URL
    }

    /// Фото ВСЕГО мероприятия (`GET /api/events/{id}/images`): по всем темам и
    /// глубже загруженной ленты. Отбор без этого видел только то, что успели
    /// подгрузить в открытой теме, — половина съёмки в отчёт просто не попадала.
    @Published private(set) var eventPhotos: [ReportPhoto] = []

    /// Кандидаты в отчёт: серверный список, а пока он не пришёл — то, что есть
    /// в ленте (у отбора не должно быть пустого экрана на ровном месте).
    var reportPhotos: [ReportPhoto] {
        eventPhotos.isEmpty ? feedPhotos : eventPhotos
    }

    /// Фото из загруженной ленты.
    private var feedPhotos: [ReportPhoto] {
        messages.compactMap { m in
            guard let att = m.attachments.first, att.isImage, let url = att.remoteURL else { return nil }
            return ReportPhoto(id: m.id, url: url)
        }
    }

    /// Перечитать фото мероприятия. Запрос доступен тем, кто ведёт отбор
    /// (`canOtbor`), остальным сервер ответит отказом — тогда остаётся лента.
    func loadEventPhotos() async {
        guard useRealtime, !chat.isDirect else { return }
        struct ImagesDTO: Decodable {
            struct Item: Decodable {
                let id: Int
                let media_url: String?
                let thumb_url: String?
            }
            let images: [Item]
        }
        guard let dto = try? await APIClient.shared.get("/api/events/\(chat.dealId)/images",
                                                        as: ImagesDTO.self) else { return }
        eventPhotos = dto.images.compactMap { item in
            // Для сетки хватает превью; полный кадр нужен «юридической инфе».
            guard let raw = item.thumb_url ?? item.media_url,
                  let url = AppConfig.mediaURL(raw) else { return nil }
            return ReportPhoto(id: String(item.id), url: url)
        }
        fullPhotoURLs = Dictionary(
            dto.images.compactMap { item -> (String, URL)? in
                guard let raw = item.media_url, let url = AppConfig.mediaURL(raw) else { return nil }
                return (String(item.id), url)
            },
            uniquingKeysWith: { a, _ in a })
    }

    /// Полные кадры по id сообщения — для водяного знака в «Юридической инфе»,
    /// когда самого сообщения в загруженной ленте нет.
    private var fullPhotoURLs: [String: URL] = [:]

    /// Права админа чата, состав участников и кто докуда прочитал.
    ///
    /// Прочитанность приходит по конкретной ленте (`chat_key`), а не по мероприятию
    /// целиком: у «Общего» и у каждой подтемы свои курсоры.
    func loadEventMeta() async {
        guard useRealtime, !chat.isDirect else { return }
        // Карточка и состояние прочтения независимы — берём разом.
        let key = feedChatKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? feedChatKey
        async let detailsReq = APIClient.shared.get("/api/events/\(chat.dealId)",
                                                    as: EventDetailsDTO.self)
        async let stateReq = APIClient.shared.get(
            "/api/events/\(chat.dealId)/read-state?chat_key=\(key)", as: ReadStateDTO.self)
        let details = try? await detailsReq
        let state = try? await stateReq

        if let dto = details {
            rights = dto.me_rights
            isChatAdmin = dto.me_rights?.chat_admin ?? dto.me_is_chat_admin ?? false
            memberCount = dto.members.count
            members = dto.members.map(User.init(member:))
            canInvite = dto.me_can_invite ?? false
            rebuildMentionIndex()
        }
        if let state {
            groupReads = state.readers
            memberCount = max(memberCount, state.total)
        }
    }

    /// Сколько участников прочитали моё сообщение в мероприятии («прочитали N из M»).
    func groupReadInfo(for message: Message) -> MessageBubble.GroupReadInfo? {
        guard !chat.isDirect, isMine(message), let mid = Int(message.id), mid > 0 else { return nil }
        let total = max(memberCount - 1, 0)     // без меня самого
        guard total > 0 else { return nil }
        let read = groupReads.filter { $0.key != currentUserId && $0.value >= mid }.count
        return MessageBubble.GroupReadInfo(read: min(read, total), total: total)
    }

    /// Отметить/снять фото для отчёта.
    ///
    /// Отметки живут только в приложении: на сервере их больше нет — выгрузка
    /// принимает список id прямо в запросе, поэтому хранить состояние негде и незачем.
    func togglePick(_ messageId: String) {
        if pickedIds.contains(messageId) { pickedIds.remove(messageId) } else { pickedIds.insert(messageId) }
        Haptics.selection()
    }

    /// Снять все отметки фото.
    func clearPicks() {
        pickedIds.removeAll()
        Haptics.selection()
    }

    /// Выгрузить отмеченные фото в папку мероприятия на Диске.
    /// `dest`: report — отчёт, photobank — фотобанк, legal — юридическая информация.
    func exportPicked(to dest: String) async throws -> ExportResultDTO {
        let ids = pickedIds.compactMap(Int.init)
        guard !ids.isEmpty else { return ExportResultDTO(ok: true, count: 0, folder: nil) }
        return try await APIClient.shared.post("/api/events/\(chat.dealId)/export",
                                               json: ExportRequest(ids: ids, dest: dest),
                                               as: ExportResultDTO.self)
    }

    /// Положить готовый кадр в «Юридическую инфу» мероприятия.
    ///
    /// Отдельного эндпоинта под это нет: сервер выдаёт подпись с `purpose: legal`
    /// (проверяя, что мы админ чата) и сам раскладывает файл в папку
    /// «Компания/Мероприятие/Юр-инфо» — файл идёт в хранилище напрямую.
    func uploadLegal(_ data: Data, fileName: String) async throws {
        guard let eventId = Int(chat.dealId) else { return }
        _ = try await MediaUploader.put(data, filename: fileName, purpose: .legal, eventId: eventId)
    }

    /// «Юридическая инфа»: берём ОТМЕЧЕННЫЕ фото из чата, наносим на каждое
    /// его геометку и время съёмки и грузим в папку legal мероприятия.
    /// Возвращает (сколько отправлено, сколько из них с координатами).
    func exportLegal() async throws -> (sent: Int, withGeo: Int) {
        var sent = 0
        var withGeo = 0
        // Запасной вариант: у старых фото своих координат нет (их снимали до
        // появления геометок) — тогда берём текущее местоположение устройства.
        let fallbackGeo = await LocationProvider.shared.current()

        // Идём по ОТМЕТКАМ, а не по ленте: отбирать теперь можно и то, что в
        // загруженную ленту не попало (список фото приходит с сервера целиком).
        for id in pickedIds.sorted() {
            let message = messages.first { $0.id == id }
            let fromFeed = message?.attachments.first(where: { $0.isImage })?.remoteURL
            guard let url = fromFeed ?? fullPhotoURLs[id],
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { continue }

            var geo: (lat: Double, lng: Double)?
            if let lat = message?.geoLat, let lng = message?.geoLng {
                geo = (lat, lng)
            } else {
                geo = fallbackGeo
            }
            if geo != nil { withGeo += 1 }

            let address = geo == nil ? nil
                : await LocationProvider.shared.address(lat: geo!.lat, lng: geo!.lng)

            // Метка: мероприятие + дата/время загрузки + адрес + координаты.
            let stamped = Watermark.stamp(image, title: chat.title, geo: geo,
                                          address: address, date: Date())
            guard let payload = stamped.jpegData(compressionQuality: 0.9) else { continue }
            // Имя обязано быть разным: путь в хранилище сервер строит ИЗ ИМЕНИ
            // файла, и все кадры под «legal.jpg» ложились в один и тот же объект —
            // из двух отмеченных фото в папке оставалось одно.
            try await uploadLegal(payload, fileName: "legal-\(id).jpg")
            sent += 1
        }
        // Чтобы Диск у остальных обновился, не дожидаясь перезахода.
        _ = try? await APIClient.shared.post("/api/disk/notify", json: EmptyBody(), as: OKDTO.self)
        return (sent, withGeo)
    }

    /// Ключ чата целиком: 'e<eventId>' или 'd<lo-hi>'. По нему считается счётчик
    /// непрочитанного в списке чатов.
    private var chatKey: String {
        if chat.isDirect {
            let me = Int(currentUserId) ?? 0
            let other = Int(chat.otherUserId ?? "") ?? 0
            return "d\(min(me, other))-\(max(me, other))"
        }
        return "e\(chat.dealId)"
    }

    /// Ключ открытой сейчас ленты: у «Общего» и у каждой подтемы свой курсор
    /// прочтения — по нему считаются бейджи на чипах тем.
    /// Считаем по ЗАГРУЖЕННОЙ теме, а не по выбранной: капсула тем уезжает
    /// за пальцем раньше, чем доезжает лента, и отметка о прочтении легла бы
    /// под ключ соседней темы — курсор чужой ленты в чужой теме.
    private var feedChatKey: String {
        guard !chat.isDirect else { return chatKey }
        if let topic = loadedTopicId { return "t\(topic)" }
        return "e\(chat.dealId):main"
    }

    /// Отметить чат прочитанным на сервере (снимает счётчик непрочитанного).
    /// Не шлём повторно, если уже отметили до этого же сообщения.
    ///
    /// Отметок две: по мероприятию целиком (бейдж в списке чатов) и по открытой
    /// ленте (бейдж на чипе темы) — сервер считает их раздельно.
    func markRead() async {
        guard useRealtime else { return }
        let lastRead = messages.compactMap { Int($0.id) }.max() ?? 0
        // Сверяемся с курсором ЭТОЙ ленты: у «Общего» и у каждой темы свои id,
        // и общий на всех курсор глушил отметку там, где номера меньше.
        let key = feedChatKey
        guard lastRead > 0, lastRead > (lastMarkedRead[key] ?? 0) else { return }
        lastMarkedRead[key] = lastRead

        // Бейдж чата в списке сервер считает по мероприятию ЦЕЛИКОМ, а не по
        // открытой ленте. Поэтому по ключу мероприятия шлём максимум среди всех
        // загруженных лент: служебные строки — смены, этапы, состав — падают в
        // «Общий», и, сидя в подтеме, мы их «не прочитывали» никогда. Бейджи
        // самих тем при этом остаются честными: у них свои ключи.
        let eventLastRead = max(lastRead, maxKnownMessageId)
        _ = try? await APIClient.shared.post("/api/reads",
                                             json: ReadRequest(chatKey: chatKey, lastRead: eventLastRead),
                                             as: OKDTO.self)
        // Список чатов обнуляет счётчик сразу, без ручного обновления.
        RealtimeService.shared.localRead.send(chat.id)
        if chat.isDirect {
            // Собеседнику — синие галочки; отдельного REST для этого нет.
            RealtimeService.shared.markDMRead(otherId: chat.otherUserId ?? "", lastRead: lastRead)
        } else {
            _ = try? await APIClient.shared.post("/api/reads",
                                                 json: ReadRequest(chatKey: feedChatKey, lastRead: lastRead),
                                                 as: OKDTO.self)
            topicUnread[topicKey(loadedTopicId)] = 0
        }
    }

    /// Самый большой id среди всего, что мы про этот чат знаем: открытая лента
    /// плюс кэши остальных тем (их подтягивает `prefetchTopics`).
    private var maxKnownMessageId: Int {
        var top = messages.compactMap { Int($0.id) }.max() ?? 0
        for feed in messagesByTopic.values {
            top = max(top, feed.compactMap { Int($0.id) }.max() ?? 0)
        }
        return top
    }

    private func applyReactions(_ messageId: String, _ reactions: [Message.Reaction]) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].reactions = reactions
    }

    // MARK: - «Ознакомлен» и важное объявление

    /// Счётчик отметок пришёл по сокету. Своё `ackMe` не трогаем: кадр общий
    /// на всех, а отметился ли я — знаю только по своему нажатию и по ленте.
    private func applyAck(_ messageId: String, count: Int) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].ackCount = max(messages[idx].ackCount, count)
    }

    /// Отметиться «ознакомлен». Повторное нажатие сервер игнорирует, поэтому
    /// кнопку прячем сразу — ждать ответа, чтобы она погасла, незачем.
    func ack(_ message: Message) async {
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[idx].ackMe = true
        messages[idx].ackCount += 1
        struct AckResultDTO: Decodable { let ok: Bool?; let count: Int? }
        guard let dto = try? await APIClient.shared.post("/api/messages/\(message.id)/ack",
                                                         json: EmptyBody(), as: AckResultDTO.self),
              let count = dto.count else { return }
        if let i = messages.firstIndex(where: { $0.id == message.id }) {
            messages[i].ackCount = count
        }
    }

    /// Кто отметился, а кто ещё нет.
    func ackList(messageId: String) async -> [AckPersonDTO] {
        (try? await APIClient.shared.get("/api/messages/\(messageId)/acks", as: [AckPersonDTO].self)) ?? []
    }

    /// Важное объявление в открытую тему: та же врезка, что у вводных из сделки,
    /// но с автором и пушем на телефоны. Обычным сообщением такое теряется.
    func sendAlarm(_ text: String) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = try await APIClient.shared.post("/api/events/\(chat.dealId)/alarm",
                                            json: AlarmRequest(topic_id: selectedTopicId, text: body),
                                            as: MessageDTO.self)
        draft = ""
    }

    func setActive(_ active: Bool) {
        guard useRealtime else { return }
        RealtimeService.shared.activeChatId = active ? chat.id : nil
    }

    // MARK: - Загрузка

    /// Открытие чата: сообщения и отметки прочтения тянем параллельно, всё
    /// остальное — фоном. Раньше запросы шли цепочкой и чат заметно подвисал.
    func load() async {
        isLoading = true

        if chat.isDirect {
            async let msgs = service.fetchDMMessages(otherId: chat.otherUserId ?? "")
            async let reads = readsMap()
            let (loaded, readMap) = await (msgs, reads)
            // Мердж, а не замена: сообщение, пришедшее live за время запроса, было
            // бы иначе затёрто серверным срезом и пропало бы из ленты.
            if let loaded { mergeMessages(loaded) }
            applyAnchor(lastRead: readMap[chatKey] ?? 0)
        } else {
            async let msgs = service.fetchMessages(chatId: chat.id, topicId: selectedTopicId)
            async let reads = readsMap()
            async let tps = service.fetchTopics(dealId: chat.dealId)
            let (loaded, readMap, loadedTopics) = await (msgs, reads, tps)
            loadedTopicId = selectedTopicId
            if let loaded { mergeMessages(loaded) }
            topics = loadedTopics
            applyAnchor(lastRead: readMap[chatKey] ?? 0)
        }
        isLoading = false
        didInitialLoad = true

        // Не задерживает показ чата. Всё это независимо друг от друга, поэтому
        // идёт разом: цепочкой из семи запросов чат «доезжал» секунды три —
        // складывались не сами запросы (сервер отвечает за десятые доли), а
        // ожидания одного за другим.
        Task { [weak self] in
            guard let self else { return }
            async let pins: Void = self.loadPins()
            async let read: Void = self.markRead()
            async let meta: Void = self.loadEventMeta()
            async let stages: Void = self.loadStages()
            async let people: [User] = DirectoryCache.colleagues()

            _ = await (pins, read, meta, stages)
            let colleagues = await people
            self.usersById = Dictionary(colleagues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.rebuildMentionIndex()

            guard !self.chat.isDirect else { return }
            await self.refreshTopicUnread()
            // Ленты остальных тем — последними и с паузой: сразу они
            // конкурировали с открытой лентой за связь. К моменту, когда
            // человек свайпнёт, они обычно уже готовы.
            try? await Task.sleep(for: .milliseconds(400))
            await self.prefetchTopics()
            await self.prefetchPins()
        }
    }

    private func readsMap() async -> [String: Int] {
        guard useRealtime else { return [:] }
        return (try? await APIClient.shared.get("/api/reads", as: [String: Int].self)) ?? [:]
    }

    /// Открываем на первом непрочитанном ЧУЖОМ сообщении. Своих непрочитанных
    /// не бывает, а если непрочитанных нет — anchor пуст, и чат откроется в конце.
    private func applyAnchor(lastRead: Int) {
        let anchor = messages.first {
            (Int($0.id) ?? 0) > lastRead && $0.senderId != currentUserId
        }?.id
        // Встаём на первом непрочитанном, только если после него есть чем
        // заполнить экран. Иначе лента прокручивалась так, чтобы поставить его
        // ПОД шапку, упиралась в конец содержимого и повисала с пустотой внизу —
        // ровно до первого касания, после которого прокрутка вставала на место.
        guard let anchor, let idx = messages.firstIndex(where: { $0.id == anchor }),
              messages.count - idx >= Self.anchorTailMin else {
            initialAnchorId = nil
            return
        }
        initialAnchorId = anchor
    }

    /// Сколько сообщений должно остаться под якорем, чтобы прокрутка к нему
    /// была осмысленной. Меньше — открываем просто в конце ленты.
    private static let anchorTailMin = 8

    // MARK: - Отправка

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Haptics.tap()

        if let editing = editingMessage {
            editingMessage = nil
            await performEdit(editing, newText: text)
            return
        }

        let replyId = replyingTo?.id
        replyingTo = nil
        if useRealtime {
            if chat.isDirect {
                RealtimeService.shared.sendTextDM(text, otherId: chat.otherUserId ?? "", replyTo: replyId)
            } else {
                RealtimeService.shared.send(scope: "event", targetId: chat.dealId, kind: "text",
                                            body: text, replyTo: replyId, topicId: selectedTopicId)
            }
        } else {
            let msg = await service.send(text: text, chatId: chat.id, senderId: currentUserId)
            messages.append(msg)
        }
    }

    /// Отправка фото: несколько снимков уходят одним альбомом + геометкой (юр. инфа).
    func sendImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        Haptics.tap()
        guard useRealtime else {
            let msg = await service.sendPhotos(images.count, chatId: chat.id, senderId: currentUserId)
            messages.append(msg)
            return
        }
        // Формат id альбома тот же, что и в вебе — сервер по нему склеивает мозаику.
        let albumId = images.count > 1 ? "al_" + UUID().uuidString.prefix(12).lowercased() : nil
        let geo = await LocationProvider.shared.current()
        // Плитки создаём СРАЗУ на все снимки, а не по одной по мере загрузки:
        // иначе при отправке пачки человек видит одно фото и не понимает, взялись
        // ли остальные. Загружаем по очереди — так сохраняется порядок в альбоме.
        let pendings = images.map { PendingUpload(preview: $0, name: "Фото") }
        pendingUploads.append(contentsOf: pendings)
        defer {
            let ids = Set(pendings.map(\.id))
            pendingUploads.removeAll { ids.contains($0.id) }
        }

        var failed = 0
        for (image, pending) in zip(images, pendings) {
            do {
                let media = try await MediaUploader.uploadImage(image) { [weak self] value in
                    Task { @MainActor in self?.setProgress(pending.id, value) }
                }
                emit(media, kind: "image", albumId: albumId, geo: geo)
                // Отправленное убираем сразу — его место занимает настоящее сообщение.
                pendingUploads.removeAll { $0.id == pending.id }
            } catch {
                // Молча пропускать нельзя: раньше неудачная загрузка просто
                // «съедала» снимок — человек был уверен, что отправил фото,
                // а в чате его не появлялось.
                failed += 1
                pendingUploads.removeAll { $0.id == pending.id }
            }
        }
        if failed > 0 {
            uploadError = failed == images.count
                ? "Не удалось отправить фото. Проверьте связь и попробуйте ещё раз."
                : "Не отправилось фото: \(failed) из \(images.count). Попробуйте ещё раз."
            Haptics.warning()
        }
    }

    /// Что показать про неудачную отправку вложения (сбрасывается по показу).
    @Published var uploadError: String?

    /// Вложение, которое сейчас уходит на сервер.
    struct PendingUpload: Identifiable, Equatable {
        let id = UUID().uuidString
        /// Превью для фото; у файлов его нет — покажем значок.
        let preview: UIImage?
        let name: String
        /// Голосовое. Отдельно от «файла без превью»: у голосового и вид свой,
        /// строкой, а не плиткой, — иначе отправленное выглядит как видео и
        /// потом на глазах превращается в голосовое.
        var isVoice: Bool = false
        var progress: Double = 0

        static func == (a: PendingUpload, b: PendingUpload) -> Bool {
            a.id == b.id && a.progress == b.progress
        }
    }

    /// Загружаемые прямо сейчас вложения — рисуются в конце ленты.
    @Published var pendingUploads: [PendingUpload] = [] { didSet { rebuildActiveFeed() } }

    // MARK: - Голосовые сообщения

    let recorder = VoiceRecorder()

    // Ниже — состояние записи БЕЗ @Published, намеренно.
    //
    // Экран чата подписан на модель целиком, и любая публикация перерисовывает
    // его весь: шапку, этапы, полосу тем и пейджер со всеми лентами. За первую
    // секунду жеста записи такое случалось несколько раз — касание, старт,
    // замок, — и жест в это время шёл рывками. Показывает запись теперь строка
    // ввода, у неё для этого своё состояние; модель только пишет звук.

    /// Идёт запись. Отдельно от `recorder.isRecording`: по этому флагу
    /// строка ввода переключается на счётчик.
    private(set) var isRecording = false
    /// Запись зафиксирована — палец можно отпустить, она продолжается.
    var isRecordingLocked = false
    /// Повтор `recorder.isPaused`: сам рекордер строка не слушает целиком.
    private(set) var isRecordingPaused = false

    /// Запуск записи. Держим задачу, чтобы отпускание пальца дождалось её:
    /// разрешение на микрофон и запуск сессии занимают время, и при коротком
    /// нажатии «отпустил» приходил РАНЬШЕ «начал». Запись оставалась включённой,
    /// а интерфейс считал, что её нет, — остановить её было уже нечем.
    private var recordingStart: Task<Void, Never>?

    func startRecording() async {
        // Вторая запись поверх первой — всегда ошибка вызывающего: жест мог
        // прислать «начать» дважды. Раньше это разворачивалось в лишний круг
        // «включить сессию — выключить сессию» и подвешивало интерфейс.
        guard recordingStart == nil, !isRecording else { return }
        let task = Task { @MainActor in
            do {
                try await recorder.start()
                isRecording = true
                Haptics.tap()
            } catch {
                uploadError = error.localizedDescription
                Haptics.warning()
            }
        }
        recordingStart = task
        await task.value
    }

    /// Пауза и продолжение уже зафиксированной записи: длинную запись бывает
    /// нужно прервать на полуслове, а не начинать заново.
    func togglePause() {
        if recorder.isPaused { recorder.resume() } else { recorder.pause() }
        isRecordingPaused = recorder.isPaused
        Haptics.selection()
    }

    func cancelRecording() async {
        await recordingStart?.value
        recordingStart = nil
        recorder.cancel()
        isRecording = false
        isRecordingLocked = false
        isRecordingPaused = false
        Haptics.selection()
    }

    /// Закончить запись и отправить. Слишком короткая запись (случайное касание)
    /// не отправляется — рекордер вернёт nil.
    func finishRecording() async {
        // Дожидаемся запуска: иначе короткое нажатие останавливало «ничего»,
        // а запись продолжала идти.
        await recordingStart?.value
        recordingStart = nil
        let stopped = recorder.stop()
        isRecording = false
        isRecordingLocked = false
        isRecordingPaused = false
        guard let result = stopped else { return }
        defer { try? FileManager.default.removeItem(at: result.url) }
        guard let data = try? Data(contentsOf: result.url) else { return }

        let pending = PendingUpload(preview: nil, name: "Голосовое", isVoice: true)
        pendingUploads.append(pending)
        defer { pendingUploads.removeAll { $0.id == pending.id } }
        do {
            // Имя с расширением обязательно: тип содержимого сервер определяет
            // именно по нему и присланному клиентом не доверяет.
            let media = try await MediaUploader.uploadFile(data, filename: "voice.m4a") { [weak self] value in
                Task { @MainActor in self?.setProgress(pending.id, value) }
            }
            emit(media, kind: "audio")
            Haptics.success()
        } catch {
            uploadError = "Не удалось отправить голосовое. Проверьте связь и попробуйте ещё раз."
            Haptics.warning()
        }
    }

    private func setProgress(_ id: String, _ value: Double) {
        guard let idx = pendingUploads.firstIndex(where: { $0.id == id }) else { return }
        pendingUploads[idx].progress = value
    }

    /// Загрузить произвольные данные (видео/файл) и отправить сообщением.
    func sendMediaData(_ data: Data, fileName: String) async {
        guard useRealtime else { return }
        // Вид определяем по расширению — сервер делает так же и присланному типу не верит.
        let kind = AppConfig.isImage(fileName) ? "image" : (AppConfig.isVideo(fileName) ? "video" : "file")
        let pending = PendingUpload(preview: nil, name: fileName)
        pendingUploads.append(pending)
        defer { pendingUploads.removeAll { $0.id == pending.id } }
        do {
            let media = try await MediaUploader.uploadFile(data, filename: fileName) { [weak self] value in
                Task { @MainActor in self?.setProgress(pending.id, value) }
            }
            emit(media, kind: kind)
        } catch {
            uploadError = Self.uploadMessage(for: error, fileName: fileName)
            Haptics.warning()
        }
    }

    /// Сервер отбивает файлы не из белого списка — об этом надо сказать прямо,
    /// иначе выглядит как «просто не отправилось».
    private static func uploadMessage(for error: Error, fileName: String) -> String {
        if case let APIError.http(_, code) = error, code == "file_type_not_allowed" {
            return "Такой файл отправить нельзя: «\(fileName)». Можно фото, видео, документы и архивы."
        }
        return "Не удалось отправить «\(fileName)». Проверьте связь и попробуйте ещё раз."
    }

    private func emit(_ media: UploadedMedia, kind: String,
                      albumId: String? = nil, geo: (lat: Double, lng: Double)? = nil) {
        RealtimeService.shared.send(
            scope: chat.isDirect ? "dm" : "event",
            targetId: chat.isDirect ? (chat.otherUserId ?? "") : chat.dealId,
            kind: kind, media: media, albumId: albumId, geo: geo,
            topicId: chat.isDirect ? nil : selectedTopicId)
    }

    /// Переслать сообщение в другой чат мероприятия.
    ///
    /// Пересылку делает сервер: у клиента больше нет ключей файлов в хранилище
    /// (наружу отдаются только временные подписанные ссылки), поэтому переслать
    /// вложение, отправив его заново, физически невозможно. Заодно сервер сам
    /// сохраняет исходного автора и целиком переносит альбом.
    func forward(_ message: Message, to target: ForwardTarget) async {
        guard useRealtime else { return }
        let request: ForwardMessageRequest
        switch target {
        case .chat(let chat):
            // Личный чат адресуем собеседником: у переписки нет своего id,
            // сервер собирает ключ сам.
            if chat.isDirect {
                guard let peer = chat.otherUserId, let workerId = Int(peer) else { return }
                request = ForwardMessageRequest(worker_id: workerId)
            } else {
                guard let eventId = Int(chat.dealId) else { return }
                request = ForwardMessageRequest(event_id: eventId)
            }
        case .person(let user):
            guard let workerId = Int(user.id) else { return }
            request = ForwardMessageRequest(worker_id: workerId)
        }
        _ = try? await APIClient.shared.post("/api/messages/\(message.id)/forward",
                                             json: request, as: OKDTO.self)
        Haptics.success()
    }

    func toggleReaction(_ message: Message, emoji: String) {
        guard useRealtime else { return }
        Haptics.selection()
        RealtimeService.shared.toggleReaction(messageId: message.id, emoji: emoji)
    }

    // MARK: - Поиск по мероприятию

    /// Запрос к серверу с дебаунсом: иначе на каждое нажатие клавиши уходил бы
    /// отдельный поиск по всей истории мероприятия.
    private func scheduleServerSearch() {
        searchTask?.cancel()
        let q = search.trimmingCharacters(in: .whitespaces)
        // Сервер отвечает пустым списком на запрос короче двух символов — не ходим зря.
        guard useRealtime, !chat.isDirect, q.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let found = await self.service.searchMessages(dealId: self.chat.dealId, query: q)
            guard !Task.isCancelled else { return }
            // Пока ходили на сервер, строку могли уже изменить.
            guard self.search.trimmingCharacters(in: .whitespaces) == q else { return }
            self.searchResults = found
            self.isSearching = false
        }
    }

    /// Переход из поиска: подгружаем окно ленты вокруг сообщения и открываем на нём.
    /// Без этого перейти к старому сообщению нельзя — в последнюю сотню оно не входит.
    func openFound(_ message: Message) async {
        guard let id = Int(message.id) else { return }
        search = ""
        searchResults = []
        if message.topicId != loadedTopicId {
            loadedTopicId = message.topicId
            selectedTopicId = message.topicId
        }
        guard let window = await service.fetchMessages(chatId: chat.id, topicId: message.topicId, around: id),
              !window.isEmpty else { return }
        messages = window
        cacheTopic(window, for: topicKey(message.topicId))
        // Через initialAnchorId нельзя: он срабатывает только на первой загрузке
        // чата, а тут лента уже открыта — прокрутка ушла бы в конец.
        jumpNeedsSettle = true
        jumpToMessageId = message.id
    }

    /// Куда проматывать ленту с подсветкой (переход из поиска или из цитаты).
    @Published var jumpToMessageId: String?

    /// Строка ленты, на которой на самом деле лежит это сообщение.
    ///
    /// Обычно это оно само. Но альбом склеен в ленте в одно сообщение — первое
    /// из отправленных разом, — и у остальных фотографий своей строки нет.
    /// Прокрутка к такому id молча не срабатывала: искать в ленте нечего.
    func feedAnchorId(for messageId: String) -> String? {
        if activeFeed.contains(where: { $0.id == messageId }) { return messageId }
        guard let message = messages.first(where: { $0.id == messageId }),
              let album = message.albumId else { return nil }
        return messages.first { $0.albumId == album }?.id
    }

    /// Лента под этим переходом только что заменилась целиком — окном вокруг
    /// сообщения. Прокручивать сразу бесполезно: ячейки с нужным id в ленивом
    /// списке ещё нет, прокрутка молча ничего не делает, и остаёшься где-то
    /// посреди только что подставленной ленты — со стороны это выглядит как
    /// «перекинуло вверх на случайное сообщение». Такой переход нужно доводить.
    @Published var jumpNeedsSettle = false

    /// В открытую ленту ДОБАВИЛОСЬ сообщение — можно доскроллить к нему.
    ///
    /// Отдельно от «в ленте стало другое число сообщений»: при смене темы массив
    /// подменяется целиком, и по одному лишь счётчику лента уезжала в конец на
    /// каждом свайпе, даже если человек читал середину.
    @Published var appendedMessageId: String?

    // MARK: - Упоминания через @

    /// Подсказка для упоминания: что человек набрал после последней «@».
    ///
    /// Сервер сверяет упоминание с ФИО целиком, а в ФИО есть пробел
    /// («@Журавлёв Игорь»), поэтому обрывать подсказку на первом же пробеле нельзя —
    /// иначе фамилию с именем не подобрать.
    private var mentionQuery: String? {
        guard !chat.isDirect, let at = draft.lastIndex(of: "@") else { return nil }
        // «@» должна начинать слово, иначе это адрес почты или часть слова.
        if at > draft.startIndex {
            let before = draft[draft.index(before: at)]
            guard before == " " || before == "\n" else { return nil }
        }
        let query = String(draft[draft.index(after: at)...])
        guard !query.contains("\n"), query.count <= 40 else { return nil }
        return query
    }

    /// Кого предложить: участники мероприятия плюс обращение ко всем.
    /// Себя не показываем — упоминать самого себя незачем, сервер это и не сохранит.
    var mentionSuggestions: [MentionSuggestion] {
        guard let query = mentionQuery else { return [] }
        let q = query.lowercased()
        var out: [MentionSuggestion] = []
        if q.isEmpty || "все".hasPrefix(q) || "всем".hasPrefix(q) {
            out.append(MentionSuggestion(id: "all", title: "все", subtitle: "Оповестить весь состав"))
        }
        for member in members where member.id != currentUserId {
            let name = member.fullName
            guard !name.isEmpty, q.isEmpty || name.lowercased().hasPrefix(q) else { continue }
            out.append(MentionSuggestion(id: member.id, title: name, subtitle: member.position))
        }
        return Array(out.prefix(8))
    }

    /// Подставить выбранное имя вместо набранного «@…».
    func applyMention(_ suggestion: MentionSuggestion) {
        guard let at = draft.lastIndex(of: "@") else { return }
        draft = String(draft[draft.startIndex..<at]) + "@" + suggestion.title + " "
        Haptics.selection()
    }

    struct MentionSuggestion: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
    }

    /// ФИО в нижнем регистре → id: по нему в тексте сообщения находим
    /// «@Фамилия Имя» и уводим по нажатию в профиль.
    ///
    /// Держим готовым, а не считаем на лету: иначе словарь пересобирался бы
    /// для каждого пузыря в ленте.
    @Published private(set) var mentionIndex: [String: String] = [:]

    /// Состав кладём после справочника: упоминают участников мероприятия, и
    /// при совпадении ФИО их запись должна победить.
    private func rebuildMentionIndex() {
        var index: [String: String] = [:]
        for user in usersById.values {
            let name = user.fullName.lowercased()
            if !name.isEmpty { index[name] = user.id }
        }
        for member in members {
            let name = member.fullName.lowercased()
            if !name.isEmpty { index[name] = member.id }
        }
        mentionIndex = index
    }

    // MARK: - Прочее

    func isMine(_ message: Message) -> Bool { message.senderId == currentUserId }
    func sender(_ message: Message) -> User? { usersById[message.senderId] ?? MockData.user(id: message.senderId) }
    func user(for id: String) -> User? { usersById[id] ?? MockData.user(id: id) }

    var storageFolder: String { "\(chat.title) (#\(chat.dealId))" }
}
