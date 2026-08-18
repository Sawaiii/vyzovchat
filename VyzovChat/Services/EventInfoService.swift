import Foundation

/// Обвязка мероприятия: оборудование, документы (акты), претензии и приглашения.
///
/// Всё это правит админ чата — обычный участник только смотрит. Права приходят
/// в карточке мероприятия (`me_is_chat_admin`, `me_can_invite`), поэтому здесь
/// их не проверяем: сервер всё равно ответит `chat_admin_only`.
protocol EventInfoServicing {
    // Оборудование
    func equipment(dealId: String) async -> [EquipmentDTO]
    /// Весь состав заказа: с услугами, работами и транспортом, но без отметок.
    /// В чеклистах их нет — отмечать там нечего, — а бригаде надо знать, что едет.
    func equipmentBrief(dealId: String) async -> [BriefItemDTO]
    func addEquipment(dealId: String, name: String, qty: Int?) async throws -> EquipmentDTO
    func deleteEquipment(dealId: String, itemId: Int) async throws

    // Документы
    func documents(dealId: String) async -> [DocumentDTO]
    func addDocument(dealId: String, _ req: AddDocumentRequest) async throws -> DocumentDTO
    func deleteDocument(dealId: String, docId: Int) async throws
    // Ручных «отправить в Tony» и «сложить на Диск» здесь больше нет: с 15 августа
    // 2026 документ уходит на Диск сам при добавлении, а в CRM его прокидывает
    // автоматика. Эндпоинты на сервере остались, но кнопок под них нет — иначе
    // одно и то же делается двумя способами и расходится.

    // Претензии
    func claims(dealId: String) async -> [ClaimDTO]
    func createClaim(dealId: String, items: [CreateClaimRequest.Item]) async throws
    /// «Урегулирована» — снимает блокировку завершения мероприятия.
    /// Комментарий обязателен: сервер хранит его у претензии и без него отвечает 400.
    func closeClaim(id: Int, note: String) async throws
    // «Отправить в Tony» у претензии тоже убрана: ущерб прокидывается в CRM по
    // факту фиксации. Статус «отправлена» остался — его ставит сервер.
    func deleteClaim(id: Int) async throws

    // Приглашения
    /// Ссылка-приглашение. Роль: member (подрядчик), manager, warehouse.
    /// Куратор может звать только подрядчиков — сервер понизит роль сам.
    func createInvite(dealId: String, role: String) async throws -> InviteDTO
}

final class RealEventInfoService: EventInfoServicing {

    // MARK: - Оборудование

    func equipment(dealId: String) async -> [EquipmentDTO] {
        (try? await APIClient.shared.get("/api/events/\(dealId)/equipment", as: [EquipmentDTO].self)) ?? []
    }

    func equipmentBrief(dealId: String) async -> [BriefItemDTO] {
        (try? await APIClient.shared.get("/api/events/\(dealId)/equipment/brief",
                                         as: [BriefItemDTO].self)) ?? []
    }

    func addEquipment(dealId: String, name: String, qty: Int?) async throws -> EquipmentDTO {
        try await APIClient.shared.post("/api/events/\(dealId)/equipment",
                                        json: AddEquipmentRequest(name: name, qty: qty),
                                        as: EquipmentDTO.self)
    }

    func deleteEquipment(dealId: String, itemId: Int) async throws {
        _ = try await APIClient.shared.delete("/api/events/\(dealId)/equipment/\(itemId)", as: OKDTO.self)
    }

    // MARK: - Документы

    func documents(dealId: String) async -> [DocumentDTO] {
        (try? await APIClient.shared.get("/api/events/\(dealId)/documents", as: [DocumentDTO].self)) ?? []
    }

    func addDocument(dealId: String, _ req: AddDocumentRequest) async throws -> DocumentDTO {
        try await APIClient.shared.post("/api/events/\(dealId)/documents", json: req, as: DocumentDTO.self)
    }

    func deleteDocument(dealId: String, docId: Int) async throws {
        _ = try await APIClient.shared.delete("/api/events/\(dealId)/documents/\(docId)", as: OKDTO.self)
    }

    // MARK: - Претензии

    func claims(dealId: String) async -> [ClaimDTO] {
        (try? await APIClient.shared.get("/api/events/\(dealId)/claims", as: [ClaimDTO].self)) ?? []
    }

    func createClaim(dealId: String, items: [CreateClaimRequest.Item]) async throws {
        struct CreatedDTO: Decodable { let id: Int }
        _ = try await APIClient.shared.post("/api/events/\(dealId)/claims",
                                            json: CreateClaimRequest(items: items), as: CreatedDTO.self)
    }

    func closeClaim(id: Int, note: String) async throws {
        _ = try await APIClient.shared.post("/api/claims/\(id)/close",
                                            json: CloseClaimRequest(note: note), as: OKDTO.self)
    }

    func deleteClaim(id: Int) async throws {
        _ = try await APIClient.shared.delete("/api/claims/\(id)", as: OKDTO.self)
    }

    // MARK: - Приглашения

    func createInvite(dealId: String, role: String) async throws -> InviteDTO {
        try await APIClient.shared.post("/api/events/\(dealId)/invite",
                                        json: CreateInviteRequest(role: role), as: InviteDTO.self)
    }
}

final class MockEventInfoService: EventInfoServicing {
    func equipment(dealId: String) async -> [EquipmentDTO] { [] }
    func equipmentBrief(dealId: String) async -> [BriefItemDTO] { [] }
    func addEquipment(dealId: String, name: String, qty: Int?) async throws -> EquipmentDTO {
        EquipmentDTO(id: 0, name: name, qty: qty, crm_url: nil,
                     warehouse_id: nil, warehouse_name: nil,
                     loaded_at: nil, loaded_by: nil, loaded_impl_at: nil, loaded_impl_by: nil,
                     arrived_at: nil, arrived_by: nil, dismantled_at: nil, dismantled_by: nil,
                     returned_at: nil, returned_by: nil,
                     claim_status: nil, claim_note: nil)
    }
    func deleteEquipment(dealId: String, itemId: Int) async throws {}
    func documents(dealId: String) async -> [DocumentDTO] { [] }
    func addDocument(dealId: String, _ req: AddDocumentRequest) async throws -> DocumentDTO {
        DocumentDTO(id: 0, type: req.type, title: req.title, file_name: req.name, file_size: req.size,
                    file_url: nil, download_url: nil, body: req.body, sent_to_tony: false, created_at: nil)
    }
    func deleteDocument(dealId: String, docId: Int) async throws {}
    func claims(dealId: String) async -> [ClaimDTO] { [] }
    func createClaim(dealId: String, items: [CreateClaimRequest.Item]) async throws {}
    func closeClaim(id: Int, note: String) async throws {}
    func deleteClaim(id: Int) async throws {}
    func createInvite(dealId: String, role: String) async throws -> InviteDTO {
        InviteDTO(token: "mock", path: "/join/mock", role: role, event_name: nil)
    }
}
