import Foundation
import Combine

/// Реалтайм-канал к серверу Vyzov Chat.
///
/// Это обычный WebSocket с JSON-кадрами (`URLSessionWebSocketTask`), а не Socket.IO:
/// на новом бэкенде сокет свой, без протокола поверх. Токен передаётся в query
/// адреса — заголовки при рукопожатии сокета выставить нельзя.
///
/// Две особенности, которых не было раньше:
/// 1. **Комнаты явные.** Сервер шлёт сообщения мероприятия только тем, кто прислал
///    `join` по нему. Поэтому после подключения (и каждого переподключения) надо
///    заново зайти во все свои мероприятия — этим занимается `joinEvents`.
/// 2. **Отправка — только через сокет.** REST-эндпоинта для сообщений нет. Если связи
///    нет, написанное кладётся в очередь и уходит при переподключении, иначе сообщение
///    молча пропадало бы.
final class RealtimeService: ObservableObject {
    static let shared = RealtimeService()

    /// id сотрудников, которые сейчас онлайн.
    @Published private(set) var onlineIds: Set<String> = []
    /// Кэш «последний раз в сети» из событий presence.
    @Published private(set) var lastSeenById: [String: Date] = [:]
    @Published private(set) var isConnected = false

    /// Входящие сообщения (мероприятие и ЛС).
    let incoming = PassthroughSubject<Message, Never>()
    /// Обновления реакций: (messageId, реакции).
    let reactionUpdates = PassthroughSubject<(String, [Message.Reaction]), Never>()
    /// Удалённые сообщения (messageId).
    let deletions = PassthroughSubject<String, Never>()
    /// Отредактированные сообщения: (messageId, новый текст, время правки).
    let edits = PassthroughSubject<(String, String, Date?), Never>()
    /// Сервер дообработал видео: подменил файл и/или вынул обложку.
    let mediaPatches = PassthroughSubject<MediaPatch, Never>()
    /// Собеседник прочитал ЛС: (кто прочитал, докуда, когда).
    let dmReads = PassthroughSubject<(reader: String, lastRead: Int, readAt: Date?), Never>()
    /// Участник дочитал чат мероприятия: (eventId, кто, докуда) — для «прочитали N из M».
    let groupReadUpdates = PassthroughSubject<(eventId: String, workerId: String, lastRead: Int), Never>()
    /// Состав мероприятий изменился — перезагрузить списки.
    let eventsChanged = PassthroughSubject<Void, Never>()
    /// Изменился справочник сотрудников (аватар/имя).
    let workersChanged = PassthroughSubject<Void, Never>()
    /// Изменилось содержимое общего диска.
    let diskChanged = PassthroughSubject<Void, Never>()
    /// Изменился фотобанк.
    let photobankChanged = PassthroughSubject<Void, Never>()
    /// Изменился список тем мероприятия.
    let topicsChanged = PassthroughSubject<Void, Never>()
    /// Сменились закрепы чата. Сервер всегда шлёт весь список — так у всех
    /// одинаковая полоса, без досборки по кусочкам.
    let pinUpdates = PassthroughSubject<PinUpdate, Never>()
    /// Меня упомянули через @ в мероприятии (eventId).
    let mentions = PassthroughSubject<String, Never>()
    /// Кто-то открыл или закрыл смену: (eventId, отметка).
    let checkins = PassthroughSubject<(eventId: String, checkin: CheckinDTO), Never>()
    /// Мы сами прочитали чат (его id) — чтобы список сразу обнулил счётчик.
    let localRead = PassthroughSubject<String, Never>()

    /// Патч медиа к уже показанному сообщению.
    struct MediaPatch {
        let messageId: String
        var mediaURL: URL?
        var downloadURL: URL?
        var thumbURL: URL?
        var mediaSize: Int?
    }

    /// Новый список закрепов чата. Заполнено либо мероприятие с темой, либо
    /// ключ личной переписки — по нему получатель и понимает, его ли это чат.
    struct PinUpdate {
        let eventId: String?
        let topicKey: String
        let dmKey: String?
        let pins: [Message]
    }

    /// Кто вошёл — чтобы отличать свои сообщения и «ответы вам».
    var currentUserId: String?
    var currentUserFio: String?
    /// Открытый сейчас чат — чтобы не слать по нему лишние уведомления.
    var activeChatId: String?

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var token: String?
    /// В каких мероприятиях мы состоим — их надо занимать заново после обрыва.
    private var eventRooms: Set<Int> = []
    /// Написанное без связи: уйдёт при переподключении.
    private var outbox: [[String: Any]] = []
    /// Сколько сообщений держим в очереди. Без предела человек, оставшийся без
    /// связи надолго, копил бы её бесконечно, а при возврате связи всё это разом
    /// улетело бы на сервер.
    private let outboxLimit = 50
    private var retry = 0
    private var reconnectWork: DispatchWorkItem?
    private var pingTimer: Timer?
    /// Соединение закрыто намеренно (выход из аккаунта) — не переподключаться.
    private var closedByUs = false
    /// Сокет открыт и годен для отправки. Отдельно от публикуемого `isConnected`,
    /// которое обновляется на главном потоке и потому отстаёт на цикл.
    private var socketReady = false

    private let queue = DispatchQueue(label: "vyzovchat.realtime")

    private init() {}

    // MARK: - Жизненный цикл соединения

    func connect(token: String) {
        guard !token.isEmpty else { return }
        self.token = token
        closedByUs = false
        openSocket()
    }

    private func openSocket() {
        guard let token, let url = AppConfig.wsURL(token: token) else { return }
        task?.cancel(with: .goingAway, reason: nil)

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveNext()

        // socketReady выставляем СИНХРОННО, до отправки кадров. Публикуемое
        // isConnected для этого не годится: оно уходит на главный поток и станет
        // true лишь на следующем цикле — join успел бы уйти в очередь вместо сокета,
        // сервер не положил бы нас в комнаты, и лента молчала бы до перезахода.
        socketReady = true
        setConnected(true)
        rejoinRooms()
        flushOutbox()
        startPing()
    }

    func disconnect() {
        closedByUs = true
        socketReady = false
        reconnectWork?.cancel()
        reconnectWork = nil
        stopPing()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setConnected(false)
    }

    /// Полный выход: сбрасываем и очередь, и присутствие.
    func reset() {
        disconnect()
        queue.sync { outbox.removeAll() }
        eventRooms.removeAll()
        token = nil
        Task { @MainActor in
            self.onlineIds = []
            self.lastSeenById = [:]
        }
    }

    private func setConnected(_ value: Bool) {
        Task { @MainActor in
            if self.isConnected != value { self.isConnected = value }
        }
    }

    // MARK: - Комнаты мероприятий

    /// Запомнить свои мероприятия и войти в них. Вызывать после загрузки списка чатов
    /// и повторять при его обновлении — сервер шлёт сообщения только в занятые комнаты.
    func joinEvents(_ ids: [Int]) {
        let fresh = Set(ids).subtracting(eventRooms)
        eventRooms.formUnion(ids)
        for id in fresh { sendFrame(["type": "join", "eventId": id]) }
    }

    private func rejoinRooms() {
        for id in eventRooms { sendFrame(["type": "join", "eventId": id]) }
    }

    // MARK: - Приём

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                // Обрыв: сообщения за время офлайна сервер не переиграет,
                // поэтому подписчики после isConnected=true перечитывают ленту сами.
                self.socketReady = false
                self.setConnected(false)
                self.scheduleReconnect()
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(Data(text.utf8))
                case .data(let data):
                    self.handle(data)
                @unknown default:
                    break
                }
                self.setConnected(true)
                self.receiveNext()
            }
        }
    }

    private func scheduleReconnect() {
        guard !closedByUs, reconnectWork == nil else { return }
        stopPing()
        retry += 1
        let delay = min(pow(2.0, Double(min(retry, 5))), 30)   // 2, 4, 8, 16, 30 с
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWork = nil
            self.openSocket()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Не ждать очередной попытки по таймеру — попробовать связаться прямо сейчас
    /// (человек что-то отправил, значит приложение активно).
    private func wakeUp() {
        guard !closedByUs, !socketReady else { return }
        reconnectWork?.cancel()
        reconnectWork = nil
        retry = 0
        openSocket()
    }

    // MARK: - Пульс

    /// Свой пинг раз в 25 секунд: без него оборванное соединение (уснул телефон,
    /// сменилась сеть) не обнаруживается — приложение молча ничего не получает.
    private func startPing() {
        stopPing()
        DispatchQueue.main.async { [weak self] in
            let timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
                self?.task?.sendPing { error in
                    guard error != nil else { return }
                    self?.socketReady = false
                    self?.setConnected(false)
                    self?.scheduleReconnect()
                }
            }
            self?.pingTimer = timer
        }
    }

    private func stopPing() {
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = nil
        }
    }

    // MARK: - Отправка

    /// Отправить кадр. Если связи нет и кадр важен (`queueIfDown`), он подождёт в очереди.
    /// Служебное — join, реакции, отметки прочтения — не копим: к моменту связи оно
    /// уже не имеет смысла.
    @discardableResult
    private func sendFrame(_ payload: [String: Any], queueIfDown: Bool = false) -> Bool {
        guard let task, socketReady,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            if queueIfDown { enqueue(payload) }
            wakeUp()
            return false
        }
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            if queueIfDown { self?.enqueue(payload) }
            self?.socketReady = false
            self?.setConnected(false)
            self?.scheduleReconnect()
        }
        return true
    }

    /// Положить кадр в очередь на отправку, не давая ей разрастаться без предела.
    private func enqueue(_ payload: [String: Any]) {
        queue.sync {
            outbox.append(payload)
            if outbox.count > outboxLimit { outbox.removeFirst(outbox.count - outboxLimit) }
        }
    }

    private func flushOutbox() {
        let queued: [[String: Any]] = queue.sync {
            let items = outbox
            outbox = []
            return items
        }
        for payload in queued { sendFrame(payload, queueIfDown: true) }
    }

    /// Общий конверт сообщения: в мероприятие или в личную переписку.
    private func envelope(eventId: Int?, topicId: Int?, toWorker: Int?) -> [String: Any] {
        if let toWorker {
            return ["type": "dm", "toWorker": toWorker]
        }
        var base: [String: Any] = ["type": "send", "eventId": eventId ?? 0]
        if let topicId { base["topicId"] = topicId }
        return base
    }

    /// Универсальная отправка. Цель обязана быть числовой: пустой id ушёл бы
    /// в мероприятие 0 — сообщение «в никуда».
    func send(scope: String, targetId: String, kind: String,
              body: String? = nil,
              media: UploadedMedia? = nil,
              replyTo: String? = nil, forwardedFrom: String? = nil,
              albumId: String? = nil, geo: (lat: Double, lng: Double)? = nil,
              topicId: Int? = nil) {
        guard let target = Int(targetId) else { return }
        let isDM = scope == "dm"
        var payload = envelope(eventId: isDM ? nil : target,
                               topicId: isDM ? nil : topicId,
                               toWorker: isDM ? target : nil)
        payload["kind"] = kind
        if let body { payload["body"] = body }
        if let media {
            payload["mediaKey"] = media.key
            payload["mediaType"] = media.contentType
            payload["mediaName"] = media.name
            payload["mediaSize"] = media.size
            if let thumb = media.thumbKey { payload["thumbKey"] = thumb }
            if let w = media.width { payload["imgW"] = w }
            if let h = media.height { payload["imgH"] = h }
        }
        if let replyTo, let rid = Int(replyTo) { payload["replyTo"] = rid }
        if let forwardedFrom { payload["forwardedFrom"] = forwardedFrom }
        if let albumId { payload["albumId"] = albumId }
        if let geo {
            payload["geoLat"] = geo.lat
            payload["geoLng"] = geo.lng
        }
        sendFrame(payload, queueIfDown: true)
    }

    func sendText(_ text: String, eventId: String, topicId: Int? = nil,
                  replyTo: String? = nil, forwardedFrom: String? = nil) {
        send(scope: "event", targetId: eventId, kind: "text", body: text,
             replyTo: replyTo, forwardedFrom: forwardedFrom, topicId: topicId)
    }

    func sendMedia(_ media: UploadedMedia, kind: String, eventId: String, topicId: Int? = nil,
                   caption: String? = nil, replyTo: String? = nil, albumId: String? = nil,
                   geo: (lat: Double, lng: Double)? = nil) {
        send(scope: "event", targetId: eventId, kind: kind, body: caption, media: media,
             replyTo: replyTo, albumId: albumId, geo: geo, topicId: topicId)
    }

    func sendTextDM(_ text: String, otherId: String, replyTo: String? = nil, forwardedFrom: String? = nil) {
        send(scope: "dm", targetId: otherId, kind: "text", body: text,
             replyTo: replyTo, forwardedFrom: forwardedFrom)
    }

    func sendMediaDM(_ media: UploadedMedia, kind: String, otherId: String,
                     caption: String? = nil, replyTo: String? = nil, albumId: String? = nil) {
        send(scope: "dm", targetId: otherId, kind: kind, body: caption, media: media,
             replyTo: replyTo, albumId: albumId)
    }

    /// Прочитано до сообщения — собеседнику уйдут синие галочки.
    func markDMRead(otherId: String, lastRead: Int) {
        guard let target = Int(otherId), lastRead > 0 else { return }
        sendFrame(["type": "dmRead", "toWorker": target, "messageId": lastRead])
    }

    func toggleReaction(messageId: String, emoji: String) {
        guard let mid = Int(messageId) else { return }
        sendFrame(["type": "react", "messageId": mid, "emoji": emoji])
    }

    // MARK: - Presence helpers

    func isOnline(_ id: String) -> Bool { onlineIds.contains(id) }
    func lastSeen(for id: String) -> Date? { lastSeenById[id] }

    // MARK: - Разбор входящих кадров

    private func handle(_ data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = root["type"] as? String else { return }

        switch type {
        case "presence:init":
            let ids = (root["online"] as? [Any]) ?? []
            let set = Set(ids.map { Self.idString($0) })
            Task { @MainActor in self.onlineIds = set }

        case "presence":
            guard let raw = root["workerId"] else { return }
            let id = Self.idString(raw)
            let online = (root["online"] as? Bool) ?? false
            let seen = (root["lastSeen"] as? String).flatMap(DateParse.iso)
            Task { @MainActor in
                if online {
                    self.onlineIds.insert(id)
                } else {
                    self.onlineIds.remove(id)
                    if let seen { self.lastSeenById[id] = seen }
                }
            }

        case "message":
            guard let dict = root["message"] as? [String: Any],
                  let dto = Self.decodeMessage(dict) else { return }
            let msg = Message(dto: dto)
            incoming.send(msg)
            // «@Имя» и «@все» сервер присылает отдельным списком — иначе упоминание
            // ничем не отличалось бы от обычного сообщения.
            if let me = currentUserId, let ids = root["mentions"] as? [Any],
               ids.map({ Self.idString($0) }).contains(me), let eid = dto.event_id {
                mentions.send(String(eid))
            }
            notifyIfNeeded(msg, mentioned: mentionsMe(root))

        case "dm":
            guard let dict = root["message"] as? [String: Any],
                  let dto = Self.decodeMessage(dict) else { return }
            let msg = Message(dto: dto, chatId: dmChatId(for: dto))
            incoming.send(msg)
            notifyIfNeeded(msg, mentioned: false)

        case "dm:read":
            guard let from = root["from"] else { return }
            dmReads.send((reader: Self.idString(from),
                          lastRead: Self.intValue(root["lastRead"]),
                          readAt: Date()))

        case "reaction":
            guard let raw = root["messageId"] else { return }
            let arr = (root["reactions"] as? [[String: Any]]) ?? []
            let reactions: [Message.Reaction] = arr.compactMap { d in
                guard let e = d["emoji"] as? String, let w = d["worker_id"] else { return nil }
                return Message.Reaction(emoji: e, workerId: Self.idString(w))
            }
            reactionUpdates.send((Self.idString(raw), reactions))

        case "reaction:mine":
            // Мероприятие в кадре не приходит — уведомление показываем без перехода в чат.
            let emoji = (root["emoji"] as? String) ?? "👍"
            let from = (root["from"] as? String) ?? "Коллега"
            NotificationsManager.shared.show(title: "Реакция \(emoji)",
                                             body: "\(from) — на ваше сообщение",
                                             chatId: nil)

        case "message:edit":
            guard let raw = root["id"] else { return }
            edits.send((Self.idString(raw), (root["body"] as? String) ?? "", Date()))

        case "message:delete":
            guard let raw = root["id"] else { return }
            deletions.send(Self.idString(raw))

        case "message:media":
            guard let raw = root["id"] else { return }
            mediaPatches.send(MediaPatch(
                messageId: Self.idString(raw),
                mediaURL: (root["media_url"] as? String).flatMap { URL(string: $0) },
                downloadURL: (root["download_url"] as? String).flatMap { URL(string: $0) },
                thumbURL: (root["thumb_url"] as? String).flatMap { URL(string: $0) },
                mediaSize: root["media_size"].map(Self.intValue)
            ))

        case "group:read":
            // В кадре — ключ чата ('e12', 'e12:main', 't7'), а не id мероприятия.
            guard let key = root["chatKey"] as? String, let eventId = Self.eventId(fromChatKey: key) else { return }
            groupReadUpdates.send((eventId: eventId,
                                   workerId: Self.idString(root["workerId"] ?? ""),
                                   lastRead: Self.intValue(root["lastRead"])))

        case "checkin":
            guard let raw = root["checkin"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let dto = try? JSONDecoder().decode(CheckinDTO.self, from: data) else { return }
            checkins.send((eventId: Self.idString(root["eventId"] ?? ""), checkin: dto))

        case "pin":
            // topic_id приходит null для «Общего» — это не отсутствие поля,
            // а именно вкладка «Общий», и путать их нельзя.
            let topicKey: String = {
                guard let raw = root["topic_id"], !(raw is NSNull) else { return "main" }
                return Self.idString(raw)
            }()
            let pins = ((root["pins"] as? [[String: Any]]) ?? [])
                .compactMap { Self.decodeMessage($0) }
                .map { Message(dto: $0) }
            let eventId = (root["event_id"]).flatMap { $0 is NSNull ? nil : Self.idString($0) }
            pinUpdates.send(PinUpdate(eventId: eventId,
                                      topicKey: topicKey,
                                      dmKey: root["dm_key"] as? String,
                                      pins: pins))

        case "topics:changed":
            topicsChanged.send(())

        case "members:changed":
            eventsChanged.send(())

        case "disk:change":
            diskChanged.send(())

        case "photobank:change":
            photobankChanged.send(())

        case "event:alert":
            let title = (root["title"] as? String) ?? "Мероприятие"
            let body = (root["body"] as? String) ?? "Напоминание по мероприятию"
            let chatId = root["eventId"].map { "chat-\(Self.idString($0))" }
            NotificationsManager.shared.show(title: title, body: body, chatId: chatId)

        default:
            break
        }
    }

    private func mentionsMe(_ root: [String: Any]) -> Bool {
        guard let me = currentUserId, let ids = root["mentions"] as? [Any] else { return false }
        return ids.map { Self.idString($0) }.contains(me)
    }

    /// Личный чат у нас адресуется id собеседника, а сервер шлёт ключ переписки
    /// «меньший-больший». Достаём из него того, кто не мы.
    private func dmChatId(for dto: MessageDTO) -> String {
        guard let key = dto.dm_key else { return "dm-\(dto.sender_id)" }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return "dm-\(dto.sender_id)" }
        let me = currentUserId.flatMap(Int.init)
        let other = parts.first { $0 != me } ?? dto.sender_id
        return "dm-\(other)"
    }

    // MARK: - Уведомления о входящих

    private func notifyIfNeeded(_ msg: Message, mentioned: Bool) {
        guard msg.senderId != currentUserId else { return }   // не своё
        guard msg.chatId != activeChatId else { return }       // не открытый сейчас чат
        // Упоминание пробивает «без звука»: его как раз и ждут адресно.
        guard mentioned || !MuteStore.isMuted(msg.chatId) else { return }
        let repliedToMe = msg.replySender != nil && msg.replySender == currentUserFio
        let title = msg.senderName ?? "Новое сообщение"
        let prefix = mentioned ? "упомянул(а) вас: " : (repliedToMe ? "ответил(а) вам: " : "")
        NotificationsManager.shared.show(title: title, body: prefix + msg.previewText,
                                         chatId: msg.chatId, avatarURL: msg.senderAvatarURL)
    }

    // MARK: - Хелперы

    private static func decodeMessage(_ dict: [String: Any]) -> MessageDTO? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(MessageDTO.self, from: data)
    }

    /// Ключи чатов: 'e<id>', 'e<id>:main' — мероприятие; 't<topicId>' — подтема
    /// (её мероприятие по кадру не определить, такие отметки пропускаем).
    private static func eventId(fromChatKey key: String) -> String? {
        guard key.hasPrefix("e") else { return nil }
        let body = key.dropFirst()
        let num = body.split(separator: ":").first.map(String.init) ?? String(body)
        return Int(num) != nil ? num : nil
    }

    private static func intValue(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) ?? 0 }
        return 0
    }

    private static func idString(_ any: Any) -> String {
        if let n = any as? Int { return String(n) }
        if let n = any as? NSNumber { return n.stringValue }
        if let s = any as? String { return s }
        return String(describing: any)
    }
}
