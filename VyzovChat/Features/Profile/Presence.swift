import SwiftUI

/// Отображение статуса присутствия «в сети / был в сети».
/// `isOnline` приходит из Socket.IO (событие `presence`) — подключается на
/// этапе реалтайма; `lastSeen` уже доступен из API (`workers.last_seen`).
enum Presence {
    static func text(isOnline: Bool, lastSeen: Date?) -> String {
        if isOnline { return "в сети" }
        guard let lastSeen else { return "не в сети" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .full
        return "был(а) в сети " + f.localizedString(for: lastSeen, relativeTo: Date())
    }

    static func color(isOnline: Bool) -> Color {
        isOnline ? Theme.success : Theme.textSecondary
    }
}

/// Точка-индикатор онлайна поверх аватара.
struct OnlineDot: View {
    let isOnline: Bool
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(isOnline ? Theme.success : Color.gray)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color(light: 0xFFFFFF, dark: 0x0E1220), lineWidth: 2))
            .opacity(isOnline ? 1 : 0.6)
    }
}
