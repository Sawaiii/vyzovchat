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
        if pending.isVoice { voiceRow } else { tile }
    }

    /// Уходящее голосовое показываем тем же, чем оно станет: строкой со
    /// столбиками. Квадратная плитка с иконкой файла читалась как видео, и
    /// сообщение на глазах превращалось из одного в другое.
    private var voiceRow: some View {
        HStack(spacing: Spacing.s) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.35)).frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: max(0.03, pending.progress))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
                Image(systemName: "mic.fill")
                    .font(.caption).foregroundStyle(Theme.textOnAccent)
            }
            // Столбики те же, что будут у отправленного: сообщения ещё нет, и
            // зерно берём у самой загрузки — форма всё равно своя у каждой.
            VoiceWaveform(seed: pending.id, progress: 0)
                .frame(width: 170, height: 26)
                .opacity(0.5)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Spacing.s)
        .glass(cornerRadius: Theme.cornerMedium, elevated: false)
    }

    private var tile: some View {
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
