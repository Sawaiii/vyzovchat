import SwiftUI

/// Простой роутер для перехода из уведомления в нужный чат.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    /// id чата, который надо открыть (например, "chat-5" или "dm-3").
    @Published var pendingChatId: String?
    /// Запрос переключиться на вкладку «Чаты».
    @Published var wantsChatsTab = false

    private init() {}

    func openChat(id: String) {
        wantsChatsTab = true
        pendingChatId = id
    }
}
