import Foundation

/// Глобальная конфигурация подключения к бэкенду Vyzov Chat.
enum AppConfig {
    /// Базовый адрес API (тот же сервер, что и у веб-версии).
    static let baseURL = URL(string: "https://vyzovchat.ru")!

    /// Использовать моки вместо реального сервера (для офлайн-разработки/превью).
    static let useMockData = false

    /// Адрес WebSocket-канала. Токен передаётся в query — заголовки при
    /// рукопожатии сокета выставить нельзя, сервер это учитывает.
    static func wsURL(token: String) -> URL? {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        comps?.scheme = (baseURL.scheme == "http") ? "ws" : "wss"
        comps?.path = "/ws"
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps?.url
    }

    /// Ссылка на медиа. Сервер отдаёт уже подписанные абсолютные ссылки на S3
    /// (`media_url`, `thumb_url`, `download_url`), поэтому подставлять токен не нужно —
    /// в отличие от прежнего бэкенда, где файлы раздавались самим приложением.
    ///
    /// Подпись живёт сутки: если ссылка протухла, картинку не починить подстановкой —
    /// нужно перезапросить сообщение (лента перечитывается при переподключении сокета).
    static func mediaURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if let url = URL(string: raw) { return url }
        // на всякий случай: имя файла с пробелами/кириллицей
        return raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            .flatMap { URL(string: $0) }
    }

    /// Расширения, которые считаем видео (для корректного отображения).
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp", "avi", "mkv", "webm"]

    /// …и картинками. Список совпадает с белым списком загрузок на сервере.
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

    private static func ext(_ nameOrPath: String?) -> String? {
        guard let s = nameOrPath, let dot = s.lastIndex(of: ".") else { return nil }
        return String(s[s.index(after: dot)...]).lowercased()
    }

    static func isVideo(_ nameOrPath: String?) -> Bool {
        guard let e = ext(nameOrPath) else { return false }
        return videoExtensions.contains(e)
    }

    static func isImage(_ nameOrPath: String?) -> Bool {
        guard let e = ext(nameOrPath) else { return false }
        return imageExtensions.contains(e)
    }

    /// Тип содержимого по имени файла — для прямой заливки в S3.
    /// Сервер всё равно определяет его сам по расширению; здесь нужен
    /// ровно тот же заголовок, иначе подпись не сойдётся.
    static func contentType(for filename: String) -> String {
        switch ext(filename) ?? "" {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":  return "image/png"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "mp4":  return "video/mp4"
        case "mov":  return "video/quicktime"
        case "m4v":  return "video/x-m4v"
        case "pdf":  return "application/pdf"
        default:     return "application/octet-stream"
        }
    }
}
