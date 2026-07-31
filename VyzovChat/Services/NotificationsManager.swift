import UserNotifications
import UIKit

/// Локальные уведомления о входящих сообщениях (в т.ч. «ответили вам»).
///
/// Работают, пока приложение живо/в фоне и держит сокет. Полноценный push
/// при полностью закрытом приложении требует APNs (платный Apple Developer
/// Program + серверная отправка) — это отдельная инфраструктура.
final class NotificationsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Убрать уже показанные уведомления (при входе в чат).
    func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func show(title: String, body: String, chatId: String? = nil, avatarURL: URL? = nil) {
        Task {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let chatId { content.userInfo = ["chatId": chatId] }
            if let attachment = await Self.makeAttachment(avatarURL) {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Картинка уведомления: аватар отправителя, иначе — лого приложения.
    private static func makeAttachment(_ avatarURL: URL?) async -> UNNotificationAttachment? {
        if let avatarURL, let (data, _) = try? await URLSession.shared.data(from: avatarURL),
           let file = writeTemp(data, ext: "jpg") {
            return try? UNNotificationAttachment(identifier: UUID().uuidString, url: file)
        }
        if let logo = UIImage(named: "Logo"), let data = logo.pngData(),
           let file = writeTemp(data, ext: "png") {
            return try? UNNotificationAttachment(identifier: UUID().uuidString, url: file)
        }
        return nil
    }

    private static func writeTemp(_ data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do { try data.write(to: url); return url } catch { return nil }
    }

    /// Тап по уведомлению — открыть соответствующий чат.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let chatId = response.notification.request.content.userInfo["chatId"] as? String {
            Task { @MainActor in Router.shared.openChat(id: chatId) }
        }
        completionHandler()
    }

    // Показывать баннер даже когда приложение на переднем плане.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
