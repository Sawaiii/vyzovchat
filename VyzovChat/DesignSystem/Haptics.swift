import UIKit

extension UIApplication {
    /// Скрыть клавиатуру (снять фокус с активного поля).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Тактильная обратная связь для ключевых действий.
///
/// Генераторы общие и живут всё время работы приложения. У тактильного движка
/// есть раскрутка: новый генератор на каждый вызов означал, что движок заводится
/// заново прямо в момент действия — и первый отклик стоил заметной паузы на
/// главном потоке. Общий генератор остаётся тёплым между вызовами.
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notice = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    /// Разогреть движок заранее — перед действием, отклик на которое должен
    /// прийти мгновенно (например, в начале жеста записи).
    static func prepare() {
        impact.prepare()
        notice.prepare()
    }

    static func tap() {
        impact.impactOccurred()
    }
    static func success() {
        notice.notificationOccurred(.success)
    }
    static func warning() {
        notice.notificationOccurred(.warning)
    }
    static func selection() {
        select.selectionChanged()
    }
}
