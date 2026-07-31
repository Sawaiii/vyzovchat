import SwiftUI

/// Панель записи голосового: счётчик, «удалить» и «отправить».
///
/// Отдельная вью со своим наблюдением за рекордером — счётчик тикает несколько
/// раз в секунду, и держать его прямо в чате значило бы перерисовывать всю
/// ленту на каждый тик.
///
/// Записываем по кнопке, а не удержанием: на площадке в перчатках держать палец
/// ровно неудобно, а сорвавшийся жест стирает запись.
struct RecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button(action: onCancel) {
                Image(systemName: "trash").font(.title3).foregroundStyle(Theme.danger)
                    .frame(width: 40, height: 40)
            }

            HStack(spacing: Spacing.xs) {
                Circle().fill(Theme.danger).frame(width: 8, height: 8)
                    .opacity(recorder.duration.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.25)
                Text(Self.durationLabel(recorder.duration))
                    .font(Typography.callout.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Идёт запись")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Spacing.m).padding(.vertical, 10)
            .background(Theme.panel2, in: Capsule())

            Button(action: onSend) {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.accent, in: Circle())
            }
        }
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
