import SwiftUI

/// Кнопка записи голосового: держим — пишем, ведём вверх к замку — фиксируем,
/// ведём влево — отменяем. После фиксации круг становится отправкой.
///
/// Отдельная вью не ради порядка, а ради плавности: палец двигает круг десятки
/// раз в секунду, и пока смещение лежало в состоянии чата, каждый кадр жеста
/// перерисовывал весь экран — ленту, темы, фон. Здесь оно живёт внутри, и на
/// движение пальца обновляется только сама кнопка.
struct MicRecordButton: View {
    /// Палец на кнопке. Наружу — чтобы поле ввода успело смениться на счётчик
    /// ещё до того, как запись реально начнётся (старт асинхронный).
    @Binding var pressing: Bool
    /// Запись зафиксирована: палец отпущен, а она продолжается.
    let isLocked: Bool
    /// Идёт запись или её вот-вот начнут — над кнопкой показываем замок/паузу.
    let isActive: Bool
    let isPaused: Bool

    let onStart: () -> Void
    let onLock: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void
    let onTogglePause: () -> Void

    /// Насколько кнопка уехала за пальцем.
    @State private var drag: CGSize = .zero
    /// Палец дошёл до замка — подсвечиваем цель, чтобы было видно, что дальше
    /// вести не надо.
    @State private var lockArmed = false

    /// Насколько вести палец вверх до фиксации. Ровно до замка: он висит на
    /// этом же расстоянии, и «дошёл до иконки» должно значить «сработало».
    private let lockDistance: CGFloat = 64
    /// Влево до отмены — заметно дальше, чтобы случайный увод не стирал запись.
    private let cancelDistance: CGFloat = 80

    var body: some View {
        // После фиксации круг перестаёт быть микрофоном и становится отправкой:
        // запись уже идёт сама, держать нечего.
        Image(systemName: isLocked ? "arrow.up" : "mic.fill")
            .font(.headline).foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Theme.accent, in: Circle())
            // Растёт под пальцем, как в мессенджерах: видно, что жест поймался.
            .scaleEffect(pressing ? 1.6 : 1)
            // Ореол рисуется уже поверх выросшего круга: попади он раньше
            // масштаба, тот бы на него умножился и залил пол-экрана.
            .background {
                if pressing {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.10)).scaleEffect(2.6)
                        Circle().fill(Theme.accent.opacity(0.16)).scaleEffect(1.95)
                    }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pressing)
            .contentShape(Rectangle())
            // Круг едет за пальцем к замку. Смещение не меняет место в лейауте,
            // поэтому сам замок остаётся стоять — к нему и ведут.
            .offset(drag)
            .gesture(dragGesture)
            .overlay(alignment: .bottom) {
                if isActive { floatingPanel }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Зафиксированную запись жест не трогает: круг стал обычной
                // кнопкой «отправить».
                guard !isLocked else { return }
                if !pressing {
                    pressing = true
                    lockArmed = false
                    onStart()
                }
                let dx = max(min(0, value.translation.width), -cancelDistance)
                let dy = max(min(0, value.translation.height), -70)
                drag = CGSize(width: dx, height: dy)
                // Вверх до замка — фиксируем, влево — отменяем.
                if dy < -lockDistance {
                    reset()
                    Haptics.success()
                    onLock()
                } else if value.translation.width < -cancelDistance {
                    reset()
                    onCancel()
                } else {
                    lockArmed = dy < -25
                }
            }
            .onEnded { value in
                if isLocked {
                    // Касание по кругу отправляет. Смазанное касание — это уже
                    // прокрутка чего-то другого, не отправка.
                    if abs(value.translation.width) < 12, abs(value.translation.height) < 12 {
                        onFinish()
                    }
                    return
                }
                guard pressing else { return }
                reset()
                onFinish()
            }
    }

    /// Кнопка вернулась на место, палец больше не считается прижатым.
    private func reset() {
        pressing = false
        lockArmed = false
        drag = .zero
    }

    /// Всплывающая панель над кнопкой: пока держим — замок, к которому ведут
    /// палец, после фиксации — пауза.
    ///
    /// Замок здесь видимая цель, а не догадка: без него фиксация была бы
    /// «увести палец вверх», и понять, увёл ли достаточно, неоткуда.
    @ViewBuilder
    private var floatingPanel: some View {
        if isLocked {
            Button(action: onTogglePause) {
                Image(systemName: isPaused ? "mic.fill" : "pause.fill")
                    .font(.headline).foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.panel2, in: Circle())
            }
            .offset(y: -52)
        } else {
            VStack(spacing: 6) {
                Image(systemName: lockArmed ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(lockArmed ? Theme.accent : Theme.textSecondary)
            .frame(width: 40, height: 72)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: lockArmed)
            .offset(y: -lockDistance)
        }
    }
}
