import UIKit

/// Загрузка вложений в хранилище.
///
/// Схема на новом бэкенде: сначала просим у сервера подписанную ссылку
/// (`POST /api/uploads/presign`), затем кладём файл **прямо в S3** — через
/// приложение он не проходит. В сообщение уходит не путь к файлу, а выданный
/// сервером ключ объекта; ссылки для показа сервер подпишет сам.
///
/// Тип содержимого сервер определяет по расширению имени файла и не доверяет
/// клиенту — поэтому имя должно быть с правильным расширением, иначе загрузка
/// отобьётся как `file_type_not_allowed`.
enum MediaUploader {

    /// Назначение файла — от него зависит папка в хранилище.
    enum Purpose: String {
        case chat                       // фото, видео и файлы чата
        case thumb                      // лёгкое превью для ленты
        case avatar                     // фото профиля
        case eventAvatar = "event-avatar"
        case document                   // документы мероприятия
        case legal                      // кадр со штампом для юр. инфы
    }

    /// Сторона, по которой ужимаем фото перед отправкой: тащить с телефона
    /// оригинал на 12 МБ незачем — в ленте он всё равно показывается меньше.
    private static let maxSide: CGFloat = 1920
    /// Сторона превью: его грузим отдельным объектом, чтобы лента не тянула оригиналы.
    private static let thumbSide: CGFloat = 320

    // MARK: - Общий путь

    /// Получить подпись и залить данные. Возвращает ключ объекта.
    /// `onProgress` — доля отправленного (0…1) для показа хода загрузки.
    static func put(_ data: Data, filename: String, purpose: Purpose, eventId: Int? = nil,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> (key: String, contentType: String) {
        let presign = try await APIClient.shared.post(
            "/api/uploads/presign",
            json: PresignRequest(filename: filename, purpose: purpose.rawValue, event_id: eventId),
            as: PresignDTO.self)
        try await APIClient.shared.putToStorage(urlString: presign.put_url,
                                                data: data,
                                                contentType: presign.content_type,
                                                onProgress: onProgress)
        return (presign.key, presign.content_type)
    }

    // MARK: - Фото

    /// Ужать фото, залить оригинал и превью, вернуть всё для отправки сообщением.
    /// Превью необязательно: если оно не загрузилось, лента покажет оригинал.
    static func uploadImage(_ image: UIImage, filename: String = "IMG.jpg",
                            onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadedMedia {
        let scaled = resized(image, maxSide: maxSide)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else {
            throw UploadError.failed("Не удалось подготовить фото")
        }
        // Оставляем «хвост» под превью: оно грузится следом и тоже занимает время.
        let uploaded = try await put(data, filename: filename, purpose: .chat,
                                     onProgress: { onProgress?($0 * 0.9) })
        var media = UploadedMedia(key: uploaded.key, contentType: uploaded.contentType,
                                  name: filename, size: data.count,
                                  width: Int(scaled.size.width * scaled.scale),
                                  height: Int(scaled.size.height * scaled.scale))
        media.thumbKey = try? await uploadThumb(for: image)
        onProgress?(1)
        return media
    }

    /// Превью: отдельный маленький jpeg. Ошибку глотаем осознанно — без превью
    /// лента работает, а из-за неудачи с ним терять само фото нельзя.
    private static func uploadThumb(for image: UIImage) async throws -> String? {
        guard let data = resized(image, maxSide: thumbSide).jpegData(compressionQuality: 0.6) else { return nil }
        return try await put(data, filename: "thumb.jpg", purpose: .thumb).key
    }

    /// Произвольный файл (видео, документ, архив) — как есть, без обработки.
    static func uploadFile(_ data: Data, filename: String, purpose: Purpose = .chat,
                           onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadedMedia {
        let uploaded = try await put(data, filename: filename, purpose: purpose, onProgress: onProgress)
        return UploadedMedia(key: uploaded.key, contentType: uploaded.contentType,
                             name: filename, size: data.count)
    }

    /// Фото профиля: сервер ждёт уже уменьшенный квадрат. Возвращает ключ —
    /// его нужно передать в `PATCH /api/workers/{id}`.
    static func uploadAvatar(_ image: UIImage, purpose: Purpose = .avatar) async throws -> String {
        let square = cropSquare(image)
        guard let data = resized(square, maxSide: 512).jpegData(compressionQuality: 0.85) else {
            throw UploadError.failed("Не удалось подготовить фото")
        }
        return try await put(data, filename: "avatar.jpg", purpose: purpose).key
    }

    // MARK: - Обработка изображений

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide, side > 0 else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func cropSquare(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        guard side > 0, image.size.width != image.size.height else { return image }
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }
}
