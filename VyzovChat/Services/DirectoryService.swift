import Foundation

/// Справочники сервера: мероприятия, сотрудники, компании.
/// (Раньше этот слой назывался «Битрикс» — интеграции с ним нет,
/// все данные приходят из самого Vyzov Chat.)
/// Кого спрашиваем у `/api/workers`.
///
/// По умолчанию сервер отдаёт всех, кроме гостей склада: их зовут на одно
/// мероприятие по ссылке, и в общем списке (упоминания, пересылка, состав)
/// они только мешают.
enum WorkersScope: String {
    /// Штат — список «Роли и персонал».
    case staff
    /// Пришедшие по ссылке: склад и подрядчики.
    case guests
    /// Все, кроме гостей склада, — поведение сервера по умолчанию.
    case `default` = ""
}

protocol DirectoryServicing {
    func fetchDeals(for user: User) async -> [Deal]
    func fetchColleagues() async -> [User]
    /// Люди организации с фильтром: штат, гости или всё остальное.
    func fetchWorkers(scope: WorkersScope) async -> [User]
    /// Удалить сотрудника (админ; реализатор — только своих). Себя удалить нельзя.
    func deleteWorker(id: String) async throws
    /// Участники конкретного мероприятия с ролью в составе.
    func members(dealId: String) async -> [User]
    /// Создать мероприятие (только админ). Возвращает id созданного.
    func createEvent(_ req: CreateEventRequest) async throws -> String
    /// Компании (бренды) организации.
    func fetchCompanies() async -> [CompanyDTO]
    /// Карточка мероприятия из списка (для предзаполнения формы правки).
    func event(id: String) async -> EventDTO?
    /// Изменить мероприятие (админ этого чата, не только глобальный админ).
    func updateEvent(id: String, _ req: UpdateEventRequest) async throws
    /// Убрать мероприятие в архив или вернуть из него (админ чата).
    func archiveEvent(id: String, archived: Bool) async throws
    /// Удалить мероприятие (только глобальный админ).
    func deleteEvent(id: String) async throws
    /// Добавить участника в мероприятие (админ чата).
    func addMember(dealId: String, workerId: String, role: String) async throws
    /// Убрать участника (админ чата).
    func removeMember(dealId: String, workerId: String) async throws
    /// Роль участника: admin | senior | member | observer | storekeeper.
    /// Раздаёт владелец, руководитель или реализатор своей компании.
    func setMemberRole(dealId: String, workerId: String, role: String) async throws

    /// Словарь меток организации (создаёт и удаляет их админ).
    func tags() async -> [EventTagDTO]
    /// Метки мероприятия и признаки «нужны фото» / «нужен отчёт» / «фото нельзя
    /// использовать» — всё это один запрос (админ чата).
    func setEventTags(dealId: String, tagIds: [Int],
                      needsPhoto: Bool, needsReport: Bool, photosRestricted: Bool) async throws

    // Сотрудники (только глобальный админ)
    func createWorker(_ req: CreateWorkerRequest) async throws -> User
    func updateWorker(id: String, _ req: UpdateWorkerRequest) async throws -> User
}

final class MockDirectoryService: DirectoryServicing {
    func fetchDeals(for user: User) async -> [Deal] {
        try? await Task.sleep(for: .milliseconds(500))
        return MockData.deals
            .filter { $0.assignedUserIds.contains(user.workerId) }
            .sorted { ($0.eventDate ?? .distantPast) > ($1.eventDate ?? .distantPast) }
    }

    func fetchColleagues() async -> [User] { MockData.allUsers }

    func fetchWorkers(scope: WorkersScope) async -> [User] { MockData.allUsers }

    func deleteWorker(id: String) async throws {}

    func members(dealId: String) async -> [User] {
        guard let deal = MockData.deals.first(where: { $0.id == dealId }) else { return [] }
        return deal.assignedUserIds.compactMap { MockData.user(id: $0) }
    }

    func createEvent(_ req: CreateEventRequest) async throws -> String { "mock" }

    func fetchCompanies() async -> [CompanyDTO] { [] }

    func event(id: String) async -> EventDTO? { nil }

    func updateEvent(id: String, _ req: UpdateEventRequest) async throws {}
    func archiveEvent(id: String, archived: Bool) async throws {}
    func deleteEvent(id: String) async throws {}
    func addMember(dealId: String, workerId: String, role: String) async throws {}
    func removeMember(dealId: String, workerId: String) async throws {}
    func setMemberRole(dealId: String, workerId: String, role: String) async throws {}
    func tags() async -> [EventTagDTO] { [] }
    func setEventTags(dealId: String, tagIds: [Int],
                      needsPhoto: Bool, needsReport: Bool, photosRestricted: Bool) async throws {}
    func createWorker(_ req: CreateWorkerRequest) async throws -> User { MockData.currentUser }
    func updateWorker(id: String, _ req: UpdateWorkerRequest) async throws -> User { MockData.currentUser }
}
