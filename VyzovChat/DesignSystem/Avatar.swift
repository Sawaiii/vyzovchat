import SwiftUI

/// Аватар пользователя: инициалы на цветном фоне (детерминированный цвет по id).
struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    var id: String = ""

    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    private var gradient: LinearGradient {
        let palette: [(UInt, UInt)] = [
            (0x3E6BFF, 0x22D3EE), (0x8B5CF6, 0xEC4899),
            (0xF59E0B, 0xEF4444), (0x10B981, 0x22D3EE),
            (0x6366F1, 0x8B5CF6)
        ]
        let seed = abs((id.isEmpty ? name : id).hashValue)
        let pair = palette[seed % palette.count]
        return LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
