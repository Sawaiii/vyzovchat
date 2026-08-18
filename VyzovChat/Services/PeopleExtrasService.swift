import Foundation

/// Всё, что появилось вокруг человека и мероприятия помимо переписки:
/// жалобы, социальная часть карточки и опрос клиента.
///
/// Отдельный слой, а не части `DirectoryService`: справочник отвечает за то, кто
/// есть в системе, а здесь — оценки, награды и разбор жалоб, у которых своя жизнь.
enum PeopleExtras {

    // MARK: - Жалобы

    /// Пожаловаться на человека. Только в рамках мероприятия: «плохо работал» без
    /// привязки разбирать бессмысленно. Жалоба уходит тому, кто завёл чат.
    static func complain(dealId: String, aboutId: String, text: String) async throws {
        guard let about = Int(aboutId) else { return }
        _ = try await APIClient.shared.post("/api/events/\(dealId)/complaints",
                                            json: CreateComplaintRequest(about_id: about, body: text),
                                            as: OKDTO.self)
    }

    /// Что мне разбирать (супер-админу — все по организации).
    static func complaints() async -> ComplaintsDTO {
        (try? await APIClient.shared.get("/api/complaints", as: ComplaintsDTO.self))
            ?? ComplaintsDTO(items: [], new: 0)
    }

    /// «Разобрано» — закрывает адресат или супер-админ.
    static func closeComplaint(id: Int) async throws {
        _ = try await APIClient.shared.post("/api/complaints/\(id)/done",
                                            json: EmptyBody(), as: OKDTO.self)
    }

    // MARK: - Карточка человека

    /// Награды, оценка и компетенции. Считаются на месте и к правкам карточки
    /// отношения не имеют — поэтому отдельным запросом.
    static func profile(workerId: String) async -> ProfileExtraDTO? {
        try? await APIClient.shared.get("/api/workers/\(workerId)/profile", as: ProfileExtraDTO.self)
    }

    /// Оценить человека (1…5); 0 снимает свою оценку. Оценивают руководство и
    /// реализаторы, себя — нельзя.
    static func rate(workerId: String, stars: Int) async throws -> RatingDTO {
        try await APIClient.shared.put("/api/workers/\(workerId)/rating",
                                        json: SetRatingRequest(stars: stars), as: RatingDTO.self)
    }

    /// Кто и когда оценил — админу и руководителю (`can_see_ratings`). Средняя не
    /// отвечает на вопрос, откуда она взялась: десять человек так решили или один
    /// пришёл и поставил единицу.
    static func ratingLog(workerId: String) async -> [RaterMarkDTO] {
        (try? await APIClient.shared.get("/api/workers/\(workerId)/ratings",
                                         as: [RaterMarkDTO].self)) ?? []
    }

    static func addSkill(workerId: String, skill: String) async throws -> [String] {
        try await APIClient.shared.post("/api/workers/\(workerId)/skills",
                                         json: AddSkillRequest(skill: skill), as: [String].self)
    }

    static func removeSkill(workerId: String, skill: String) async throws -> [String] {
        let enc = skill.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? skill
        return try await APIClient.shared.delete("/api/workers/\(workerId)/skills?skill=\(enc)",
                                                  as: [String].self)
    }

    /// Подсказки компетенций из уже проставленного — чтобы формулировки не расползались.
    static func skillSuggestions(query: String = "") async -> [String] {
        let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = enc.isEmpty ? "/api/skills" : "/api/skills?q=\(enc)"
        return (try? await APIClient.shared.get(path, as: [String].self)) ?? []
    }

    // MARK: - Опрос клиента

    /// Выдать разовую ссылку на опрос. Заполнить её можно один раз, результат
    /// приходит врезкой в чат мероприятия.
    static func createReview(dealId: String) async throws -> CreateReviewDTO {
        try await APIClient.shared.post("/api/events/\(dealId)/review",
                                         json: EmptyBody(), as: CreateReviewDTO.self)
    }

    /// Выданные ссылки и пришедшие отзывы.
    static func reviews(dealId: String) async -> [ReviewDTO] {
        (try? await APIClient.shared.get("/api/events/\(dealId)/reviews", as: [ReviewDTO].self)) ?? []
    }
}
