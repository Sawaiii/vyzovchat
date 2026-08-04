import UIKit

extension UIApplication {
    /// Скрыть клавиатуру (снять фокус с активного поля).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Тактильная обратная связь для ключевых действий.
///
/// Генератор создаётся на каждый вызов — намеренно. Общий, живущий всё время
/// работы приложения, отклик глушил: движок к нему просто переставал
/// отзываться. Экономия на создании того не стоила.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
