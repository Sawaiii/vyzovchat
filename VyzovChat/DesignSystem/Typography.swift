import SwiftUI

/// Типографика на основе системного шрифта San Francisco с поддержкой
/// Dynamic Type — текст масштабируется под настройки доступности и любой экран.
enum Typography {
    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title      = Font.system(.title2, design: .rounded, weight: .semibold)
    static let headline   = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body       = Font.system(.body, design: .default)
    static let callout    = Font.system(.callout, design: .default)
    static let subheadline = Font.system(.subheadline, design: .default)
    static let caption    = Font.system(.caption, design: .default)
    static let button     = Font.system(.headline, design: .rounded, weight: .semibold)
}
