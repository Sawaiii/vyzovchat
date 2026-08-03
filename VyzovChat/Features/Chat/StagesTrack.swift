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
            HStack(spacing: 2) {
                ForEach(Array(EventStage.allCases.enumerated()), id: \.element) { index, stage in
                    if index > 0 { arrow(before: stage) }
                    step(stage, number: index + 1)
                }
            }
            // У шага свой отступ в 8 — чтобы кружок первого этапа встал на ту же
            // линию, что бейджи и дата выше, снаружи остаётся ровно остаток.
            .padding(.horizontal, Spacing.m - 8)
            .padding(.vertical, 6)
        }
        .background(Theme.panel.opacity(0.6))
    }

    private func arrow(before stage: EventStage) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isDone(stage) ? Theme.success : Theme.textSecondary.opacity(0.6))
    }

    private func step(_ stage: EventStage, number: Int) -> some View {
        let done = isDone(stage)
        let isNext = model.nextStage == stage
        let tappable = model.canMark(stage) || model.canUndo(stage) || stage.checklist != nil

        return Button {
            // У погрузки и приёмки нажатие ведёт в чеклист: закрыть этап всё
            // равно нельзя, пока в нём есть неотмеченные позиции.
            if let kind = stage.checklist, !model.canMark(stage) || (model.checklistLeft(stage) ?? 0) > 0 {
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
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isNext ? Theme.accent.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
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

    /// «3/7» у этапов с чеклистом — и только когда оборудование вообще заведено.
    private func counter(for stage: EventStage) -> String? {
        guard let kind = stage.checklist, let p = model.equipProgress, p.total > 0 else { return nil }
        return "\(kind == .loaded ? p.loaded : p.returned)/\(p.total)"
    }

    private func counterIsFull(_ stage: EventStage) -> Bool { (model.checklistLeft(stage) ?? 1) == 0 }
}
