import SwiftUI

extension View {
    /// Полоса, которая ездит только влево-вправо.
    ///
    /// У горизонтального `ScrollView` вертикаль остаётся живой: стоит содержимому
    /// оказаться хоть на пару точек выше рамки — дробная высота шрифта, тень
    /// капсулы, вставки навигации, — и строка чипов начинает съезжать вверх-вниз
    /// внутри своей полосы. `fixedSize` прибивает высоту к содержимому, а
    /// `basedOnSize` убирает отскок по обеим осям, когда прокручивать нечего.
    ///
    /// Вешается на сам `ScrollView`, а не на его содержимое.
    func horizontalStrip() -> some View {
        self
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            .fixedSize(horizontal: false, vertical: true)
    }
}
