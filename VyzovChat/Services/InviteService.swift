import Foundation

/// Приглашение по ссылке `/join/<token>`.
///
/// Ссылку выдаёт админ чата (подрядчику) или кладовщику — она живёт в карточке
/// сделки в CRM и потому бессрочная. Приложение умеет её принимать так же, как
/// веб: гость склада называет себя, подрядчик регистрируется или входит.
enum InviteService {

    /// Что за приглашение. Запрос публичный, но токен мы всё равно отправляем
    /// (APIClient делает это сам): по нему сервер отвечает `member: true`, если
    /// человек в этом мероприятии уже состоит.
    static func info(token: String) async throws -> InviteInfoDTO {
        try await APIClient.shared.get("/api/invite/\(token)", as: InviteInfoDTO.self)
    }

    /// Принять приглашение. Возвращает карточку, токен и id мероприятия.
    static func accept(token: String, _ body: AcceptInviteRequest) async throws -> AcceptInviteResponseDTO {
        try await APIClient.shared.post("/api/invite/\(token)/accept",
                                        json: body, as: AcceptInviteResponseDTO.self)
    }
}

/// Разбор ссылки-приглашения.
///
/// Универсальные ссылки (`https://vyzovchat.ru/join/…`) требуют файла
/// apple-app-site-association на сервере, а сервер не наш. Поэтому ловим свою
/// схему `vyzovchat://join/<token>`, а веб-ссылку разбираем, когда её вставили
/// руками из переписки: практически это главный путь — ссылку присылают в
/// мессенджере, человек копирует её целиком.
enum InviteLink {

    /// Вытащить токен из ссылки любого вида или из голого токена.
    static func token(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text) {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            // vyzovchat://join/<token> — «join» приезжает хостом, а не путём
            if url.host == "join", let last = parts.last { return last }
            if let idx = parts.firstIndex(of: "join"), idx + 1 < parts.count {
                return parts[idx + 1]
            }
        }
        // Голый токен: длинная строка без пробелов и косых черт.
        if !text.contains("/"), !text.contains(" "), text.count >= 16 { return text }
        return nil
    }
}
