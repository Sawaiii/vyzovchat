import SwiftUI

extension View {
    /// Панель навигации в цвете приложения.
    ///
    /// По умолчанию iOS рисует её системным «стеклом»: на нашем тёмном фоне это
    /// светло-серая плашка, к которой вплотную прилипает содержимое — видно две
    /// разные поверхности со швом посередине. Красим панель в верхний цвет
    /// фонового градиента (`Theme.bg` — ровно он стоит вверху `appBackground`),
    /// и шов пропадает: панель читается как часть экрана.
    ///
    /// Схему приборов задаём тёмной принудительно — иначе в светлой системной
    /// теме заголовок был бы тёмным по тёмному.
    func appNavigationBar() -> some View {
        self
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
