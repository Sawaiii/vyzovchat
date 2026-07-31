import SwiftUI

/// Плоская панель в стиле Telegram (раньше был «жидкое стекло»).
/// Имена API сохранены, чтобы не трогать все экраны.
///
/// Здесь намеренно НЕТ материала, градиентной обводки и тени. Раньше каждая
/// строка списка размывала фон через `.ultraThinMaterial`, обводилась градиентом
/// и отбрасывала тень — три дорогих прохода на строку, по два десятка строк на
/// экране. При прокрутке это давало заметные рывки.
///
/// Причём размытие ничего не давало: фон приложения — сплошной тёмный градиент,
/// и размытая сплошная заливка выглядит как та же сплошная заливка. Поэтому
/// рисуем цвет напрямую и обводим тонкой линией.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerLarge
    var strokeOpacity: Double = 0.06
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .background(shape.fill(elevated ? Theme.panel : Theme.panel.opacity(0.55)))
            .overlay(shape.strokeBorder(Color.white.opacity(elevated ? 0.08 : 0.05), lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension View {
    /// Плоская панель-поверхность.
    func glass(cornerRadius: CGFloat = Theme.cornerLarge,
               elevated: Bool = true) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, elevated: elevated))
    }
}

/// Карточка-панель с внутренними отступами.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.cornerLarge
    var padding: CGFloat = Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: cornerRadius)
    }
}

/// Фон экрана — сплошной тёмный градиент (без анимаций).
struct AmbientBackground: View {
    var body: some View {
        Theme.appBackground.ignoresSafeArea()
    }
}
