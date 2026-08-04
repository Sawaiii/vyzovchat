import SwiftUI

/// Строка записи голосового: красная точка, счётчик и подсказка (или «Отмена»,
/// когда запись зафиксирована).
///
/// Сама за рекордером НЕ следит — это важно. Счётчик тикает двадцать раз в
/// секунду, и пока за ним следила вся строка, каждый тик пересчитывал её
/// раскладку. Приходились эти тики ровно на движение пальца по кнопке записи,
/// и жест шёл рывками: между двумя кадрами жеста успевал влезть пересчёт
/// строки. Теперь тикает только сам счётчик, и размер у него намертво
/// зафиксирован — наружу пересчёт не выходит.
///
/// Самой кнопки записи здесь нет: она общая для всех состояний поля ввода и
/// живёт выше по дереву. Вынуть её из дерева посреди удержания нельзя —
/// вместе с ней оборвался бы жест, а с ним и запись.
struct RecordingBar: View {
    /// Без @ObservedObject намеренно: см. выше.
    let recorder: VoiceRecorder
    /// Запись зафиксирована: палец отпущен, и отмена стала обычной кнопкой.
    let isLocked: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            RecordingCounter(recorder: recorder)
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
}

/// Точка и время записи — единственное, что обновляется двадцать раз в секунду.
///
/// Ширина задана жёстко. Без неё каждая сотая доля меняла ширину текста, а
/// значит и раскладку строки ввода, и пересчёт уходил вверх по дереву — до
/// ленты сообщений. С фиксированным размером система знает, что снаружи ничего
/// не изменилось, и дальше счётчика не идёт.
private struct RecordingCounter: View {
    @ObservedObject var recorder: VoiceRecorder

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(Theme.danger).frame(width: 9, height: 9)
                .opacity(dotOpacity)
            Text(Self.durationLabel(recorder.duration))
                .font(Typography.callout.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 96, height: 40, alignment: .leading)
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
