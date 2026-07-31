import UIKit

extension UIApplication {
    /// Скрыть клавиатуру (снять фокус с активного поля).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Тактильная обратная связь для ключевых действий.
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
