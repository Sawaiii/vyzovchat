import UIKit

/// Ошибки сетевого слоя с человекочитаемым текстом.
enum APIError: LocalizedError {
    case http(status: Int, serverMessage: String?)
    case decoding
    case transport(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .http(let status, let msg):
            if status == 401 { return "Сессия истекла. Войдите заново." }
            return msg ?? "Ошибка сервера (\(status))"
        case .decoding: return "Не удалось прочитать ответ сервера"
        case .transport(let m): return m
        case .notAuthenticated: return "Требуется вход"
        }
    }
}

/// Тонкий клиент поверх URLSession: JSON-запросы с Bearer-токеном и multipart-загрузка.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Идущие сейчас GET-запросы: одинаковые склеиваем в один.
    private let inflight = InflightRequests()

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        // Раньше стояло waitsForConnectivity = true, и при пропавшей связи запрос
        // не падал, а ЖДАЛ её появления — по умолчанию до недели. Экран при этом
        // просто висел в загрузке. Лучше быстро ошибиться: показанные данные
        // остаются на месте, а человек видит, что связи нет.
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForResource = 60
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
    }

    // MARK: - JSON

    /// GET со склейкой одинаковых запросов.
    ///
    /// Карточку мероприятия одновременно спрашивают три места (лента чата, смены,
    /// экран мероприятия) — без склейки это три одинаковых запроса подряд. Тело
    /// ответа кладём общее, а разбирает его каждый вызывающий сам: по одному пути
    /// разные экраны читают разные части.
    @discardableResult
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        // Запрос собираем заранее: внутрь замыкания склейки уходят только
        // готовый запрос и сессия, без ссылки на клиент.
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStore.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let request = req
        let data = try await inflight.run(key: path) { [session] in
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw APIError.transport("Нет связи с сервером")
            }
            try Self.validate(response, data: data)
            return data
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, json: Encodable?, as type: T.Type) async throws -> T {
        let data = try json.map { try JSONEncoder().encode(AnyEncodable($0)) }
        return try await request(path, method: "POST", body: data, as: type)
    }

    @discardableResult
    func patch<T: Decodable>(_ path: String, json: Encodable?, as type: T.Type) async throws -> T {
        let data = try json.map { try JSONEncoder().encode(AnyEncodable($0)) }
        return try await request(path, method: "PATCH", body: data, as: type)
    }

    @discardableResult
    func put<T: Decodable>(_ path: String, json: Encodable?, as type: T.Type) async throws -> T {
        let data = try json.map { try JSONEncoder().encode(AnyEncodable($0)) }
        return try await request(path, method: "PUT", body: data, as: type)
    }

    /// Строит абсолютный URL запроса. Бросает вместо `!` — путь с пробелами/
    /// спецсимволами (имя файла и т.п.) не должен ронять приложение.
    private func makeURL(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: AppConfig.baseURL) else {
            throw APIError.transport("Некорректный адрес запроса")
        }
        return url
    }

    /// POST, возвращающий бинарные данные (например, zip-архив с диска).
    func postRaw(_ path: String, json: Encodable) async throws -> Data {
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStore.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(AnyEncodable(json))
        let (data, response) = try await session.data(for: req)
        try Self.validate(response, data: data)
        return data
    }

    @discardableResult
    func delete<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await request(path, method: "DELETE", body: nil, as: type)
    }

    private func request<T: Decodable>(_ path: String, method: String, body: Data?, as type: T.Type) async throws -> T {
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStore.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport("Нет связи с сервером")
        }
        try Self.validate(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - Загрузка файла прямо в хранилище

    /// PUT по подписанной ссылке из `/api/uploads/presign`. Файл идёт в S3 мимо
    /// приложения, поэтому здесь нет ни токена, ни базового адреса — и заголовок
    /// `Content-Type` обязан в точности совпасть с тем, под который выдана подпись,
    /// иначе хранилище отклонит запрос.
    func putToStorage(urlString: String, data: Data, contentType: String,
                      onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let url = URL(string: urlString) else {
            throw APIError.transport("Некорректный адрес загрузки")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // Делегат нужен только ради прогресса: без него человек не понимает,
        // идёт ли отправка вообще.
        let delegate = onProgress.map(UploadProgressDelegate.init)
        let (body, response) = try await session.upload(for: req, from: data, delegate: delegate)
        try Self.validate(response, data: body)
    }

    // MARK: - Общая проверка ответа

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Некорректный ответ")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ServerErrorDTO.self, from: data))?.error
            throw APIError.http(status: http.statusCode, serverMessage: msg)
        }
    }
}

/// Обёртка для кодирования произвольного Encodable.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
