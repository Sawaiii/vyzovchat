import SwiftUI

/// Тёмная тема в стиле Telegram — согласована с веб-версией (тот же продукт).
enum Theme {
    // Акценты
    static let accent = Color(hex: 0x3390EC)          // яркий синий (кнопки, активное)
    static let accentSecondary = Color(hex: 0x2B5278) // приглушённый синий
    static let success = Color(hex: 0x4CAF50)
    static let warning = Color(hex: 0xFF9F0A)
    static let danger  = Color(hex: 0xFF6B6B)

    // Поверхности
    static let bg = Color(hex: 0x0E1621)
    static let panel = Color(hex: 0x17212B)
    static let panel2 = Color(hex: 0x1E2C3A)
    static let line = Color(hex: 0x101820)

    // Текст
    static let textPrimary = Color(hex: 0xE9EDF1)
    static let textSecondary = Color(hex: 0x7F91A4)
    static let textOnAccent = Color.white

    // Чат
    static let bubbleMine = Color(hex: 0x2B5278)
    static let bubbleOther = Color(hex: 0x182533)
    static let groupTitle = Color(hex: 0xFFCF6B)      // названия мероприятий — жёлтым
    /// Кликабельное внутри пузыря: упоминания и «переслано от».
    /// Заметно светлее фона обоих пузырей — accentSecondary для этого не годится,
    /// он в точности совпадает с цветом своего пузыря и там просто исчезает.
    static let bubbleLink = Color(hex: 0x6AB7FF)

    /// Фон приложения — тёмный градиент как в веб-чате.
    static var appBackground: some View {
        LinearGradient(colors: [Color(hex: 0x0E1621), Color(hex: 0x0B1119)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// «Градиент» акцента (для совместимости со старым кодом) — фактически сплошной синий.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    }

    static let cornerLarge: CGFloat = 16
    static let cornerMedium: CGFloat = 12
    static let cornerSmall: CGFloat = 10
}

// MARK: - Удобные инициализаторы Color

extension Color {
    /// Разбор hex-строки вида "#1E2C3A" / "1e2c3a" (цвет-обои чата с сервера).
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt(s, radix: 16) else { return nil }
        self.init(hex: value)
    }

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Разные оттенки для светлой и тёмной темы (тема тёмная, но оставлено для утилит).
    init(light: UInt, dark: UInt) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
