import SwiftUI

/// Логотип-знак Vyzov Chat (из ассета Logo).
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

#Preview {
    ZStack {
        AmbientBackground()
        BrandMark(size: 100)
    }
}
