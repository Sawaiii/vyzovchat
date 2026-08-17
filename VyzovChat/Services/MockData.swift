import Foundation

/// Вымышленные данные для работы приложения без реального сервера.
///
/// Включаются запуском с аргументом `-demoData` (см. `AppConfig.useMockData`).
/// На них снимают экраны для презентации: рабочие переписки и заказы показывать
/// нельзя, а пустые экраны ничего не рассказывают. Люди, компании и мероприятия
/// здесь придуманы; совпадения с настоящими случайны.
enum MockData {

    // MARK: - Люди

    static let currentUser = User(
        id: "1024",
        workerId: "1024",
        lastName: "Никитин",
        firstName: "Алексей",
        middleName: "Сергеевич",
        phone: "+7 900 123-45-67",
        position: "Руководитель работ",
        department: "Отдел мероприятий",
        avatarURL: nil,
        fio: "Никитин Алексей Сергеевич",
        login: "a.nikitin",
        email: "a.nikitin@example.com",
        isAdmin: true,
        globalRole: "leader"
    )

    static let colleagues: [User] = [
        User(id: "1050", workerId: "1050", lastName: "Смирнова", firstName: "Ольга",
             middleName: "Ивановна", phone: "+7 900 555-11-22",
             position: "Координатор", department: "Отдел мероприятий", avatarURL: nil,
             fio: "Смирнова Ольга Ивановна", login: "o.smirnova",
             email: "o.smirnova@example.com", eventRole: "senior"),
        User(id: "1077", workerId: "1077", lastName: "Петров", firstName: "Дмитрий",
             middleName: nil, phone: "+7 900 777-33-44",
             position: "Фотограф", department: "Медиа", avatarURL: nil,
             fio: "Петров Дмитрий", login: "d.petrov",
             email: "d.petrov@example.com", eventRole: "member"),
        User(id: "1090", workerId: "1090", lastName: "Ковалёв", firstName: "Игорь",
             middleName: "Павлович", phone: "+7 900 888-99-00",
             position: "Монтажник", department: "Логистика", avatarURL: nil,
             fio: "Ковалёв Игорь Павлович", login: "i.kovalev",
             email: "i.kovalev@example.com", eventRole: "member"),
        User(id: "1103", workerId: "1103", lastName: "Ёлкина", firstName: "Марина",
             middleName: "Андреевна", phone: "+7 900 222-64-18",
             position: "Декоратор", department: "Оформление", avatarURL: nil,
             fio: "Ёлкина Марина Андреевна", login: "m.elkina",
             email: "m.elkina@example.com", eventRole: "member"),
        User(id: "1118", workerId: "1118", lastName: "Гусев", firstName: "Артём",
             middleName: nil, phone: "+7 900 314-08-52",
             position: "Звукорежиссёр", department: "Техническая служба", avatarURL: nil,
             fio: "Гусев Артём", login: "a.gusev",
             email: "a.gusev@example.com", eventRole: "storekeeper")
    ]

    static var allUsers: [User] { [currentUser] + colleagues }

    static func user(id: String) -> User? {
        allUsers.first { $0.workerId == id }
    }

    // MARK: - Мероприятия

    static let deals: [Deal] = [
        Deal(id: "4102",
             title: "Конференция «Логистика 2026» — Крокус Экспо",
             stage: .inProgress,
             address: "Красногорск, Международная, 16",
             eventDate: date(daysAgo: 0),
             assignedUserIds: ["1024", "1050", "1090", "1118"],
             responsibleId: "1050",
             company: "Атлант Групп",
             myRole: "senior"),
        Deal(id: "4098",
             title: "Свадьба Королёвых — Loft Hall",
             stage: .photoReport,
             address: "Москва, ул. Правды, 24",
             eventDate: date(daysAgo: 1),
             assignedUserIds: ["1024", "1077", "1103"],
             responsibleId: "1050",
             company: "Гранд Холл",
             myRole: "admin"),
        Deal(id: "4091",
             title: "Корпоратив «ТехноПром» — Резиденция",
             stage: .photoReport,
             address: "Москва, Красная Пресня, 12",
             eventDate: date(daysAgo: 2),
             assignedUserIds: ["1024", "1050", "1077"],
             responsibleId: "1050",
             company: "Атлант Групп",
             myRole: "member"),
        Deal(id: "4085",
             title: "Юбилей 50 лет — ресторан «Волга»",
             stage: .done,
             address: "Химки, Ленинградская, 1",
             eventDate: date(daysAgo: 5),
             assignedUserIds: ["1024", "1077", "1118"],
             responsibleId: "1050",
             rawStatus: "closed",
             reportStatus: "sent",
             company: "Гранд Холл",
             myRole: "member"),
        Deal(id: "4077",
             title: "Выставка «АгроЭкспо» — павильон 3",
             stage: .done,
             address: "Москва, Профсоюзная, 84",
             eventDate: date(daysAgo: 12),
             assignedUserIds: ["1024", "1090"],
             responsibleId: "1050",
             archived: true,
             rawStatus: "closed",
             reportStatus: "sent",
             company: "Атлант Групп",
             myRole: "member"),
        Deal(id: "4110",
             title: "Форум «Медиа Старт» — Digital October",
             stage: .prepare,
             address: "Москва, Берсеневская наб., 6",
             eventDate: date(daysAgo: -3),
             assignedUserIds: ["1024", "1050", "1103"],
             responsibleId: "1050",
             company: "Медиа Старт",
             myRole: "senior")
    ]

    // MARK: - Чаты

    static func chats() -> [Chat] {
        deals.filter { $0.stage.createsChat }.map { deal in
            Chat(id: "chat-\(deal.id)",
                 dealId: deal.id,
                 title: deal.title,
                 participantIds: deal.assignedUserIds,
                 lastMessagePreview: preview(for: deal),
                 lastMessageDate: lastDate(for: deal),
                 lastMessageIsMine: deal.id == "4091",
                 unreadCount: unread(for: deal),
                 isPhotoReportOpen: deal.stage == .photoReport || deal.stage == .done,
                 isArchived: deal.archived,
                 rawStatus: deal.rawStatus,
                 reportStatus: deal.reportStatus,
                 company: deal.company,
                 isChatAdmin: deal.myRole == "admin" || deal.myRole == "senior",
                 myRole: deal.myRole,
                 address: deal.address)
        }
        .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
    }

    private static func preview(for deal: Deal) -> String {
        switch deal.id {
        case "4102": return "Ольга: Сцена собрана, ждём звук"
        case "4098": return "Дмитрий: Загрузил 148 кадров с площадки"
        case "4091": return "Отчёт отправлен заказчику ✓"
        case "4085": return "Игорь: Оборудование вернули на склад"
        default:     return "Мероприятие завершено"
        }
    }

    private static func unread(for deal: Deal) -> Int {
        switch deal.id {
        case "4102": return 4
        case "4098": return 2
        default:     return 0
        }
    }

    private static func lastDate(for deal: Deal) -> Date {
        switch deal.id {
        case "4102": return date(minutesAgo: 6)
        case "4098": return date(minutesAgo: 52)
        case "4091": return date(minutesAgo: 340)
        case "4085": return date(daysAgo: 4)
        default:     return date(daysAgo: 11)
        }
    }

    // MARK: - Переписка

    static func messages(chatId: String) -> [Message] {
        let dealId = chatId.replacingOccurrences(of: "chat-", with: "")
        guard !dealId.isEmpty else { return [] }
        switch dealId {
        case "4102": return conferenceThread(chatId: chatId)
        default:     return genericThread(chatId: chatId)
        }
    }

    /// Мероприятие, которое идёт прямо сейчас, — самая живая переписка.
    private static func conferenceThread(chatId: String) -> [Message] {
        [
            msg(chatId, 0, "", "Чат мероприятия создан автоматически", minutesAgo: 900, kind: .system),
            msg(chatId, 1, "1050", "Коллеги, сбор в 7:30 у служебного входа. Пропуска на всех заказаны.", minutesAgo: 880),
            msg(chatId, 2, "1090", "Принял. Фуру с конструкциями ждём к 8:00.", minutesAgo: 861),
            msg(chatId, 3, "1024", "Пропуск на машину получил, отдам водителю на въезде.", minutesAgo: 848),
            msg(chatId, 4, "1118", "Пульт и радиосистемы забрал со склада, комплект полный.", minutesAgo: 512),
            msg(chatId, 5, "1090", "Сцена собрана, свет повесили. Осталась задняя ферма.", minutesAgo: 148),
            msg(chatId, 6, "1050", "@Никитин Алексей заказчик просит добавить два микрофона на президиум", minutesAgo: 96),
            msg(chatId, 7, "1024", "Сделаем, у Артёма есть запасные.", minutesAgo: 88),
            msg(chatId, 8, "1118", "Поставил, проверил — работают.", minutesAgo: 74),
            msg(chatId, 9, "1050", "Фото зала до начала 👇", minutesAgo: 61, kind: .photo, photos: 2),
            msg(chatId, 10, "1024", "Отлично, отправляю заказчику.", minutesAgo: 44),
            msg(chatId, 11, "1103", "Оформление президиума готово, ленту повесили.", minutesAgo: 33),
            msg(chatId, 12, "1024", "Игорь, ферму закрепили? Заказчик спрашивает про подвес экрана.", minutesAgo: 24),
            msg(chatId, 13, "1090", "Да, всё по схеме. Экран вешаем после прогона света.", minutesAgo: 18),
            msg(chatId, 14, "1050", "Сцена собрана, ждём звук", minutesAgo: 6)
        ]
    }

    private static func genericThread(chatId: String) -> [Message] {
        [
            msg(chatId, 0, "", "Чат мероприятия создан автоматически", minutesAgo: 1500, kind: .system),
            msg(chatId, 1, "1050", "Всех добавила в чат. Точка сбора — служебный вход, 9:00.", minutesAgo: 1440),
            msg(chatId, 2, "1103", "Оформление привезу к восьми, разгрузка со двора.", minutesAgo: 1380),
            msg(chatId, 3, "1024", "Площадка готова, приступаем к съёмке.", minutesAgo: 420),
            msg(chatId, 4, "1077", "Несколько кадров с площадки 👇", minutesAgo: 96, kind: .photo, photos: 3),
            msg(chatId, 5, "1077", "Загрузил 148 кадров с площадки", minutesAgo: 52)
        ]
    }

    private static func msg(_ chatId: String, _ index: Int, _ sender: String, _ text: String,
                            minutesAgo: Int, kind: Message.Kind = .text, photos: Int = 0) -> Message {
        Message(id: "\(chatId)-\(index)",
                chatId: chatId,
                senderId: sender,
                text: text,
                attachments: (0..<photos).map {
                    Message.Attachment(id: "\(chatId)-att-\(index)-\($0)", localImageName: nil,
                                       remoteURL: demoPhoto($0), width: 1200, height: 1600)
                },
                sentAt: date(minutesAgo: minutesAgo),
                kind: kind)
    }

    /// Условный снимок с площадки из ресурсов приложения. Это не фотография
    /// мероприятия, а нарисованный фон: тёмный зал, свет приборов, расфокус.
    private static func demoPhoto(_ index: Int) -> URL? {
        let names = ["demo-photo-1", "demo-photo-2", "demo-photo-3", "demo-photo-4"]
        return Bundle.main.url(forResource: names[index % names.count], withExtension: "jpg")
    }

    // MARK: - Даты

    /// «Сейчас» на момент запуска: на экранах должны быть свежие даты,
    /// иначе список выглядит заброшенным.
    private static let anchor = Date()

    static func date(daysAgo: Int) -> Date {
        anchor.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
    }
    static func date(minutesAgo: Int, seedString: String = "") -> Date {
        anchor.addingTimeInterval(TimeInterval(-minutesAgo * 60))
    }
}
