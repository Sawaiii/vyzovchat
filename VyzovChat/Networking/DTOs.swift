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
    /// Компании, чьи чаты ведёт реализатор: их он отмечает сам в своей карточке.
    /// Одной компании ему мало — в CRM она проставлена не у всех.
    let company_ids: [Int]?
    let last_seen: String?
    /// Уволен: в списках не показывается и войти не может, история цела.
    let archived_at: String?
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

/// `POST /api/workers`. Поля `is_admin` в теле больше нет: с миграции 00044
/// полные права даёт только роль (`owner`/`leader`), сервер считает их сам.
struct CreateWorkerRequest: Encodable {
    let fio: String
    let login: String
    let pass: String
    let role: String?
    let is_leader: Bool
    let email: String?
    let phone: String?
    /// Основная компания — сервер принимает её сразу при заведении.
    var company_id: Int? = nil
}

/// `PATCH /api/workers/{id}` — все поля необязательные, шлём только изменённые.
/// Отдельного `PATCH /api/me` на сервере нет: свою карточку правим этим же путём.
struct UpdateWorkerRequest: Encodable {
    var fio: String?
    /// Ведущее поле: от роли сервер считает и `is_admin`, и стартовую страницу.
    var role: String?
    var is_curator: Bool?
    var pass: String?
    var company_id: Int?     // -1 = отвязать компанию
    /// Набор компаний реализатора. Его правит и сам реализатор в своей карточке.
    var company_ids: [Int]?
    /// Уволен: пропадает из списков и не может войти; история остаётся.
    var archived: Bool?
    var email: String?       // "" = очистить
    var phone: String?       // "" = очистить
    var avatar: String?      // S3-ключ из presign; "" = убрать фото
}

/// Строка журнала действий — `GET /api/audit`.
struct AuditEntryDTO: Decodable, Identifiable {
    let id: Int
    let actor_fio: String
    /// delete_message | delete_event | delete_worker | delete_disk_files |
    /// remove_from_photobank | cancel_shift
    let action: String
    let object: String
    let details: String
    let created_at: String

    var actionTitle: String {
        switch action {
        case "delete_message":       return "Удалено сообщение"
        case "delete_event":         return "Удалено мероприятие"
        case "delete_worker":        return "Удалён сотрудник"
        case "delete_disk_files":    return "Удалено с Диска"
        case "remove_from_photobank": return "Убрано из фотобанка"
        case "cancel_shift":         return "Отменена смена"
        default:                     return action
        }
    }

    var icon: String {
        switch action {
        case "delete_message":        return "text.bubble"
        case "delete_event":          return "calendar.badge.minus"
        case "delete_worker":         return "person.badge.minus"
        case "delete_disk_files":     return "folder.badge.minus"
        case "remove_from_photobank": return "photo.badge.minus"
        case "cancel_shift":          return "clock.badge.xmark"
        default:                      return "trash"
        }
    }
}

/// Компания (бренд) — `GET /api/companies`.
struct CompanyDTO: Decodable, Identifiable {
    let id: Int
    let code: String
    let name: String
    /// Как компания зовётся в Tony («Аренда Плюс» против «А+») — по нему сервер
    /// сопоставляет людей при заведении из CRM.
    let crm_name: String?
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
    /// Моя роль в составе: admin | senior | member | observer | storekeeper.
    /// Пусто — меня в составе нет (так админ видит чужие мероприятия).
    let my_role: String?
    /// Служебный чат («Жалобы») — не мероприятие: в нём нет ни этапов, ни смен.
    let system: Bool?
    /// Площадка и ссылка на сделку — приходят из CRM, видны всем в шапке чата.
    let address: String?
    let crm_url: String?
    /// Когда в чате писали в последний раз — по нему сортируется список.
    let last_at: String?
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
    /// Галочки в складской половине чеклиста загрузки и в приёмке (кладовщик).
    let equip_check: Bool?
    /// …в половине реализации на загрузке (админ чата).
    let equip_check_impl: Bool?
    /// …и в сверке на площадке: приезд и демонтаж (старший, плюс админ чата —
    /// иначе без назначенного старшего мероприятие встанет).
    let equip_check_site: Bool?
    /// Опрос клиента: выдать ссылку и посмотреть отзывы.
    let review: Bool?
    /// Добавить и удалить позицию оборудования.
    let equip_edit: Bool?
    /// Отметить свою смену: не для наблюдателя и кладовщика.
    let checkin: Bool?
    /// Раздавать роли в чате — владелец, руководитель, реализатор своей компании.
    let assign: Bool?
    /// Объявить важное с отметкой «Ознакомлен»: админ чата, старший, наблюдатель.
    let alarm: Bool?
    /// Править и отменять смены задним числом — только руководство (админ,
    /// руководитель, реализатор своих компаний). Админу чата этого мало.
    let shift_cancel: Bool?

    /// Отмечаться «ознакомлен» положено участнику и старшему: у админа чата,
    /// кладовщика и наблюдателя такой кнопки нет — иначе список никогда не
    /// станет полным.
    var canAck: Bool { role == "member" || role == "senior" }
}

/// `GET /api/messages/{id}/acks` — кто отметился, а кто ещё нет.
struct AckPersonDTO: Decodable, Identifiable {
    let id: Int
    let fio: String
    /// Роль в мероприятии.
    let role: String
    let done: Bool
    /// Когда отметился (пусто — ещё нет).
    let at: String?
}

/// `POST /api/events/{id}/alarm` — важное объявление в тему.
struct AlarmRequest: Encodable {
    let topic_id: Int?
    let text: String
}

// MARK: - Жалобы

/// Жалоба на человека — всегда в рамках мероприятия. Уходит тому, кто завёл чат,
/// в его служебный чат «Жалобы»; если жалуются на него самого — руководителю.
struct ComplaintDTO: Decodable, Identifiable {
    let id: Int
    let event_id: Int
    let event_name: String?
    let about_id: Int
    let about_fio: String?
    let author_id: Int
    let author_fio: String?
    let body: String
    /// new | done
    let status: String
    let closed_fio: String?
    let closed_at: String?
    let created_at: String

    var isNew: Bool { status == "new" }
}

struct ComplaintsDTO: Decodable {
    let items: [ComplaintDTO]
    /// Сколько неразобранных — по нему горит счётчик в профиле.
    let new: Int?
}

struct CreateComplaintRequest: Encodable {
    let about_id: Int
    let body: String
}

// MARK: - Карточка человека: награды, оценка, компетенции

struct AchievementDTO: Decodable, Identifiable {
    let code: String
    let title: String
    /// Живое число под наградой: сколько на самом деле выездов, фото, часов.
    let note: String
    /// Имя файла герба на сервере — картинок у нас нет, рисуем свой значок.
    let image: String?

    var id: String { code }
}

struct RatingDTO: Decodable {
    /// Среднее по всем оценкам; 0 — ещё не оценивали.
    let avg: Double
    let count: Int
    /// Моя оценка, 0 — я не оценивал.
    let mine: Int

    /// «5,0 (3)» — как в вебе: запятая и число оценивших.
    var text: String? {
        guard count > 0 else { return nil }
        return String(format: "%.1f", avg).replacingOccurrences(of: ".", with: ",") + " (\(count))"
    }
}

/// `GET /api/workers/{id}/profile` — социальная часть карточки.
struct ProfileExtraDTO: Decodable {
    let achievements: [AchievementDTO]?
    let rating: RatingDTO?
    let skills: [String]?
    /// Могу ли я оценивать и размечать компетенции (руководство и реализаторы).
    let can_rate: Bool?
}

struct SetRatingRequest: Encodable { let stars: Int }
struct AddSkillRequest: Encodable { let skill: String }

// MARK: - Опрос клиента

/// Ссылка на опрос и пришедший по ней отзыв (`GET /api/events/{id}/reviews`).
struct ReviewDTO: Decodable, Identifiable {
    let id: Int
    let url: String
    let created_at: String?
    let filled_at: String?
    /// Оценки 1…10 по четырём вопросам; пусто — опрос ещё не заполнен.
    let team: Int?
    let senior: Int?
    let equipment: Int?
    let manager: Int?
    let comment: String?

    var isFilled: Bool { filled_at != nil }

    /// Средняя оценка по четырём вопросам.
    var average: Double? {
        let scores = [team, senior, equipment, manager].compactMap { $0 }
        guard scores.count == 4 else { return nil }
        return Double(scores.reduce(0, +)) / 4
    }
}

struct CreateReviewDTO: Decodable {
    let id: Int
    let token: String
    let url: String
}

// MARK: - Этапы мероприятия

/// Пройденный этап: погрузка → приезд/монтаж → готовность → демонтаж → приёмка.
struct StageDTO: Decodable {
    let stage: String
    let done_at: String
    let done_by: String?
}

/// Сколько позиций оборудования отмечено в каждом чеклисте.
struct EquipProgressDTO: Decodable {
    let total: Int
    let loaded: Int
    /// Сторона реализации на загрузке.
    let loaded_impl: Int?
    /// Сверка на площадке: приезд и демонтаж.
    let arrived: Int?
    let dismantled: Int?
    let returned: Int

    /// Сколько отмечено в конкретном чеклисте.
    func done(_ kind: EquipCheckKind) -> Int {
        switch kind {
        case .loaded:     return loaded
        case .loadedImpl: return loaded_impl ?? 0
        case .arrived:    return arrived ?? 0
        case .dismantled: return dismantled ?? 0
        case .returned:   return returned
        }
    }
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
struct CheckinDTO: Decodable, Identifiable {
    /// Смена на мероприятии одна на человека — id сотрудника её и опознаёт.
    var id: Int { worker_id }
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
    /// Кто, когда и что именно правил руками: вход / выход / диапазон /
    /// снято завершение. Без этого в сводке появляются часы, которых никто
    /// не проставлял.
    let edited_by: String?
    let edited_at: String?
    let edited_what: String?
    /// Селфи с площадки при отметке — подписанная ссылка (ключ наружу не отдают).
    let photo_url: String?

    /// Смену правили задним числом — строкой под отметкой.
    var editNote: String? {
        guard let who = edited_by, !who.isEmpty else { return nil }
        let what = (edited_what?.isEmpty == false) ? edited_what! : "время"
        return "правил(а) \(who): \(what)"
    }

    /// Сколько метров между началом и концом смены.
    ///
    /// Координаты завершения сервер писал и раньше, но их никто не показывал:
    /// смену закрывали по дороге домой, и в сводке это выглядело обычной сменой.
    var finishDistance: Double? {
        guard let lat1 = geo_lat, let lng1 = geo_lng,
              let lat2 = finish_lat, let lng2 = finish_lng else { return nil }
        return GeoDistance.meters(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2)
    }

    /// Смену закрыли далеко от места, где открыли. Порог тот же, что в вебе, —
    /// 500 м: площадка бывает большая, и уходить на сотню метров это норма.
    var finishedFarAway: Bool { (finishDistance ?? 0) > 500 }

    /// «закрыл(а) в 1,2 км от старта» — с расстоянием, иначе пометка без веса.
    var finishFarNote: String? {
        guard finishedFarAway, let d = finishDistance else { return nil }
        return "смену закрыли в " + GeoDistance.text(d) + " от места начала"
    }
}

/// Расстояние между точками. Гаверсинус, а не CoreLocation: нужен один
/// показатель в сводке смен, тащить ради него менеджер локаций незачем.
enum GeoDistance {
    static func meters(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let r = 6_371_000.0                        // средний радиус Земли, м
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lng2 - lng1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Метры до километра, дальше — километры с одним знаком.
    static func text(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) м" }
        return String(format: "%.1f", meters / 1000).replacingOccurrences(of: ".", with: ",") + " км"
    }
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
    // Чеклисты: загрузка (склад и реализация), сверка на приезде и на демонтаже,
    // приёмка — кто и когда отметил.
    let loaded_at: String?
    let loaded_by: String?
    /// Сторона реализации на загрузке: склад выдал, реализация забрала.
    let loaded_impl_at: String?
    let loaded_impl_by: String?
    /// Сверка оборудования на площадке — ведёт старший.
    let arrived_at: String?
    let arrived_by: String?
    let dismantled_at: String?
    let dismantled_by: String?
    let returned_at: String?
    let returned_by: String?
    /// Есть ли претензия по этой позиции: filed | sent | closed. Пусто — претензии нет.
    let claim_status: String?
    /// Чем закончилась, если урегулирована.
    let claim_note: String?

    /// Отмечена ли позиция в чеклисте нужного вида.
    func isChecked(_ kind: EquipCheckKind) -> Bool {
        switch kind {
        case .loaded:     return loaded_at != nil
        case .loadedImpl: return loaded_impl_at != nil
        case .arrived:    return arrived_at != nil
        case .dismantled: return dismantled_at != nil
        case .returned:   return returned_at != nil
        }
    }

    /// Кто отметил — показываем рядом с галочкой.
    func checkedBy(_ kind: EquipCheckKind) -> String? {
        let who: String?
        switch kind {
        case .loaded:     who = loaded_by
        case .loadedImpl: who = loaded_impl_by
        case .arrived:    who = arrived_by
        case .dismantled: who = dismantled_by
        case .returned:   who = returned_by
        }
        return (who?.isEmpty == false) ? who : nil
    }

    /// Заведена ли по позиции претензия — рисуем прямо в чеклисте, чтобы
    /// кладовщик видел, по чему уже есть вопрос, и не заводил вторую.
    var hasClaim: Bool { !(claim_status ?? "").isEmpty }

    /// Подпись претензии рядом с позицией.
    var claimTitle: String? {
        switch claim_status {
        case "closed": return "претензия урегулирована"
        case "sent":   return "претензия в CRM"
        case "filed", "open": return "претензия"
        default:       return nil
        }
    }
}

/// Какой чеклист оборудования.
///
/// Загрузка отмечается дважды: склад — что выдал, реализация — что забрала.
/// Смысл двойной отметки в том, что подпись стоит у обоих, поэтому отметить за
/// другую сторону нельзя. На площадке оборудование сверяет старший — на приезде
/// и на демонтаже; приёмка на складе одна.
enum EquipCheckKind: String, Identifiable {
    case loaded
    case loadedImpl = "loaded_impl"
    case arrived
    case dismantled
    case returned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loaded:     return "Загрузка · склад"
        case .loadedImpl: return "Загрузка · реализация"
        case .arrived:    return "Сверка на приезде"
        case .dismantled: return "Сверка на демонтаже"
        case .returned:   return "Чеклист приёмки"
        }
    }

    /// Какой этап держит этот чеклист.
    var stage: String {
        switch self {
        case .loaded, .loadedImpl: return "load"
        case .arrived:             return "arrive"
        case .dismantled:          return "dismantle"
        case .returned:            return "accept"
        }
    }

    var icon: String {
        switch self {
        case .loaded, .loadedImpl: return "shippingbox"
        case .arrived:             return "checklist"
        case .dismantled:          return "wrench.and.screwdriver"
        case .returned:            return "arrow.down.circle"
        }
    }

    /// Кто отмечает эту половину — подсказка тем, кому кнопки недоступны.
    var owner: String {
        switch self {
        case .loaded:              return "отмечает кладовщик"
        case .loadedImpl:          return "отмечает админ чата"
        case .arrived, .dismantled: return "отмечает старший"
        case .returned:            return "отмечает кладовщик"
        }
    }
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
    /// filed | sent | closed
    let status: String
    let created_at: String?
    let author_fio: String?
    let author_role: String?
    let items: [ClaimItemDTO]?
    /// Чем закончилось — сервер хранит комментарий урегулирования у самой претензии.
    let settled_note: String?
    let settled_fio: String?
    let settled_at: String?

    var isOpen: Bool { status != "closed" }
    var statusTitle: String {
        switch status {
        case "closed": return "Урегулирована"
        case "sent":   return "Отправлена в CRM"
        default:       return "Открыта"
        }
    }
}

/// `POST /api/claims/{id}/close` — комментарий обязателен, пустой сервер не примет.
struct CloseClaimRequest: Encodable { let note: String }

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
    /// Кто и что правил задним числом — в отчёте это должно быть видно.
    let edited_by: String?
    let edited_at: String?
    let edited_what: String?

    var id: String { "\(worker_id)-\(event_id)-\(checked_at)" }

    /// Строка «правил(а) Иванов: выход» — иначе непонятно, откуда часы.
    var editNote: String? {
        guard let who = edited_by, !who.isEmpty else { return nil }
        let what = (edited_what?.isEmpty == false) ? edited_what! : "время"
        return "правил(а) \(who): \(what)"
    }
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

/// `GET /api/invite/{token}` — что за приглашение (публично, токен не нужен).
struct InviteInfoDTO: Decodable {
    let ok: Bool?
    let event_id: Int
    let event_name: String?
    /// member (подрядчик) | storekeeper (склад).
    let role: String
    /// Я уже в этом мероприятии — форма имени не нужна, иначе гость упрётся
    /// в «имя занято» самим собой.
    let member: Bool?
}

/// `POST /api/invite/{token}/accept`.
///
/// Три случая в одном теле: гость склада (только `fio`), вход существующим
/// аккаунтом (`mode: login`) и регистрация подрядчика (`mode: register`).
struct AcceptInviteRequest: Encodable {
    var mode: String?
    var fio: String?
    var phone: String?
    var email: String?
    var login: String?
    var pass: String?

    static func guest(fio: String) -> AcceptInviteRequest {
        AcceptInviteRequest(fio: fio)
    }
    static func login(login: String, pass: String) -> AcceptInviteRequest {
        AcceptInviteRequest(mode: "login", login: login, pass: pass)
    }
    static func register(fio: String, phone: String, email: String,
                         login: String, pass: String) -> AcceptInviteRequest {
        AcceptInviteRequest(mode: "register", fio: fio, phone: phone,
                            email: email, login: login, pass: pass)
    }
}

/// Ответ приёма приглашения: карточка, токен и мероприятие, куда добавили.
struct AcceptInviteResponseDTO: Decodable {
    let worker: WorkerDTO
    let token: String
    let event_id: Int?
}

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
    /// «Ознакомлен»: стоит под вводными из сделки (`crm`) и важным объявлением (`alarm`).
    let needs_ack: Bool?
    let ack_count: Int?
    /// Сколько человек вообще должны отметиться — участники и старшие мероприятия.
    let ack_total: Int?
    let ack_me: Bool?

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
        self.companyIds = dto.company_ids ?? []
        self.isArchived = dto.archived_at != nil
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
        self.myRole = dto.my_role
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
        self.myRole = event.my_role
        self.isSystem = event.system ?? false
        self.address = event.address
        self.crmURL = event.crm_url.flatMap { URL(string: $0) }
        // Время последнего сообщения сервер теперь отдаёт сам — без него список
        // сортировался по «нет даты» и тасовался при каждом обновлении.
        if lastDate == nil, let at = DateParse.iso(event.last_at) {
            self.lastMessageDate = at
        }
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
        self.systemKind = Self.contentKinds.contains(dto.kind) ? nil : dto.kind
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
        self.needsAck = dto.needs_ack ?? false
        self.ackCount = dto.ack_count ?? 0
        self.ackTotal = dto.ack_total ?? 0
        self.ackMe = dto.ack_me ?? false
    }
}
