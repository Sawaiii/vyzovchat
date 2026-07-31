import Foundation

/// Фото профилей сотрудников.
///
/// В сообщениях и составе мероприятия сервер аватар не присылает — только id
/// отправителя. Готовые подписанные ссылки отдаются одной картой
/// `GET /api/avatars` (id → url), её и держим в памяти: иначе на каждое
/// сообщение в ленте пришлось бы отдельно ходить за картинкой.
///
/// Карта читается при разборе каждого сообщения, а обновляется из фоновой
/// задачи — поэтому доступ под замком.
enum AvatarStore {
    private static let lock = NSLock()
    private static var byWorker: [Int: URL] = [:]
    private static var loadedAt: Date?

    /// Ссылки живут сутки, но перезапрашиваем чаще: сотрудник мог сменить фото.
    private static let ttl: TimeInterval = 30 * 60

    static func url(forWorker id: Int) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return byWorker[id]
    }

    /// Подтянуть карту, если её ещё нет или она устарела.
    static func loadIfNeeded() async {
        lock.lock()
        let fresh = loadedAt.map { Date().timeIntervalSince($0) < ttl } ?? false
        lock.unlock()
        if fresh { return }
        await reload()
    }

    static func reload() async {
        guard let raw = try? await APIClient.shared.get("/api/avatars", as: [String: String].self) else { return }
        var map: [Int: URL] = [:]
        for (key, value) in raw {
            if let id = Int(key), let url = URL(string: value) { map[id] = url }
        }
        lock.lock()
        byWorker = map
        loadedAt = Date()
        lock.unlock()
    }

    /// При выходе из аккаунта — чтобы следующий вход не показал чужие фото.
    static func clear() {
        lock.lock()
        byWorker = [:]
        loadedAt = nil
        lock.unlock()
    }
}
