import Foundation

/// Сделка/заказ из Битрикса. При переводе на определённую стадию
/// по сделке автоматически создаётся чат.
struct Deal: Identifiable, Codable, Equatable, Hashable {
    let id: String            // ID сделки в Битриксе
    var title: String         // название мероприятия/заказа
    var stage: Stage
    var address: String?
    var eventDate: Date?
    var assignedUserIds: [String]   // workerId сотрудников на заказе
    var responsibleId: String?      // ответственный
    var archived: Bool = false      // прошедшее мероприятие (в архиве)
    var rawStatus: String = "active"    // active | closed
    var reportStatus: String = "none"   // none | sent
    var company: String? = nil          // компания/бренд (events.folder)

    /// Статусы для отображения бейджами.
    var statusBadges: [(text: String, kind: StatusKind)] {
        var items: [(String, StatusKind)] = []
        items.append(rawStatus == "closed" ? ("Завершено", .neutral) : ("Активно", .active))
        items.append(reportStatus == "sent" ? ("Отчёт отправлен", .success) : ("Нет отчёта", .warning))
        if archived { items.append(("Архив", .neutral)) }
        return items
    }

    enum StatusKind { case active, success, warning, neutral }

    enum Stage: String, Codable, CaseIterable {
        case new = "Новая"
        case prepare = "Подготовка"
        case inProgress = "На мероприятии"
        case photoReport = "Фотоотчёт"
        case done = "Завершена"

        /// Стадия, начиная с которой создаётся рабочий чат.
        var createsChat: Bool {
            switch self {
            case .new, .prepare: return false
            case .inProgress, .photoReport, .done: return true
            }
        }
    }

    /// Имя папки для выгрузки фото на сервер (S3).
    var storageFolder: String {
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safe) (#\(id))"
    }
}
