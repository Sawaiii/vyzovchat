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
    /// Верхняя безопасная зона устройства — по ней и различаем «островок»,
    /// «бровь» и старый экран с кнопкой.
    let topInset: CGFloat

    init(width: CGFloat, topInset: CGFloat = DeviceInsets.notchTop) {
        self.width = width
        self.topInset = topInset
    }

    var isCompact: Bool { width <= 375 }        // SE, mini, 12/13 mini
    var isLarge: Bool { width >= 428 }          // Pro Max, Plus

    /// «Островок»: 14 Pro и новее — 59 pt и выше.
    var hasDynamicIsland: Bool { topInset >= 55 }
    /// «Бровь»: X…14 — 44…50 pt.
    var hasNotch: Bool { topInset >= 30 && topInset < 55 }

    var horizontalPadding: CGFloat {
        isCompact ? Spacing.m : (isLarge ? Spacing.l : Spacing.m + 4)
    }

    /// Отступ от панели навигации до содержимого вкладки.
    ///
    /// Панель iOS рисует своим «стеклом» — она заметно светлее экрана, и без
    /// просвета содержимое читается как её продолжение. Просвет и даём, но не
    /// одним числом на всех: у «островка» строка состояния на 12 pt выше
    /// «брови», панель уже уехала вниз, там хватает меньшего. У экрана с
    /// кнопкой (SE) строка состояния низкая — там отступ нужнее всего.
    var contentTopPadding: CGFloat {
        if hasDynamicIsland { return Spacing.s }
        return hasNotch ? 14 : Spacing.m
    }

    var cardCorner: CGFloat {
        isCompact ? Theme.cornerMedium : Theme.cornerLarge
    }
}

/// Безопасные зоны устройства. Берём у активного окна: метрики нужны и там,
/// где `GeometryReader` заводить незачем.
enum DeviceInsets {
    static var notchTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 47
    }
}

extension EnvironmentValues {
    var adaptiveMetrics: AdaptiveMetrics {
        AdaptiveMetrics(width: UIScreen.main.bounds.width)
    }
}
