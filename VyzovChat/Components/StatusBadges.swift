import SwiftUI

/// Ряд бейджей статуса мероприятия (Активно / Нет отчёта / Архив …).
struct StatusBadgesRow: View {
    let badges: [(text: String, kind: Deal.StatusKind)]
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(badges.indices, id: \.self) { i in
                let item = badges[i]
                Text(item.text)
                    .font(compact ? .system(size: 9, weight: .semibold) : .caption2.weight(.semibold))
                    .foregroundStyle(Self.color(item.kind))
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 2 : 4)
                    .background(Self.color(item.kind).opacity(0.16), in: Capsule())
                    .lineLimit(1)
            }
        }
    }

    static func color(_ kind: Deal.StatusKind) -> Color {
        switch kind {
        case .active: return Theme.accent
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .neutral: return Theme.textSecondary
        }
    }
}
