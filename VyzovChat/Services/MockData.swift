import Foundation

/// Демо-данные для работы приложения без реального сервера.
enum MockData {

    static let currentUser = User(
        id: "1024",
        workerId: "1024",
        lastName: "Никитин",
        firstName: "Алексей",
        middleName: "Сергеевич",
        phone: "+7 900 123-45-67",
        position: "Выездной техник",
        department: "Отдел мероприятий",
        avatarURL: nil
    )

    static let colleagues: [User] = [
        User(id: "1050", workerId: "1050", lastName: "Смирнова", firstName: "Ольга",
             middleName: "Ивановна", phone: "+7 900 555-11-22",
             position: "Координатор", department: "Отдел мероприятий", avatarURL: nil),
        User(id: "1077", workerId: "1077", lastName: "Петров", firstName: "Дмитрий",
             middleName: nil, phone: "+7 900 777-33-44",
             position: "Фотограф", department: "Медиа", avatarURL: nil),
        User(id: "1090", workerId: "1090", lastName: "Ковалёв", firstName: "Игорь",
             middleName: "Павлович", phone: "+7 900 888-99-00",
             position: "Монтажник", department: "Логистика", avatarURL: nil)
    ]

    static var allUsers: [User] { [currentUser] + colleagues }

    static func user(id: String) -> User? {
        allUsers.first { $0.workerId == id }
    }

    static let deals: [Deal] = [
        Deal(id: "3401", title: "Свадьба Королёвых — Loft Hall",
             stage: .photoReport,
             address: "Москва, ул. Правды, 24",
             eventDate: date(daysAgo: 1),
             assignedUserIds: ["1024", "1077", "1090"], responsibleId: "1050"),
        Deal(id: "3388", title: "Корпоратив «ТехноПром»",
             stage: .inProgress,
             address: "Москва, Красная Пресня, 12",
             eventDate: date(daysAgo: 0),
             assignedUserIds: ["1024", "1050"], responsibleId: "1050"),
        Deal(id: "3355", title: "Юбилей 50 лет — Ресторан «Волга»",
             stage: .done,
             address: "Химки, Ленинградская, 1",
             eventDate: date(daysAgo: 4),
             assignedUserIds: ["1024", "1077"], responsibleId: "1050")
    ]

    static func chats() -> [Chat] {
        deals.filter { $0.stage.createsChat }.map { deal in
            Chat(id: "chat-\(deal.id)",
                 dealId: deal.id,
                 title: deal.title,
                 participantIds: deal.assignedUserIds,
                 lastMessagePreview: preview(for: deal),
                 lastMessageDate: date(minutesAgo: Int.random(in: 5...600), seedString: deal.id),
                 unreadCount: deal.id == "3388" ? 3 : 0,
                 isPhotoReportOpen: deal.stage == .photoReport || deal.stage == .done)
        }
    }

    private static func preview(for deal: Deal) -> String {
        switch deal.stage {
        case .photoReport: return "Ольга: Готовы фото с площадки? 📸"
        case .inProgress:  return "Игорь: Монтаж завершён, начинаем"
        case .done:        return "Фотоотчёт отправлен на сервер ✓"
        default:           return "Чат создан"
        }
    }

    static func messages(chatId: String) -> [Message] {
        let dealId = chatId.replacingOccurrences(of: "chat-", with: "")
        return [
            Message(id: "\(chatId)-0", chatId: chatId, senderId: "",
                    text: "Чат по заказу создан автоматически из Битрикса",
                    attachments: [], sentAt: date(minutesAgo: 720, seedString: chatId), kind: .system),
            Message(id: "\(chatId)-1", chatId: chatId, senderId: "1050",
                    text: "Коллеги, всех добавила. Точка сбора — служебный вход в 9:00.",
                    attachments: [], sentAt: date(minutesAgo: 700, seedString: chatId), kind: .text),
            Message(id: "\(chatId)-2", chatId: chatId, senderId: "1090",
                    text: "Принял, буду вовремя.",
                    attachments: [], sentAt: date(minutesAgo: 650, seedString: chatId), kind: .text),
            Message(id: "\(chatId)-3", chatId: chatId, senderId: "1024",
                    text: "Площадка готова, приступаем к съёмке.",
                    attachments: [], sentAt: date(minutesAgo: 120, seedString: chatId), kind: .text),
            Message(id: "\(chatId)-4", chatId: chatId, senderId: "1077",
                    text: "Несколько кадров с площадки 👇",
                    attachments: (0..<3).map {
                        Message.Attachment(id: "\(chatId)-att-\($0)", localImageName: nil,
                                           remoteURL: nil, width: 1200, height: 1600)
                    },
                    sentAt: date(minutesAgo: 30, seedString: chatId + "img"), kind: .photo)
        ].filter { _ in !dealId.isEmpty }
    }

    // MARK: - Детерминированные даты (без Date() для предсказуемости превью)

    private static let anchor = Date(timeIntervalSince1970: 1_752_600_000) // фикс. «сейчас»

    static func date(daysAgo: Int) -> Date {
        anchor.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
    }
    static func date(minutesAgo: Int, seedString: String = "") -> Date {
        anchor.addingTimeInterval(TimeInterval(-minutesAgo * 60))
    }
}
