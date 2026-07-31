import SwiftUI

/// Обои чата: градиент из цвета мероприятия + дудл-паттерн поверх.
/// Повторяет расчёт веб-версии (chatTheme в public/app.js), чтобы один и тот же
/// чат выглядел одинаково на телефоне и в браузере:
/// насыщенность режется до 70%, светлота — до 8…60%, паттерн на 4% светлее фона.
struct ChatTheme {
    let top: Color
    let bottom: Color
    let pattern: Color

    init?(hex: String?) {
        guard let hex, let hsl = HSL(hex: hex) else { return nil }
        let sat = min(hsl.s, 70)
        let base = max(8, min(hsl.l, 60))
        top = Color(h: hsl.h, s: sat, l: base)
        bottom = Color(h: hsl.h, s: sat, l: max(5, base - 5))
        pattern = Color(h: hsl.h, s: sat, l: base + 4)
    }
}

/// Фон чата целиком: градиент + плитка паттерна поверх него.
struct ChatWallpaper: View {
    let colorHex: String?

    var body: some View {
        if let theme = ChatTheme(hex: colorHex) {
            LinearGradient(colors: [theme.top, theme.bottom], startPoint: .top, endPoint: .bottom)
                .overlay(patternLayer(tint: theme.pattern))
                .ignoresSafeArea()
        } else {
            AmbientBackground()
                .overlay(patternLayer(tint: Color.white.opacity(0.04)))
                .ignoresSafeArea()
        }
    }

    /// Плитка-дудл: SVG с сервера, растрированный в шаге 238pt — как mask-size в вебе.
    private func patternLayer(tint: Color) -> some View {
        Image("ChatPattern")
            .resizable(resizingMode: .tile)
            .renderingMode(.template)
            .foregroundStyle(tint)
            .allowsHitTesting(false)
    }
}

private struct HSL {
    let h: Double, s: Double, l: Double

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255

        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        let lightness = (maxV + minV) / 2

        var hue = 0.0
        var saturation = 0.0
        if delta != 0 {
            saturation = lightness > 0.5 ? delta / (2 - maxV - minV) : delta / (maxV + minV)
            switch maxV {
            case r: hue = (g - b) / delta + (g < b ? 6 : 0)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue *= 60
        }
        self.h = hue
        self.s = saturation * 100
        self.l = lightness * 100
    }
}

private extension Color {
    /// HSL в проценты, как в CSS: hsl(h s% l%).
    init(h: Double, s: Double, l: Double) {
        let sN = min(max(s, 0), 100) / 100
        let lN = min(max(l, 0), 100) / 100
        let c = (1 - abs(2 * lN - 1)) * sN
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default:    (r1, g1, b1) = (c, 0, x)
        }
        let m = lN - c / 2
        self.init(.sRGB, red: r1 + m, green: g1 + m, blue: b1 + m, opacity: 1)
    }
}
