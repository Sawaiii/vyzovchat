import Foundation

// MARK: - Ответы сервера (snake_case как в API vyzovchat)

struct ServerErrorDTO: Decodable { let error: String? }

/// Пустое тело для запросов без параметров (например, logout).
struct EmptyBody: Encodable {}

/// Ответ, у которого важен только факт успеха.
struct OKDTO: Decodable { let ok: Bool? }

// MARK: - Авторизация

struct LoginRequest: Encodable {
    let login: String
    let pass: String
}

/// `POST /api/login` отдаёт карточку сотрудника и токен раздельно
/// (на прежнем бэкенде токен лежал внутри карточки).
struct LoginResponseDTO: Decodable {
    let worker: WorkerDTO
    let token: String
}

/// Саморегистрация по коду-приглашению (`POST /api/register`).
struct RegisterRequest: Encodable {
    let invite: String
    let fio: String
    let login: String
    let pass: String
    let email: String?
    let phone: String?
}

/// `GET /api/auth/providers` — какие способы входа включены на сервере.
struct AuthProvidersDTO: Decodable {
    let password: Bool
    let yandex: Bool
    let register: Bool
}

// MARK: - Сотрудники

struct WorkerDTO: Decodable {
    let id: Int
    let org_id: Int?
    let fio: String
    let login: String?
    let phone: String?
    let email: String?
    let position: String?
    /// Глобальная роль: worker | leader | owner | implementer | curator
    let role: String?
    let is_admin: Bool?
    let is_leader: Bool?
    let is_curator: Bool?
    /// S3-ключ фото профиля. Показывать по нему напрямую нельзя —
    /// готовые ссылки приходят одной картой из `GET /api/avatars`.
    let avatar: String?
    let company_id: Int?
    let last_seen: String?
    /// Привязан ли Яндекс-аккаунт — только в `GET /api/workers/{id}`.
    let yandex_linked: Bool?

    /// Может звать подрядчиков по ссылке: галочка в карточке либо глобальная роль.
    var isCurator: Bool { (is_curator ?? false) || role == "curator" }
}

/// Участник мероприятия (`GET /api/events/{id}` → members).
struct MemberDTO: Decodable, Identifiable {
    let id: Int
    let fio: String
    let login: String?
    /// Роль в мероприятии: admin | senior | member | observer | storekeeper
    let role: String
    let position: String?
}

struct CreateWorkerRequest: Encodable {
    let fio: String
    let login: String
    let pass: String
    let role: String?
    let is_admin: Bool
    let is_leader: Bool
    let email: String?
    let phone: String?
}

/// `PATCH /api/workers/{id}` — все поля необязательные, шлём только изменённые.
/// Отдельного `PATCH /api/me` на сервере нет: свою карточку правим этим же путём.
struct UpdateWorkerRequest: Encodable {
    var fio: String?
    var role: String?
    var is_admin: Bool?
    var is_leader: Bool?
    var is_curator: Bool?
    var pass: String?
    var company_id: Int?     // -1 = отвязать компанию
    var email: String?       // "" = очистить
    var phone: String?       // "" = очистить
    var avatar: String?      // S3-ключ из presign; "" = убрать фото
}

/// Компания (бренд) — `GET /api/companies`.
struct CompanyDTO: Decodable, Identifiable {
    let id: Int
    let code: String
    let name: String
}

// MARK: - Мероприятия

/// Метка мероприятия из словаря организации.
struct EventTagDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let color: String
    let roles: [String]?
}

struct EventDTO: Decodable {
    let id: Int
    let name: String
    let status: String?          // active | closed
    let color: String?           // цвет-обои чата
    let archived: Bool?
    /// Готовая подписанная ссылка на картинку мероприятия (сервер уже подписал).
    let avatar_url: String?
    let company_id: Int?
    let needs_photo: Bool?
    let needs_report: Bool?
    let report_status: String?
    let has_docs: Bool?
    let has_claim: Bool?
    let photos_restricted: Bool?
    let starts_at: String?
    let ends_at: String?
    let tags: [EventTagDTO]?
    /// Сколько человек в составе — знаменатель для «На смене: 1/5».
    let members_count: Int?
    /// Я админ этого чата — по нему интерфейс решает, показывать ли правки.
    let my_chat_admin: Bool?
}

/// `GET /api/events/{id}` — состав, смены и мои права в этом чате.
struct EventDetailsDTO: Decodable {
    let id: Int
    let members: [MemberDTO]
    let checkins: [CheckinDTO]?
    let has_open_claim: Bool?
    let me_is_chat_admin: Bool?
    let me_can_invite: Bool?
    /// Что мне можно в этом чате. Считает сервер, клиент только рисует по нему
    /// кнопки — иначе права разъезжаются с серверными при каждой правке.
    let me_rights: MeRightsDTO?
    /// Кого позвал этот куратор — по ним фильтруется список смен.
    let my_invited: [Int]?
}

/// Набор прав в чате мероприятия (`me_rights`).
struct MeRightsDTO: Decodable {
    /// admin | senior | member | observer | storekeeper; пусто — не в составе.
    let role: String?
    let chat_admin: Bool?
    /// Документы (акты): загрузить, заменить, выгрузить.
    let docs: Bool?
    /// Претензии: зафиксировать, урегулировать, отправить.
    let claims: Bool?
    /// Отбор фото и выгрузка на Диск.
    let otbor: Bool?
    /// …включая назначения «Отчёт» и «Фотобанк» — они только у админа чата.
    let otbor_all: Bool?
    /// Какие этапы этот человек закрывает.
    let stages: [String]?
    /// Галочки в чеклисте оборудования.
    let equip_check: Bool?
    /// Добавить и удалить позицию оборудования.
    let equip_edit: Bool?
    /// Отметить свою смену: не для наблюдателя и кладовщика.
    let checkin: Bool?
    /// Раздавать роли в чате — владелец, руководитель, реализатор своей компании.
    let assign: Bool?
}

// MARK: - Этапы мероприятия

/// Пройденный этап: погрузка → приезд/монтаж → готовность → демонтаж → приёмка.
struct StageDTO: Decodable {
    let stage: String
    let done_at: String
    let done_by: String?
}

/// Сколько позиций оборудования отмечено на погрузке и на приёмке.
struct EquipProgressDTO: Decodable {
    let total: Int
    let loaded: Int
    let returned: Int
}

struct StagesDTO: Decodable {
    let stages: [StageDTO]
    let equipment: EquipProgressDTO?
}

struct SetStageRequest: Encodable { let done: Bool }
struct EquipCheckRequest: Encodable { let kind: String; let on: Bool }

struct CreateEventRequest: Encodable {
    let name: String
    let company_id: Int?
    let starts_at: String?
    let ends_at: String?
    let worker_ids: [Int]
    let admin_worker_ids: [Int]
}

struct UpdateEventRequest: Encodable {
    let name: String
    let status: String
    let archived: Bool
    let starts_at: String?
    let ends_at: String?
    let color: String?
    let avatar: String?      // S3-ключ; "" = убрать картинку
}

struct ArchiveEventRequest: Encodable { let archived: Bool }

/// `PUT /api/events/{id}/tags` — метки и признаки мероприятия.
struct SetEventTagsRequest: Encodable {
    let tag_ids: [Int]
    let needs_photo: Bool
    let needs_report: Bool
    let photos_restricted: Bool
}

/// Смена сотрудника на мероприятии.
struct CheckinDTO: Decodable {
    let worker_id: Int
    let fio: String
    let role: String?
    let checked_at: String
    let finished_at: String?
    let geo_lat: Double?
    let geo_lng: Double?
    let finish_lat: Double?
    let finish_lng: Double?
    /// Кто проставил отметку за сотрудника (пусто = отметился сам).
    let opened_by: String?
    let closed_by: String?
}

struct MemberRoleRequest: Encodable { let role: String }

struct AddMemberRequest: Encodable {
    let worker_id: Int
    let role: String
}

// MARK: - Оборудование мероприятия

struct EquipmentDTO: Decodable, Identifiable {
    let id: Int
    let name: String
    let qty: Int?
    let crm_url: String?
    // Чеклист: отметки на погрузке и на приёмке — кто и когда.
    let loaded_at: String?
    let loaded_by: String?
    let returned_at: String?
    let returned_by: String?

    /// Отмечена ли позиция в чеклисте нужного вида.
    func isChecked(_ kind: EquipCheckKind) -> Bool {
        kind == .loaded ? loaded_at != nil : returned_at != nil
    }

    /// Кто отметил — показываем рядом с галочкой.
    func checkedBy(_ kind: EquipCheckKind) -> String? {
        let who = kind == .loaded ? loaded_by : returned_by
        return (who?.isEmpty == false) ? who : nil
    }
}

/// Какой из двух чеклистов: погрузка в машину или приёмка обратно на склад.
enum EquipCheckKind: String, Identifiable {
    case loaded, returned

    var id: String { rawValue }

    var title: String { self == .loaded ? "Чеклист погрузки" : "Чеклист приёма" }
    var stage: String { self == .loaded ? "load" : "accept" }
    var icon: String { self == .loaded ? "shippingbox" : "arrow.down.circle" }
}

struct AddEquipmentRequest: Encodable {
    let name: String
    let qty: Int?
}

// MARK: - Документы (акты)

struct DocumentDTO: Decodable, Identifiable {
    let id: Int
    /// act_accept | act_return | other
    let type: String
    let title: String?
    let file_name: String?
    let file_size: Int?
    /// Подписанные ссылки: посмотреть и сохранить.
    let file_url: String?
    let download_url: String?
    /// Текстовый документ вместо файла.
    let body: String?
    let sent_to_tony: Bool?
    let created_at: String?

    var typeTitle: String {
        switch type {
        case "act_accept": return "Акт приёма"
        case "act_return": return "Акт возврата"
        default:           return title?.isEmpty == false ? title! : "Документ"
        }
    }
}

struct AddDocumentRequest: Encodable {
    let type: String
    let title: String?
    /// Ключ объекта из presign (purpose: document).
    let key: String?
    let name: String?
    let size: Int?
    /// Либо текст вместо файла — сервер требует что-то одно.
    let body: String?
}

// MARK: - Претензии

struct ClaimItemDTO: Decodable, Identifiable {
    let position: String
    /// loss — утеряно, damage — повреждено
    let kind: String
    let note: String?
    let qty: Int?

    var id: String { position + kind + (note ?? "") }
    var kindTitle: String { kind == "loss" ? "Утеряно" : "Повреждено" }
}

struct ClaimDTO: Decodable, Identifiable {
    let id: Int
    /// open | sent | closed
    let status: String
    let created_at: String?
    let author_fio: String?
    let author_role: String?
    let items: [ClaimItemDTO]?

    var isOpen: Bool { status != "closed" }
    var statusTitle: String {
        switch status {
        case "closed": return "Урегулирована"
        case "sent":   return "Отправлена в CRM"
        default:       return "Открыта"
        }
    }
}

struct CreateClaimRequest: Encodable {
    struct Item: Encodable {
        let position: String
        let kind: String
        let note: String
        let qty: Int?
    }
    let items: [Item]
}

// MARK: - Дашборд руководителя

/// Фото отчёта: превью для сетки и оригинал для полноэкранного просмотра.
struct ReportPhotoDTO: Decodable {
    let thumb: String?
    let full: String?
}

struct DashAdminDTO: Decodable, Identifiable {
    let worker_id: Int
    let fio: String
    var id: Int { worker_id }
}

/// Карточка мероприятия с отправленным отчётом.
struct DashEventDTO: Decodable, Identifiable {
    let id: Int
    let name: String
    /// Руководитель уже открывал этот отчёт.
    let viewed: Bool?
    let photos_restricted: Bool?
    let admins: [DashAdminDTO]?
    let report_photos: [ReportPhotoDTO]?
    let claims: [ClaimDTO]?
    let docs: [DocumentDTO]?
    let checkins: [CheckinDTO]?

    var hasOpenClaim: Bool { (claims ?? []).contains { $0.isOpen } }
}

struct DashCompanyDTO: Decodable, Identifiable {
    let name: String
    let events: [DashEventDTO]
    var id: String { name }
}

struct DashboardDTO: Decodable { let companies: [DashCompanyDTO] }

/// День календаря: сколько отчётов сдано и сколько из них уже просмотрено.
struct CalendarDayDTO: Decodable, Identifiable {
    let date: String        // YYYY-MM-DD
    let total: Int
    let viewed: Int
    let new: Int
    var id: String { date }
}

struct CalendarDTO: Decodable { let days: [CalendarDayDTO] }

struct DashboardDayDTO: Decodable {
    let date: String?
    let events: [DashEventDTO]
}

/// Строка сводки смен по всем мероприятиям (для руководства).
struct ShiftRowDTO: Decodable, Identifiable {
    let worker_id: Int
    let fio: String
    let event_id: Int
    let event_name: String
    let company_name: String?
    let role: String?
    let checked_at: String
    let finished_at: String?
    let geo_lat: Double?
    let geo_lng: Double?
    let opened_by: String?
    let closed_by: String?

    var id: String { "\(worker_id)-\(event_id)-\(checked_at)" }
}

// MARK: - Приглашения по ссылке

struct InviteDTO: Decodable {
    let token: String
    /// Путь вида /join/<token> — к нему приписываем адрес сервера.
    let path: String
    let role: String
    let event_name: String?

    /// Полная ссылка, которой можно поделиться.
    var url: URL? { URL(string: AppConfig.baseURL.absoluteString + path) }
}

struct CreateInviteRequest: Encodable { let role: String }

// MARK: - Сброс пароля

struct PasswordRequestBody: Encodable { let email: String }

struct PasswordResetBody: Encodable {
    let email: String
    let code: String
    let pass: String
}

// MARK: - Темы (подканалы) мероприятия

struct TopicDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let sort: Int?
    /// all | custom — приватная тема видна не всем.
    let visibility: String?
    let roles: [String]?
    let members: [Int]?

    var isPrivate: Bool { visibility == "custom" }
}

struct CreateTopicRequest: Encodable {
    let name: String
    let visibility: String
    let roles: [String]
    let members: [Int]
}

struct TopicAccessDTO: Decodable {
    let visibility: String
    let roles: [String]?
    let members: [Int]?
}

// MARK: - Сообщения

struct ReactionDTO: Decodable { let emoji: String; let worker_id: Int }

/// Превью цитируемого сообщения.
struct ReplyDTO: Decodable {
    let id: Int
    let sender_id: Int?
    let sender_fio: String?
    let kind: String?
    let body: String?
}

struct MessageDTO: Decodable {
    let id: Int
    let event_id: Int?
    let dm_key: String?
    let topic_id: Int?
    let sender_id: Int
    let sender_fio: String?
    /// text | image | video | file
    let kind: String
    let body: String?
    let media_type: String?
    let media_name: String?
    let media_size: Int?
    /// Подписанные ссылки от сервера (живут сутки). Ключ объекта в S3 наружу не отдаётся.
    let media_url: String?
    let download_url: String?
    let thumb_url: String?
    let album_id: String?
    let reply_to: Int?
    let reply: ReplyDTO?
    let forwarded_from: String?
    let forwarded_from_id: Int?
    let in_photobank: Bool?
    let img_w: Int?
    let img_h: Int?
    let edited_at: String?
    let created_at: String
    let reactions: [ReactionDTO]?

    var isVideo: Bool { kind == "video" }
    var isAudio: Bool { kind == "audio" }
    /// Всё, что не картинка, не видео и не звук, показываем файлом — включая виды,
    /// которых мы ещё не знаем. Раньше файлом считался только `kind == "file"`, и
    /// голосовое (`audio`) попадало в ветку изображения: приложение пыталось
    /// нарисовать звук картинкой и вечно висело на сером плейсхолдере.
    var isFile: Bool { kind != "image" && kind != "video" && kind != "audio" }
}

struct EditMessageRequest: Encodable { let body: String }

/// Чат без звука. `topic_id` пуст — заглушено мероприятие целиком.
struct MuteDTO: Decodable {
    let event_id: Int
    let topic_id: Int?
}

struct SetMuteRequest: Encodable {
    let event_id: Int
    let topic_id: Int?
    let muted: Bool
}

/// Куда пересылаем: либо мероприятие (`event_id`), либо личная переписка
/// (`worker_id`). Сервер ждёт ровно одно из двух.
struct ForwardMessageRequest: Encodable {
    var event_id: Int? = nil
    var topic_id: Int? = nil
    var worker_id: Int? = nil
}

// MARK: - Прочитанность

/// Отметка «докуда прочитано» (`POST /api/reads`).
/// Ключи чатов: `e<id>` — мероприятие целиком, `e<id>:main` — «Общий»,
/// `t<topicId>` — подтема, `d<dmKey>` — личная переписка.
struct ReadRequest: Encodable {
    let chatKey: String
    let lastRead: Int
}

/// Непрочитанное внутри мероприятия: ключ "main" — «Общий», остальные — id темы.
struct TopicUnreadDTO: Decodable {
    let count: Int
    let last_read: Int
}

/// Кто докуда прочитал — для «прочитали N из M».
struct ReadStateDTO: Decodable {
    let readers: [String: Int]
    let total: Int
}

/// `GET /api/unread` — сводка по всему приложению.
struct UnreadDTO: Decodable {
    let events: [String: Int]
    let dms: [String: Int]
    /// В каких мероприятиях есть непрочитанный ответ на моё сообщение.
    let replies: [String: Bool]?
    /// …и где меня упомянули через @.
    let mentions: [String: Bool]?
}

// MARK: - Личные сообщения

struct DMThreadDTO: Decodable, Identifiable {
    let worker_id: Int
    let fio: String
    let avatar: String?
    let last_body: String?
    let last_kind: String?
    let last_id: Int?
    let unread: Int?

    var id: Int { worker_id }
}

// MARK: - Медиа (S3 через подписанные ссылки)

/// Ответ `POST /api/uploads/presign`: куда класть файл и под каким именем.
struct PresignDTO: Decodable {
    let key: String
    let put_url: String
    let content_type: String
}

struct PresignRequest: Encodable {
    let filename: String
    /// chat | thumb | avatar | event-avatar | document | legal
    let purpose: String
    let event_id: Int?
}

/// Что получилось загрузить — этим набором сообщение уходит в сокет.
struct UploadedMedia {
    let key: String
    let contentType: String
    let name: String
    let size: Int
    var thumbKey: String? = nil
    var width: Int? = nil
    var height: Int? = nil
}

// MARK: - Диск (файловый менеджер над S3)

struct DiskEntryDTO: Decodable, Identifiable {
    let name: String
    let is_dir: Bool
    /// Полный ключ объекта в хранилище — он же путь папки и адрес перехода.
    let key: String
    let size: Int?
    /// Подписанные ссылки — только у файлов.
    let url: String?
    let download_url: String?

    var id: String { key }
    var isDir: Bool { is_dir }
    var path: String { key }
    var isVideo: Bool { AppConfig.isVideo(name) }
    var isMedia: Bool { AppConfig.isImage(name) || isVideo }
    /// Ссылка для показа. У папок её нет.
    var fileURL: URL? { AppConfig.mediaURL(url) }
    /// Ссылка «сохранить файл» — с исходным именем.
    var downloadFileURL: URL? { AppConfig.mediaURL(download_url) ?? fileURL }
}

struct DiskListDTO: Decodable {
    let path: String
    let entries: [DiskEntryDTO]
}

struct DiskDeleteRequest: Encodable { let keys: [String] }

// MARK: - Отбор фото и выгрузка на Диск

struct EventImageDTO: Decodable, Identifiable {
    let id: Int
    let media_url: String?
    let thumb_url: String?
    let created_at: String?
    let sender_fio: String?
}

/// `POST /api/events/{id}/export` — выгрузить выбранные фото в папку мероприятия.
struct ExportRequest: Encodable {
    let ids: [Int]
    /// report | photobank | legal — подпапка выгрузки.
    let dest: String
}

struct ExportResultDTO: Decodable {
    let ok: Bool?
    let count: Int?
    let folder: String?
}

// MARK: - Разбор дат ISO-8601

enum DateParse {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return withFractional.date(from: s) ?? plain.date(from: s)
    }

    /// Время для отправки на сервер (он принимает RFC3339).
    static func string(_ date: Date?) -> String? {
        guard let date else { return nil }
        return plain.string(from: date)
    }
}

// MARK: - Маппинг DTO → доменные модели

extension User {
    init(dto: WorkerDTO) {
        self.init(
            id: String(dto.id),
            workerId: String(dto.id),
            lastName: dto.fio,
            firstName: "",
            middleName: nil,
            phone: dto.phone ?? "",
            position: dto.position ?? "",
            department: nil,
            avatarURL: AvatarStore.url(forWorker: dto.id)
        )
        self.fio = dto.fio
        self.login = dto.login ?? ""
        self.email = dto.email
        self.isAdmin = dto.is_admin ?? false
        self.isLeader = dto.is_leader ?? false
        self.isCurator = dto.isCurator
        self.globalRole = dto.role ?? "worker"
        self.companyId = dto.company_id
        self.lastSeen = DateParse.iso(dto.last_seen)
    }

    /// Участник мероприятия: ФИО и роль в составе, остальное — из справочника.
    init(member: MemberDTO) {
        self.init(
            id: String(member.id),
            workerId: String(member.id),
            lastName: member.fio,
            firstName: "",
            middleName: nil,
            phone: "",
            position: member.position ?? "",
            department: nil,
            avatarURL: AvatarStore.url(forWorker: member.id)
        )
        self.fio = member.fio
        self.login = member.login ?? ""
        self.eventRole = member.role
    }
}

extension Deal {
    init(dto: EventDTO, companyName: String? = nil) {
        let closed = (dto.status ?? "active") == "closed"
        let stage: Deal.Stage = closed ? .done : (dto.report_status == "sent" ? .photoReport : .inProgress)
        self.init(
            id: String(dto.id),
            title: dto.name,
            stage: stage,
            address: nil,
            eventDate: DateParse.iso(dto.starts_at),
            assignedUserIds: [],
            responsibleId: nil,
            archived: dto.archived ?? false
        )
        self.rawStatus = dto.status ?? "active"
        self.reportStatus = dto.report_status ?? "none"
        self.company = companyName
    }
}

extension Chat {
    init(event: EventDTO, unread: Int, companyName: String? = nil,
         lastPreview: String? = nil, lastDate: Date? = nil) {
        let closed = (event.status ?? "active") == "closed"
        self.init(
            id: "chat-\(event.id)",
            dealId: String(event.id),
            title: event.name,
            participantIds: [],
            lastMessagePreview: lastPreview,
            lastMessageDate: lastDate,
            unreadCount: unread,
            isPhotoReportOpen: !closed,
            avatarURL: URL(string: event.avatar_url ?? ""),
            isArchived: event.archived ?? false,
            rawStatus: event.status ?? "active",
            reportStatus: event.report_status ?? "none",
            colorHex: event.color,
            company: companyName
        )
        self.startsAt = DateParse.iso(event.starts_at)
        self.endsAt = DateParse.iso(event.ends_at)
        self.isChatAdmin = event.my_chat_admin ?? false
        self.tags = (event.tags ?? []).map { ChatTag(name: $0.name, colorHex: $0.color) }
        self.needsPhoto = event.needs_photo ?? false
        self.needsReport = event.needs_report ?? false
        self.hasDocs = event.has_docs ?? false
        self.hasClaim = event.has_claim ?? false
        self.photosRestricted = event.photos_restricted ?? false
    }

    /// Личный чат (ЛС) с сотрудником.
    init(thread: DMThreadDTO) {
        self.init(
            id: "dm-\(thread.worker_id)",
            dealId: "",
            title: thread.fio,
            participantIds: [String(thread.worker_id)],
            lastMessagePreview: Chat.preview(body: thread.last_body, kind: thread.last_kind),
            lastMessageDate: nil,
            unreadCount: thread.unread ?? 0,
            isPhotoReportOpen: false,
            isDirect: true,
            otherUserId: String(thread.worker_id),
            avatarURL: AvatarStore.url(forWorker: thread.worker_id)
        )
    }

    /// Короткое превью последнего сообщения для списка чатов.
    static func preview(body: String?, kind: String?) -> String? {
        if let body, !body.isEmpty { return body }
        switch kind {
        case "image": return "📷 Фото"
        case "video": return "🎬 Видео"
        case "audio": return "🎤 Голосовое"
        case "file":  return "📎 Файл"
        default:      return nil
        }
    }
}

extension Message {
    /// Виды, за которыми стоит содержимое разговора. Всё остальное — служебные
    /// отметки мероприятия (смены, этапы и то, что сервер заведёт дальше).
    ///
    /// Перечисляем именно содержимое, а не служебное: служебных видов
    /// прибавляется — сначала смены, потом этапы, — и список-белый быстро
    /// устаревал бы. Уже устарел один раз: этапы приехали `stage_done` и до
    /// правки рисовались пузырём «Администратор снял(а) отметку с этапа».
    static let contentKinds: Set<String> = ["text", "image", "video", "audio", "file"]

    private static func kind(dto: MessageDTO, hasAttachments: Bool) -> Kind {
        // Вид содержимого проверяем по самому виду, а не по наличию вложения:
        // у видео ссылка приходит отдельным кадром позже, и до неё сообщение
        // ошибочно считалось бы служебным.
        guard contentKinds.contains(dto.kind) else { return .system }
        return hasAttachments ? .photo : .text
    }

    /// Короткое превью для списка чатов.
    var previewText: String {
        if let t = text, !t.isEmpty { return t }
        if let a = attachments.first {
            if a.isVideo { return "🎬 Видео" }
            if a.isAudio { return "🎤 Голосовое" }
            if a.isFile { return "📎 " + (a.fileName ?? "Файл") }
            return "📷 Фото"
        }
        return ""
    }

    init(dto: MessageDTO, chatId forcedChatId: String? = nil) {
        var attachments: [Attachment] = []
        if let media = dto.media_url, !media.isEmpty {
            attachments.append(Attachment(
                id: "\(dto.id)-media",
                localImageName: nil,
                remoteURL: URL(string: media),
                fileName: dto.media_name,
                sizeBytes: dto.media_size,
                isVideo: dto.isVideo,
                isFile: dto.isFile,
                isAudio: dto.isAudio,
                width: dto.img_w ?? 0,
                height: dto.img_h ?? 0,
                thumbURL: dto.thumb_url.flatMap { URL(string: $0) },
                downloadURL: dto.download_url.flatMap { URL(string: $0) }
            ))
        }
        let computedChatId = dto.event_id.map { "chat-\($0)" } ?? (dto.dm_key.map { "dm-\($0)" } ?? "")
        self.init(
            id: String(dto.id),
            chatId: forcedChatId ?? computedChatId,
            senderId: String(dto.sender_id),
            senderName: dto.sender_fio,
            senderAvatarURL: AvatarStore.url(forWorker: dto.sender_id),
            text: dto.body,
            attachments: attachments,
            sentAt: DateParse.iso(dto.created_at) ?? Date(),
            kind: Self.kind(dto: dto, hasAttachments: !attachments.isEmpty)
        )
        self.reactions = (dto.reactions ?? []).map {
            Reaction(emoji: $0.emoji, workerId: String($0.worker_id))
        }
        self.replyToId = dto.reply_to.map(String.init)
        if let r = dto.reply {
            self.replySender = r.sender_fio
            self.replyPreview = (r.body?.isEmpty == false)
                ? r.body
                : (Chat.preview(body: nil, kind: r.kind) ?? "Вложение")
        }
        self.editedAt = DateParse.iso(dto.edited_at)
        self.forwardedFrom = dto.forwarded_from
        self.forwardedFromId = dto.forwarded_from_id.map(String.init)
        self.albumId = dto.album_id
        self.topicId = dto.topic_id
        self.inPhotobank = dto.in_photobank ?? false
    }
}
