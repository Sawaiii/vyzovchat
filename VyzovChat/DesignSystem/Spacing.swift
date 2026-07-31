import SwiftUI

/// Единая шкала отступов. Использование одинаковых значений по всему
/// приложению даёт визуальную согласованность на любом размере экрана.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 44
}

/// Хелпер адаптации под размер экрана: компактные iPhone SE / mini
/// получают чуть меньшие отступы, крупные Pro Max — чуть большие.
struct AdaptiveMetrics {
    let width: CGFloat

    var isCompact: Bool { width <= 375 }        // SE, mini, 12/13 mini
    var isLarge: Bool { width >= 428 }          // Pro Max, Plus

    var horizontalPadding: CGFloat {
        isCompact ? Spacing.m : (isLarge ? Spacing.l : Spacing.m + 4)
    }

    var cardCorner: CGFloat {
        isCompact ? Theme.cornerMedium : Theme.cornerLarge
    }
}

extension EnvironmentValues {
    var adaptiveMetrics: AdaptiveMetrics {
        AdaptiveMetrics(width: UIScreen.main.bounds.width)
    }
}
