import SwiftUI

/// Дорожка этапов под шапкой чата: видно, где бригада сейчас.
///
/// Этапы идут строго по порядку — отметить можно только следующий, снять только
/// последний. У погрузки и приёмки рядом счётчик оборудования: пока чеклист не
/// закрыт, этап не закрывается, и счётчик объясняет почему.
struct StagesTrack: View {
    @ObservedObject var model: ChatViewModel
    /// Нажали на этап с чеклистом — открыть его список.
    let onOpenChecklist: (EquipCheckKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(EventStage.allCases.enumerated()), id: \.element) { index, stage in
                    if index > 0 { arrow(before: stage) }
                    step(stage, number: index + 1)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        // Фон даёт общая шапка: своя подложка у каждой полосы и превращала
        // шапку в стопку приклеенных друг к другу полосок.
        .horizontalStrip()
    }

    private func arrow(before stage: EventStage) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isDone(stage) ? Theme.success : Theme.textSecondary.opacity(0.6))
    }

    private func step(_ stage: EventStage, number: Int) -> some View {
        let done = isDone(stage)
        let isNext = model.nextStage == stage
        let tappable = model.canMark(stage) || model.canUndo(stage) || !stage.checklists.isEmpty

        return Button {
            // Снять отметку — первым делом: у этапов с чеклистом нажатие вело
            // в чеклист всегда, и отменить случайно закрытый этап было нечем.
            if model.canUndo(stage) {
                Task { await model.toggleStage(stage) }
            } else if let kind = defaultChecklist(for: stage) {
                // Закрыть этап всё равно нельзя, пока в чеклисте есть
                // неотмеченные позиции, — ведём туда, а не в отказ.
                onOpenChecklist(kind)
            } else {
                Task { await model.toggleStage(stage) }
            }
        } label: {
            HStack(spacing: 5) {
                mark(done: done, isNext: isNext, number: number)
                Text(stage.title)
                    .font(.system(size: 11, weight: isNext ? .semibold : .regular))
                    .foregroundStyle(done ? Theme.success : (isNext ? Theme.textPrimary : Theme.textSecondary))
                if let counter = counter(for: stage) {
                    Text(counter)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(counterIsFull(stage) ? Theme.success : Theme.textSecondary)
                }
            }
            // Подложки у текущего шага нет: она вылезала левее общей линии, и
            // первый этап выглядел сдвинутым относительно всего остального.
            // Текущий и так виден — синим кружком и жирной подписью.
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        // Долгое нажатие — явные действия. Одним тапом два смысла (открыть
        // чеклист и снять отметку) не разложить, а отмена нужна наверняка:
        // случайно закрытый этап иначе не отменить вовсе.
        .contextMenu {
            if model.canUndo(stage) {
                Button { Task { await model.toggleStage(stage) } } label: {
                    Label("Снять отметку", systemImage: "arrow.uturn.backward")
                }
            }
            if model.canMark(stage) {
                Button { Task { await model.toggleStage(stage) } } label: {
                    Label("Отметить пройденным", systemImage: "checkmark.circle")
                }
            }
            // У загрузки чеклиста два — обе половины в меню отдельными пунктами.
            ForEach(stage.checklists) { kind in
                Button { onOpenChecklist(kind) } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
            // Этап не мой — говорим, чей он. Иначе меню без единого действия
            // выглядит как поломка, хотя это правило прав.
            if !model.canMark(stage) && !model.canUndo(stage) {
                Button {} label: {
                    Label("Этап закрывает \(stage.owner)", systemImage: "info.circle")
                }
                .disabled(true)
            }
        }
    }

    private func mark(done: Bool, isNext: Bool, number: Int) -> some View {
        ZStack {
            Circle()
                .fill(done ? Theme.success.opacity(0.22) : (isNext ? Theme.accent : Color.white.opacity(0.07)))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.success)
            } else {
                Text("\(number)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isNext ? Theme.textOnAccent : Theme.textSecondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func isDone(_ stage: EventStage) -> Bool { model.stagesDone[stage.rawValue] != nil }

    /// Какой чеклист открыть по тапу на этап: свой, если он у нас есть, иначе
    /// первый — посмотреть чужую половину можно, отметить нет.
    private func defaultChecklist(for stage: EventStage) -> EquipCheckKind? {
        let kinds = stage.checklists
        return kinds.first { model.canCheck($0) } ?? kinds.first
    }

    /// «3/7» у этапов с чеклистом — и только когда оборудование вообще заведено.
    /// У загрузки считаем по отстающей стороне: этап ждёт обе.
    private func counter(for stage: EventStage) -> String? {
        let kinds = stage.checklists
        guard !kinds.isEmpty, let p = model.equipProgress, p.total > 0 else { return nil }
        let done = kinds.map { p.done($0) }.min() ?? 0
        return "\(done)/\(p.total)"
    }

    private func counterIsFull(_ stage: EventStage) -> Bool { (model.checklistLeft(stage) ?? 1) == 0 }
}
