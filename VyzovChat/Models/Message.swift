import Foundation

/// Сообщение в чате. Может быть текстом, медиа-вложением или системным событием.
struct Message: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let chatId: String
    let senderId: String
    var senderName: String? = nil
    var senderAvatarURL: URL? = nil
    var text: String?
    var attachments: [Attachment]
    let sentAt: Date
    var kind: Kind

    var reactions: [Reaction] = []
    var replyToId: String? = nil
    var replySender: String? = nil       // автор цитируемого сообщения
    var replyPreview: String? = nil      // краткий текст цитаты
    var editedAt: Date? = nil            // время последнего редактирования
    var forwardedFrom: String? = nil     // ФИО исходного автора при пересылке
    /// …и его id — чтобы из пузыря открыть карточку. Может не быть у старых
    /// сообщений: сервер стал сохранять id позже самой пересылки.
    var forwardedFromId: String? = nil
    var albumId: String? = nil           // несколько фото одной отправкой → один альбом
    var topicId: Int? = nil              // подтема мероприятия (nil = канал «Общий»)
    var geoLat: Double? = nil            // геометка съёмки (юр. инфа)
    var geoLng: Double? = nil
    var inPhotobank: Bool = false        // фото уже забрано в фотобанк
    /// Какое именно событие за служебной строкой: shift_in, stage_done и т.д.
    /// Вид с сервера сохраняем — по нему строка красится, иначе все события
    /// мероприятия выглядели бы одинаково серыми.
    var systemKind: String? = nil

    /// Под сообщением стоит отметка «Ознакомлен»: так приходят вводные из сделки
    /// (`crm`) и важное объявление от руководства (`alarm`).
    var needsAck: Bool = false
    var ackCount: Int = 0
    /// Сколько человек должны отметиться — участники и старшие мероприятия.
    var ackTotal: Int = 0
    var ackMe: Bool = false

    /// Врезка, а не пузырь: вводные из сделки, важное объявление, жалоба и отзыв
    /// клиента — это уведомления, а не реплики в переписке.
    var isNotice: Bool {
        ["crm", "alarm", "complaint", "review"].contains(systemKind ?? "")
    }
    /// Важное от руководства (у него, в отличие от вводных, виден автор).
    var isAlarm: Bool { systemKind == "alarm" }
    /// Жалоба в служебном чате.
    var isComplaint: Bool { systemKind == "complaint" }
    /// Отзыв клиента по итогам опроса.
    var isReview: Bool { systemKind == "review" }

    enum Kind: String, Codable {
        case text
        case photo
        case system
    }

    struct Reaction: Codable, Equatable, Hashable {
        let emoji: String
        let workerId: String
    }

    struct Attachment: Identifiable, Codable, Equatable, Hashable {
        let id: String
        var localImageName: String? = nil
        var remoteURL: URL? = nil
        var fileName: String? = nil
        var sizeBytes: Int? = nil
        var isVideo: Bool = false
        var isFile: Bool = false
        /// Голосовое сообщение или звуковой файл — показывается плеером, а не плиткой.
        var isAudio: Bool = false
        var width: Int = 0
        var height: Int = 0
        /// Лёгкое превью для ленты (собирает отправитель). Нет — показываем оригинал.
        var thumbURL: URL? = nil
        /// Ссылка со «скачать» и исходным именем файла — для видео и документов.
        var downloadURL: URL? = nil

        var isImage: Bool { !isVideo && !isFile && !isAudio }

        /// Что показывать в ленте: превью, если есть, иначе оригинал.
        var previewURL: URL? { thumbURL ?? remoteURL }
    }

    var isSystem: Bool { kind == .system }

    struct ReactionCount: Identifiable {
        var id: String { emoji }
        let emoji: String
        let count: Int
    }

    /// Сгруппированные реакции: эмодзи → количество.
    var reactionCounts: [ReactionCount] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for r in reactions {
            if counts[r.emoji] == nil { order.append(r.emoji) }
            counts[r.emoji, default: 0] += 1
        }
        return order.map { ReactionCount(emoji: $0, count: counts[$0] ?? 0) }
    }
}
