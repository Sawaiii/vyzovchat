import SwiftUI

/// Компания (бренд) мероприятия — events.folder на сервере: АРТ, ПРО, А+, РЕНТ4, АБА.
/// У каждой свой оттенок, чтобы принадлежность читалась с одного взгляда.
struct CompanyBadge: View {
    let name: String
    var compact = true

    private var tint: Color {
        switch name.uppercased() {
        case "АРТ":   return Color(hex: 0xC77DFF)
        case "ПРО":   return Color(hex: 0x3390EC)
        case "А+":    return Color(hex: 0x4CC38A)
        case "РЕНТ4": return Color(hex: 0xF2994A)
        case "АБА":   return Color(hex: 0xEB5757)
        default:      return Theme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "building.2.fill").font(.system(size: compact ? 8 : 10))
            Text(name).lineLimit(1)
        }
        .font(.system(size: compact ? 10 : 12, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
        .fixedSize()
    }
}
