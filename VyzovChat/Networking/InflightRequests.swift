import Foundation

/// Склейка одинаковых запросов, идущих одновременно.
///
/// Экраны в приложении независимы и спокойно спрашивают одно и то же в один
/// момент: карточку мероприятия одновременно просят лента чата, экран смен и
/// экран мероприятия. Без склейки это три одинаковых обращения к серверу —
/// лишняя нагрузка и на телефон, и на сервер, особенно на слабой связи.
///
/// Здесь ключ — путь запроса. Пока ответ не пришёл, повторные вызовы ждут тот же
/// результат, а не отправляют свой запрос.
actor InflightRequests {
    private var tasks: [String: Task<Data, Error>] = [:]

    func run(key: String, operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let existing = tasks[key] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}
