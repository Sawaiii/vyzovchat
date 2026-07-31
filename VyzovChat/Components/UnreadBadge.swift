import SwiftUI

/// Бейдж непрочитанного. Держит минимальную ширину и не липнет к краям
/// на двузначных числах; выше 99 показывает «99+».
struct UnreadBadge: View {
    let count: Int
    var background: Color = Theme.accent
    var compact: Bool = true

    private var text: String { count > 99 ? "99+" : "\(count)" }

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: compact ? 18 : 20)
            .background(background, in: Capsule())
            .fixedSize()
    }
}
