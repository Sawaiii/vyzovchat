import SwiftUI

/// Строка записи голосового: красная точка, счётчик и подсказка (или «Отмена»,
/// когда запись зафиксирована).
///
/// Отдельная вью со своим наблюдением за рекордером — счётчик тикает двадцать
/// раз в секунду, и держать его прямо в чате значило бы перерисовывать всю
/// ленту на каждый тик.
///
/// Самой кнопки записи здесь нет: она общая для всех состояний поля ввода и
/// живёт выше по дереву. Вынуть её из дерева посреди удержания нельзя —
/// вместе с ней оборвался бы жест, а с ним и запись.
struct RecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    /// Запись зафиксирована: палец отпущен, и отмена стала обычной кнопкой.
    let isLocked: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(Theme.danger).frame(width: 9, height: 9)
                .opacity(dotOpacity)
            Text(Self.durationLabel(recorder.duration))
                .font(Typography.callout.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Spacing.s)
        }
        .overlay {
            if isLocked {
                Button("Отмена", action: onCancel)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.accent)
            } else {
                // Подсказка ровно про то, что сейчас делает палец: вверх ведёт
                // к замку, который и так виден, а вот про отмену влево догадаться
                // неоткуда.
                Text("‹ Влево — отмена")
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        // Место справа под кнопку записи: она нарисована поверх строки.
        .padding(.trailing, 48)
        .frame(height: 40)
    }

    /// На паузе точка не мигает, а просто гаснет — иначе не отличить.
    private var dotOpacity: Double {
        guard !recorder.isPaused else { return 0.3 }
        return recorder.duration.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.25
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hundredths = Int((seconds - Double(total)) * 100)
        return String(format: "%d:%02d,%02d", total / 60, total % 60, hundredths)
    }
}
