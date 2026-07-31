import SwiftUI

/// Простая «перетекающая» раскладка: элементы идут в ряд и переносятся на новую
/// строку, когда не влезают по ширине. Для облака тегов/чипов.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0; y += rowH + lineSpacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        let width = maxW.isFinite ? maxW : max(0, x - spacing)
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > maxW, x > bounds.minX {
                x = bounds.minX; y += rowH + lineSpacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
