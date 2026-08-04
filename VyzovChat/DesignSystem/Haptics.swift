import UIKit

extension UIApplication {
    /// Скрыть клавиатуру (снять фокус с активного поля).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Тактильная обратная связь для ключевых действий.
///
/// Генератор создаётся на каждый вызов и придерживается до конца отклика.
/// Оба края тут важны. Один общий генератор на всё приложение движок глушил —
/// он к нему переставал отзываться. А созданный и тут же брошенный успевал
/// освободиться раньше, чем система доводила удар до движка: доходил только
/// самый лёгкий отклик (выбор), а удар и уведомление терялись.
enum Haptics {
    /// Генераторы, которые сейчас доигрывают.
    private static var live: [UIFeedbackGenerator] = []

    private static func fire<G: UIFeedbackGenerator>(_ generator: G, _ play: (G) -> Void) {
        live.append(generator)
        generator.prepare()
        play(generator)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            live.removeAll { $0 === generator }
        }
    }

    static func tap() {
        // Средний, а не лёгкий: лёгкий на подтверждение действия почти не
        // ощущается — его принимали за «отклика нет».
        fire(UIImpactFeedbackGenerator(style: .medium)) { $0.impactOccurred() }
    }
    static func success() {
        fire(UINotificationFeedbackGenerator()) { $0.notificationOccurred(.success) }
    }
    static func warning() {
        fire(UINotificationFeedbackGenerator()) { $0.notificationOccurred(.warning) }
    }
    static func selection() {
        fire(UISelectionFeedbackGenerator()) { $0.selectionChanged() }
    }
}
