import Foundation

/// Этапы мероприятия и чеклист оборудования.
///
/// Порядок этапов держит сервер: он же отказывает, если пытаются перепрыгнуть
/// или закрыть погрузку с неотмеченным оборудованием. Здесь только вызовы и
/// разбор отказа на понятный повод — числа для текста берём из уже загруженной
/// сводки, сервер их в ошибке не повторяет.
enum StagesService {

    /// Почему сервер отказал отмечать этап.
    enum StageError: Error {
        /// Не закрыт предыдущий этап.
        case order
        /// Не отмечено оборудование в чеклисте этого этапа.
        case checklist
        case failed
    }

    static func stages(dealId: String) async -> StagesDTO? {
        try? await APIClient.shared.get("/api/events/\(dealId)/stages", as: StagesDTO.self)
    }

    static func setStage(dealId: String, stage: EventStage, done: Bool) async throws {
        do {
            _ = try await APIClient.shared.post("/api/events/\(dealId)/stages/\(stage.rawValue)",
                                                json: SetStageRequest(done: done), as: OKDTO.self)
        } catch let APIError.http(_, message) {
            switch message {
            case "stage_order":           throw StageError.order
            case "checklist_incomplete":  throw StageError.checklist
            default:                      throw StageError.failed
            }
        } catch {
            throw StageError.failed
        }
    }

    static func check(dealId: String, itemId: Int, kind: EquipCheckKind, on: Bool) async throws {
        _ = try await APIClient.shared.post("/api/events/\(dealId)/equipment/\(itemId)/check",
                                            json: EquipCheckRequest(kind: kind.rawValue, on: on),
                                            as: OKDTO.self)
    }
}
