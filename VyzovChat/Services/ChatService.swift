import Foundation

/// Работа с чатами и сообщениями. В реальной версии здесь будет
/// WebSocket/пуш-подписка; в моке — простые async-ответы.
protocol ChatServicing {
    func fetchChats(for user: User) async -> [Chat]
    func fetchDMChats(for user: User) async -> [Chat]
    func fetchMessages(chatId: String) async -> [Message]?
    /// История конкретной темы мероприятия (topicId = nil → канал «Общий»).
    func fetchMessages(chatId: String, topicId: Int?) async -> [Message]?
    func fetchDMMessages(otherId: String) async -> [Message]?

    // Темы (подканалы) мероприятия
    func fetchTopics(dealId: String) async -> [TopicDTO]
    func createTopic(dealId: String, name: String) async throws -> TopicDTO
    func deleteTopic(id: Int) async throws
    /// Непрочитанное по темам: ключ "m" — «Общий», остальные — id темы.
    func topicUnread(dealId: String) async -> [String: Int]
    func markTopicRead(dealId: String, topicId: Int?, lastRead: Int) async
    /// Поиск по сообщениям мероприятия — сразу по всем видимым темам, а не
    /// только по загруженной ленте.
    func searchMessages(dealId: String, query: String) async -> [Message]
    /// Окно ленты вокруг найденного сообщения: старое сообщение в последнюю
    /// сотню не попадает, и переходить из поиска было бы некуда.
    func fetchMessages(chatId: String, topicId: Int?, around messageId: Int) async -> [Message]?
    /// Последнее сообщение чата — для превью в списке (грузится фоном).
    func lastMessage(for chat: Chat) async -> Message?

    // Закреплённые сообщения. Их может быть несколько; у мероприятия свои на
    // каждой вкладке, у личной переписки — свои. Закрепляет админ чата, а в ЛС —
    // любой из двоих. Все три ручки отдают ВЕСЬ список закрепов чата.
    func pinnedMessages(dealId: String, topicId: Int?) async -> [Message]
    func pinnedDMMessages(peerId: String) async -> [Message]
    func pin(messageId: String) async throws -> [Message]
    func unpin(messageId: String) async throws -> [Message]

    func send(text: String, chatId: String, senderId: String) async -> Message
    func sendPhotos(_ count: Int, chatId: String, senderId: String) async -> Message
}

final class MockChatService: ChatServicing {
    private var extraMessages: [String: [Message]] = [:]
    private var counter = 0

    func fetchChats(for user: User) async -> [Chat] {
        try? await Task.sleep(for: .milliseconds(500))
        return MockData.chats()
            .filter { $0.participantIds.contains(user.workerId) }
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
    }

    func fetchDMChats(for user: User) async -> [Chat] { [] }

    func fetchMessages(chatId: String) async -> [Message]? {
        try? await Task.sleep(for: .milliseconds(400))
        let base = MockData.messages(chatId: chatId)
        return (base + (extraMessages[chatId] ?? [])).sorted { $0.sentAt < $1.sentAt }
    }

    func fetchDMMessages(otherId: String) async -> [Message]? { [] }

    func fetchMessages(chatId: String, topicId: Int?) async -> [Message]? {
        await fetchMessages(chatId: chatId)
    }

    func searchMessages(dealId: String, query: String) async -> [Message] { [] }

    func fetchMessages(chatId: String, topicId: Int?, around messageId: Int) async -> [Message]? {
        await fetchMessages(chatId: chatId)
    }

    func lastMessage(for chat: Chat) async -> Message? {
        MockData.messages(chatId: chat.id).last
    }

    func pinnedMessages(dealId: String, topicId: Int?) async -> [Message] { [] }
    func pinnedDMMessages(peerId: String) async -> [Message] { [] }
    func pin(messageId: String) async throws -> [Message] {
        throw APIError.transport("Закреп недоступен в демо-режиме")
    }
    func unpin(messageId: String) async throws -> [Message] { [] }

    func fetchTopics(dealId: String) async -> [TopicDTO] { [] }
    func createTopic(dealId: String, name: String) async throws -> TopicDTO {
        TopicDTO(id: 0, name: name, sort: 0, visibility: "all", roles: nil, members: nil)
    }
    func deleteTopic(id: Int) async throws {}
    func topicUnread(dealId: String) async -> [String: Int] { [:] }
    func markTopicRead(dealId: String, topicId: Int?, lastRead: Int) async {}

    func send(text: String, chatId: String, senderId: String) async -> Message {
        counter += 1
        let msg = Message(
            id: "local-\(chatId)-\(counter)", chatId: chatId, senderId: senderId,
            text: text, attachments: [],
            sentAt: MockData.date(minutesAgo: 0), kind: .text
        )
        extraMessages[chatId, default: []].append(msg)
        return msg
    }

    func sendPhotos(_ count: Int, chatId: String, senderId: String) async -> Message {
        counter += 1
        let atts = (0..<count).map {
            Message.Attachment(id: "local-att-\(counter)-\($0)", localImageName: nil,
                               remoteURL: nil, width: 1200, height: 1600)
        }
        let msg = Message(
            id: "local-\(chatId)-\(counter)", chatId: chatId, senderId: senderId,
            text: nil, attachments: atts,
            sentAt: MockData.date(minutesAgo: 0), kind: .photo
        )
        extraMessages[chatId, default: []].append(msg)
        return msg
    }
}
