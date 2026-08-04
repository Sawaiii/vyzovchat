import SwiftUI

/// Кнопка записи голосового: держим — пишем, ведём вверх к замку — фиксируем,
/// ведём влево — отменяем. После фиксации круг становится отправкой.
///
/// Разделена на две вьюхи не ради порядка, а ради плавности. Палец двигает круг
/// десятки раз в секунду, и всё, что лежит с ним в одном теле, пересобирается
/// на каждом кадре жеста. Поэтому здесь остались только замок и пауза — то, что
/// от движения пальца не зависит, — а сам круг вынесен ниже вместе со
/// смещением и жестом.
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

    /// Палец дошёл до замка — подсвечиваем цель, чтобы было видно, что дальше
    /// вести не надо.
    @State private var lockArmed = false

    /// Насколько вести палец вверх до фиксации. Ровно до замка: он висит на
    /// этом же расстоянии, и «дошёл до иконки» должно значить «сработало».
    static let lockDistance: CGFloat = 64

    var body: some View {
        RecordCircle(pressing: $pressing,
                     lockArmed: $lockArmed,
                     isLocked: isLocked,
                     onStart: onStart,
                     onLock: onLock,
                     onCancel: onCancel,
                     onFinish: onFinish)
            // Полоса и замок висят над кнопкой по её месту в лейауте, а не по
            // тому, куда её увёл палец: смещение круга лежит внутри и наружу не
            // выходит, поэтому цель остаётся стоять — к ней и ведут.
            .overlay(alignment: .bottom) { if isActive { floatingPanel } }
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
            .offset(y: -60)
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
            .offset(y: -(Self.lockDistance + 12))
        }
    }
}

/// Сам круг: растёт под пальцем, едет за ним и решает, что жест значит.
///
/// Всё, что меняется на каждом кадре жеста, живёт здесь и только здесь — тело
/// этой вьюхи короткое, и пересобирать его дёшево.
private struct RecordCircle: View {
    @Binding var pressing: Bool
    @Binding var lockArmed: Bool
    let isLocked: Bool

    let onStart: () -> Void
    let onLock: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void

    /// Насколько кнопка уехала за пальцем.
    @State private var drag: CGSize = .zero
    /// Стадия текущего жеста.
    @State private var phase: Phase = .idle

    /// Жест живёт дольше, чем запись: после фиксации или отмены палец обычно
    /// ещё едет, и события продолжают сыпаться. Без явной стадии такое событие
    /// выглядело как новое касание — запись стартовала заново, тут же
    /// отменялась следующим кадром, и так десятки раз за свайп.
    /// `spent` означает «жест своё отработал, ждём отпускания».
    private enum Phase { case idle, tracking, spent }

    private var lockDistance: CGFloat { MicRecordButton.lockDistance }
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
            // Вдвое, а не в полтора: под самим пальцем полуторного круга почти
            // не видно — палец его и закрывает.
            .scaleEffect(pressing ? 2 : 1)
            // Ореол рисуется уже поверх выросшего круга: попади он раньше
            // масштаба, тот бы на него умножился и залил пол-экрана.
            .background { ripple }
            // Анимации через модификатор здесь нет намеренно: она осталась бы в
            // теле, которое пересобирается на каждый кадр движения пальца, и
            // система заново разбирала бы её на каждом кадре. Рост и возврат
            // анимируем явно, в тот единственный момент, когда они начинаются.
            .contentShape(Rectangle())
            // Круг едет за пальцем к замку. Смещение не меняет место в лейауте,
            // поэтому сам замок остаётся стоять — к нему и ведут.
            .offset(drag)
            .gesture(dragGesture)
    }

    /// Ореол вокруг кнопки. Всегда в дереве: меняются только размер и
    /// прозрачность. Раньше он появлялся и исчезал как отдельная ветка, и
    /// SwiftUI пересобирал её переход на каждом кадре жеста — рост кнопки от
    /// этого шёл рывками.
    private var ripple: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.10)).scaleEffect(pressing ? 3.2 : 1)
            Circle().fill(Theme.accent.opacity(0.16)).scaleEffect(pressing ? 2.5 : 1)
        }
        .opacity(pressing ? 1 : 0)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Зафиксированную запись жест не трогает: круг стал обычной
                // кнопкой «отправить». Отработавший жест — тоже: решение уже
                // принято, дальше палец просто едет.
                guard !isLocked, phase != .spent else { return }
                if phase == .idle {
                    phase = .tracking
                    withAnimation(Self.grow) { pressing = true }
                    if lockArmed { lockArmed = false }
                    onStart()
                }
                // Вверх до замка — фиксируем, влево — отменяем. Считаем по
                // сырому смещению: обрезанное упирается в порог и на резком
                // свайпе никогда его не переходит. Резкий свайп ещё и приходит
                // сразу по диагонали, поэтому берём не тот порог, который
                // проверили первым, а тот, что перекрыт сильнее.
                let toLock = -value.translation.height / lockDistance
                let toCancel = -value.translation.width / cancelDistance
                if toLock >= 1 || toCancel >= 1 {
                    finishGesture()
                    if toLock >= toCancel {
                        Haptics.success()
                        onLock()
                    } else {
                        onCancel()
                    }
                } else {
                    drag = CGSize(width: max(min(0, value.translation.width), -cancelDistance),
                                  height: max(min(0, value.translation.height), -70))
                    // Пишем, только когда действительно поменялось: каждая
                    // запись сюда перерисовывает замок этажом выше.
                    let armed = value.translation.height < -25
                    if armed != lockArmed { lockArmed = armed }
                }
            }
            .onEnded { value in
                let wasTracking = phase == .tracking
                phase = .idle
                if isLocked {
                    // Касание по кругу отправляет. Смазанное касание — это уже
                    // прокрутка чего-то другого, не отправка.
                    if abs(value.translation.width) < 12, abs(value.translation.height) < 12 {
                        onFinish()
                    }
                    return
                }
                // Жест уже закрылся замком или отменой — отправлять нечего.
                guard wasTracking else { return }
                release()
                onFinish()
            }
    }

    /// Жест принял решение (замок или отмена): палец ещё на экране, но больше
    /// ничего не решает.
    private func finishGesture() {
        phase = .spent
        release()
    }

    /// Кнопка вернулась на место, палец больше не считается прижатым.
    /// Возврат — с пружиной: на резком свайпе круг уезжает далеко, и прыжок
    /// назад без анимации читается как сбой.
    private func release() {
        if lockArmed { lockArmed = false }
        withAnimation(Self.grow) {
            pressing = false
            drag = .zero
        }
    }

    /// Рост под пальцем и возврат на место — одна и та же пружина.
    private static let grow = Animation.spring(response: 0.28, dampingFraction: 0.78)
}
