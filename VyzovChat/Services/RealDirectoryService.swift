import Foundation

/// Мероприятия, сотрудники и компании из API Vyzov Chat.
final class RealDirectoryService: DirectoryServicing {

    /// Компании кэшируем: в мероприятии приходит только `company_id`,
    /// а показать надо название.
    private static var companies: [CompanyDTO] = []

    func fetchDeals(for user: User) async -> [Deal] {
        let list = await fetchCompanies()
        let byId = Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        do {
            let dtos = try await APIClient.shared.get("/api/events", as: [EventDTO].self)
            return dtos.map { Deal(dto: $0, companyName: $0.company_id.flatMap { byId[$0] }) }
        } catch {
            return []
        }
    }

    func fetchColleagues() async -> [User] {
        do {
            let dtos = try await APIClient.shared.get("/api/workers", as: [WorkerDTO].self)
            return dtos.map(User.init(dto:))
        } catch {
            return []
        }
    }

    /// Состав приходит отдельным списком в карточке мероприятия — с ролью
    /// в этом мероприятии, а не с глобальной ролью сотрудника.
    func members(dealId: String) async -> [User] {
        do {
            let dto = try await APIClient.shared.get("/api/events/\(dealId)", as: EventDetailsDTO.self)
            return dto.members.map(User.init(member:))
        } catch {
            return []
        }
    }

    /// Сервер отвечает только id созданного мероприятия, а не карточкой.
    func createEvent(_ req: CreateEventRequest) async throws -> String {
        struct CreatedDTO: Decodable { let id: Int }
        let dto = try await APIClient.shared.post("/api/events", json: req, as: CreatedDTO.self)
        return String(dto.id)
    }

    func fetchCompanies() async -> [CompanyDTO] {
        if !Self.companies.isEmpty { return Self.companies }
        let list = (try? await APIClient.shared.get("/api/companies", as: [CompanyDTO].self)) ?? []
        Self.companies = list
        return list
    }

    /// Отдельного эндпоинта под одну карточку нет — берём её из списка мероприятий.
    func event(id: String) async -> EventDTO? {
        let list = (try? await APIClient.shared.get("/api/events", as: [EventDTO].self)) ?? []
        return list.first { String($0.id) == id }
    }

    func updateEvent(id: String, _ req: UpdateEventRequest) async throws {
        _ = try await APIClient.shared.patch("/api/events/\(id)", json: req, as: OKDTO.self)
    }

    /// Архив и возврат из него. Если по мероприятию есть незакрытая претензия,
    /// сервер ответит `claim_open` и убрать его не даст.
    func archiveEvent(id: String, archived: Bool) async throws {
        _ = try await APIClient.shared.post("/api/events/\(id)/archive",
                                            json: ArchiveEventRequest(archived: archived), as: OKDTO.self)
    }

    func deleteEvent(id: String) async throws {
        _ = try await APIClient.shared.delete("/api/events/\(id)", as: OKDTO.self)
    }

    func addMember(dealId: String, workerId: String, role: String) async throws {
        guard let wid = Int(workerId) else { return }
        _ = try await APIClient.shared.post("/api/events/\(dealId)/members",
                                            json: AddMemberRequest(worker_id: wid, role: role), as: OKDTO.self)
    }

    func removeMember(dealId: String, workerId: String) async throws {
        _ = try await APIClient.shared.delete("/api/events/\(dealId)/members/\(workerId)", as: OKDTO.self)
    }

    func setMemberRole(dealId: String, workerId: String, role: String) async throws {
        _ = try await APIClient.shared.patch("/api/events/\(dealId)/members/\(workerId)",
                                             json: MemberRoleRequest(role: role), as: OKDTO.self)
    }

    // MARK: - Метки мероприятий

    func tags() async -> [EventTagDTO] {
        (try? await APIClient.shared.get("/api/tags", as: [EventTagDTO].self)) ?? []
    }

    func setEventTags(dealId: String, tagIds: [Int],
                      needsPhoto: Bool, needsReport: Bool, photosRestricted: Bool) async throws {
        _ = try await APIClient.shared.put(
            "/api/events/\(dealId)/tags",
            json: SetEventTagsRequest(tag_ids: tagIds, needs_photo: needsPhoto,
                                      needs_report: needsReport, photos_restricted: photosRestricted),
            as: OKDTO.self)
    }

    // MARK: - Сотрудники

    func createWorker(_ req: CreateWorkerRequest) async throws -> User {
        let dto = try await APIClient.shared.post("/api/workers", json: req, as: WorkerDTO.self)
        await MainActor.run { DirectoryCache.invalidate() }
        return User(dto: dto)
    }

    func updateWorker(id: String, _ req: UpdateWorkerRequest) async throws -> User {
        let dto = try await APIClient.shared.patch("/api/workers/\(id)", json: req, as: WorkerDTO.self)
        await MainActor.run { DirectoryCache.invalidate() }
        return User(dto: dto)
    }
}
