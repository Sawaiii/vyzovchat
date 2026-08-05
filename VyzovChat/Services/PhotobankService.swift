import Foundation

// MARK: - DTO фотобанка (теговая библиотека)

/// Тег фото: `source` = "ai" (сгенерирован ИИ) или "admin" (проставлен вручную).
struct PhotobankTagDTO: Decodable, Hashable {
    let tag: String
    let source: String?
}

/// Фото из фотобанка (виртуальный каталог — фото ищутся по тегам из БД).
///
/// Ключи объектов наружу не отдаются: сервер присылает уже подписанные ссылки
/// на оригинал, превью и скачивание. Живут они сутки — после этого список
/// нужно перезапросить, «починить» старую ссылку нельзя.
struct PhotobankItemDTO: Decodable, Identifiable, Hashable {
    let id: Int
    let event_id: Int?
    let event_name: String?
    let created_at: String?
    let sender_fio: String?
    let moderated: Bool?
    /// Мероприятие с запретом на использование фото.
    let restricted: Bool?
    let media_url: String?
    let thumb_url: String?
    let download_url: String?
    let tags: [PhotobankTagDTO]?

    var imageURL: URL? { AppConfig.mediaURL(media_url) }
    /// Что показывать в сетке: лёгкое превью, если оно есть.
    var previewURL: URL? { AppConfig.mediaURL(thumb_url) ?? imageURL }
    var isNew: Bool { !(moderated ?? true) }
    var tagList: [PhotobankTagDTO] { tags ?? [] }
}

struct PhotobankListDTO: Decodable { let items: [PhotobankItemDTO] }

/// Фасет: тег + сколько фото с ним (для облака тегов и подсказок).
struct PhotobankFacetDTO: Decodable, Hashable, Identifiable {
    let tag: String
    let count: Int
    var id: String { tag }
}

/// Счётчики: всего фото и сколько «новых» (непросмотренных админом).
struct PhotobankCountsDTO: Decodable {
    let total: Int
    let newCount: Int
    enum CodingKeys: String, CodingKey { case total; case newCount = "new" }

    init(total: Int, newCount: Int) { self.total = total; self.newCount = newCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        newCount = (try? c.decode(Int.self, forKey: .newCount)) ?? 0
    }
}

/// Как объединять выбранные теги: все сразу (and) или любой из (or).
enum PhotobankOp: String { case and, or }

// MARK: - Сервис

protocol PhotobankServicing {
    /// Поиск фото по тегам (+фильтр по мероприятию и «только новые»).
    /// `nil` — запрос не удался; это не то же самое, что «ничего не нашлось».
    func search(tags: [String], op: PhotobankOp, event: Int?, onlyNew: Bool) async -> [PhotobankItemDTO]?
    /// Облако доступных тегов с количеством.
    func facets() async -> [PhotobankFacetDTO]?
    /// Счётчики всего/новые.
    func counts() async -> PhotobankCountsDTO
    /// Словарь общих ИИ-тегов (для подсказок при вводе).
    func taxonomy() async -> [String]
    // Правки (только глобальный админ):
    func addTag(itemId: Int, tag: String) async
    func removeTag(itemId: Int, tag: String) async
    func markModerated(itemId: Int) async
    /// Убрать фото из фотобанка (в чате оно остаётся).
    func remove(itemId: Int) async
    /// Скачать выбранные фото одним архивом.
    func zip(ids: [Int]) async throws -> URL
}

final class RealPhotobankService: PhotobankServicing {
    private func path(_ base: String, _ items: [URLQueryItem]) -> String {
        var comps = URLComponents()
        comps.path = base
        comps.queryItems = items.isEmpty ? nil : items
        return comps.string ?? base
    }

    func search(tags: [String], op: PhotobankOp, event: Int?, onlyNew: Bool) async -> [PhotobankItemDTO]? {
        var q: [URLQueryItem] = []
        if !tags.isEmpty {
            q.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
            q.append(URLQueryItem(name: "op", value: op.rawValue))
        }
        if let event { q.append(URLQueryItem(name: "event", value: String(event))) }
        if onlyNew { q.append(URLQueryItem(name: "status", value: "new")) }
        return try? await APIClient.shared.get(path("/api/photobank", q), as: PhotobankListDTO.self).items
    }

    func facets() async -> [PhotobankFacetDTO]? {
        try? await APIClient.shared.get("/api/photobank/tags", as: [PhotobankFacetDTO].self)
    }

    func counts() async -> PhotobankCountsDTO {
        (try? await APIClient.shared.get("/api/photobank/counts", as: PhotobankCountsDTO.self))
            ?? PhotobankCountsDTO(total: 0, newCount: 0)
    }

    func taxonomy() async -> [String] {
        (try? await APIClient.shared.get("/api/photobank/taxonomy", as: [String].self)) ?? []
    }

    // Пути правок изменились: было /api/photobank/item/{id}/…, стало /api/photobank/{id}/…
    func addTag(itemId: Int, tag: String) async {
        struct Req: Encodable { let tag: String }
        _ = try? await APIClient.shared.post("/api/photobank/\(itemId)/tags",
                                             json: Req(tag: tag), as: OKDTO.self)
    }

    func removeTag(itemId: Int, tag: String) async {
        let enc = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
        _ = try? await APIClient.shared.delete("/api/photobank/\(itemId)/tags?tag=\(enc)",
                                               as: OKDTO.self)
    }

    func markModerated(itemId: Int) async {
        _ = try? await APIClient.shared.post("/api/photobank/\(itemId)/moderated",
                                             json: EmptyBody(), as: OKDTO.self)
    }

    /// Убрать из фотобанка. Сообщение с фото остаётся в чате: удаляется только
    /// отметка «в фотобанке» — вернуть фото можно повторным отбором.
    func remove(itemId: Int) async {
        _ = try? await APIClient.shared.delete("/api/photobank/\(itemId)", as: OKDTO.self)
    }

    /// Выбранные фото одним архивом — сервер собирает zip и отдаёт файлом.
    func zip(ids: [Int]) async throws -> URL {
        struct Req: Encodable { let ids: [Int] }
        let data = try await APIClient.shared.postRaw("/api/photobank/zip", json: Req(ids: ids))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyzovChat-photos").appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url)
        return url
    }
}

final class MockPhotobankService: PhotobankServicing {
    func search(tags: [String], op: PhotobankOp, event: Int?, onlyNew: Bool) async -> [PhotobankItemDTO]? { [] }
    func facets() async -> [PhotobankFacetDTO]? { [] }
    func counts() async -> PhotobankCountsDTO { PhotobankCountsDTO(total: 0, newCount: 0) }
    func taxonomy() async -> [String] { [] }
    func addTag(itemId: Int, tag: String) async {}
    func removeTag(itemId: Int, tag: String) async {}
    func markModerated(itemId: Int) async {}
    func remove(itemId: Int) async {}
    func zip(ids: [Int]) async throws -> URL { FileManager.default.temporaryDirectory }
}
