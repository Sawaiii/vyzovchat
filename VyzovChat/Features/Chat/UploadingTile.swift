import SwiftUI

/// Вложение, которое сейчас уходит на сервер: превью с кольцом прогресса.
///
/// Раньше после прикрепления фото не происходило ничего видимого до тех пор,
/// пока сообщение не появлялось в ленте — на слабой связи это десятки секунд
/// тишины, и человек не понимал, отправляется ли что-нибудь вообще.
struct UploadingTile: View {
    let pending: ChatViewModel.PendingUpload

    private static let side: CGFloat = 140

    var body: some View {
        ZStack {
            if let preview = pending.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.side, height: Self.side)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))
            } else {
                Theme.panel2
                    .frame(width: Self.side, height: Self.side)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.title2).foregroundStyle(Theme.textSecondary)
                            Text(pending.name)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                        }
                    )
            }

            ring
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 3)
            Circle()
                // Пока байты не пошли, крутить нечего — показываем тонкую дугу,
                // чтобы кольцо не выглядело застывшим на нуле.
                .trim(from: 0, to: max(0.02, pending.progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: pending.progress)
            Text("\(Int(pending.progress * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 46, height: 46)
        .padding(8)
        .background(.black.opacity(0.35), in: Circle())
    }
}
