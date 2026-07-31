import SwiftUI

@main
struct VyzovChatApp: App {
    @StateObject private var session = AppSession()

    init() {
        // Больший кэш для аватаров и медиа (меньше миганий/дозагрузок).
        URLCache.shared = URLCache(memoryCapacity: 40 * 1024 * 1024,
                                   diskCapacity: 300 * 1024 * 1024)
        NotificationsManager.shared.configure()
        AppAppearance.apply()
        // Не задерживать касания в прокрутках: иначе удержание сообщения (особенно
        // на фото) срабатывает заметно позже — ScrollView ждёт, не свайп ли это.
        UIScrollView.appearance().delaysContentTouches = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(Theme.accent)
                .preferredColorScheme(.dark) // тёмная тема как в веб-версии
        }
    }
}
