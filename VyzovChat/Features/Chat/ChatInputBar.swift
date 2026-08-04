import SwiftUI

/// Строка ввода чата: поле с черновиком, вложения и запись голосового.
///
/// Отдельная вью — не ради порядка. Нажатие на микрофон, старт записи и её
/// фиксация меняли состояние прямо на экране чата, а тело экрана — это шапка,
/// этапы, полоса тем и пейджер со всеми лентами разом. Каждое такое изменение
/// перерисовывало всё это заново, и приходились они ровно на первую секунду
/// жеста: касание, запуск записи, замок. Отсюда и «двигается в пять кадров, а
/// потом нормально» — как только состояние переставало меняться, экран
/// переставали перерисовывать.
///
/// Поэтому состояние записи живёт здесь и дальше этой строки не выходит.
/// Модель по-прежнему пишет звук и отправляет его, но экрану об этом больше не
/// рассказывает.
struct ChatInputBar: View {
    @ObservedObject var model: ChatViewModel
    @Binding var showPhotoPicker: Bool
    @Binding var showFileImporter: Bool

    /// Палец на микрофоне. Отдельно от «идёт запись»: запись стартует
    /// асинхронно, а строка должна смениться в тот же миг, когда её коснулись.
    @State private var isPressingMic = false
    @State private var isRecording = false
    @State private var isLocked = false
    @State private var isPaused = false

    /// Идёт запись или её вот-вот начнут — поле ввода уступает место счётчику.
    private var isRecordingUI: Bool { isPressingMic || isRecording }

    private var hasDraft: Bool { !model.draft.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if isRecordingUI {
                    // Счётчик тикает двадцать раз в секунду. Он живёт в отдельной
                    // вью со своим наблюдением за рекордером — иначе
                    // перерисовывалась бы вся строка на каждый тик.
                    RecordingBar(recorder: model.recorder,
                                 isLocked: isLocked,
                                 onCancel: { cancel() })
                } else {
                    textField
                }
            }
            .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
            .background(Theme.panel)

            // Правая кнопка нарисована поверх строки, а не внутри неё: во время
            // записи она вырастает в круг с ореолом и вылезает за её пределы, а
            // над ней всплывает замок. И, что важнее, она одна на все состояния —
            // убери её из дерева при смене ветки, и посреди удержания оборвался
            // бы жест, а вместе с ним и запись.
            trailingControl
                .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
        }
        // Предел длины записи рекордер сообщает владельцу, а не обрывает сам:
        // иначе строка осталась бы думать, что запись идёт.
        .onAppear {
            model.recorder.onLimitReached = { finish() }
        }
    }

    private var textField: some View {
        HStack(spacing: Spacing.s) {
            Menu {
                Button { showPhotoPicker = true } label: { Label("Фото и видео", systemImage: "photo.on.rectangle") }
                Button { showFileImporter = true } label: { Label("Файл", systemImage: "doc") }
            } label: {
                Image(systemName: "paperclip").font(.title3).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
            }

            TextField("Сообщение", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, Spacing.m).padding(.vertical, 10)
                .background(Theme.panel2, in: Capsule())

            // Место под правую кнопку: сама она нарисована поверх строки.
            Color.clear.frame(width: 40, height: 40)
        }
    }

    /// Что справа от поля: отправка текста, микрофон или — у зафиксированной
    /// записи — отправка голосового.
    @ViewBuilder
    private var trailingControl: some View {
        if hasDraft && !isRecordingUI {
            Button { Task { await model.send() } } label: {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.accent, in: Circle())
            }
        } else {
            micButton
        }
    }

    /// Запись голосового удержанием, как в мессенджерах: держим — пишем,
    /// ведём вверх — фиксируем и можно отпустить, ведём влево — отменяем.
    ///
    /// После фиксации палец не нужен: круг становится отправкой, над ним
    /// появляется пауза, а отмена — обычной кнопкой в строке. На площадке в
    /// перчатках жест срывается, и без этого запасного пути записанное
    /// терялось бы.
    private var micButton: some View {
        MicRecordButton(
            pressing: $isPressingMic,
            isLocked: isLocked,
            isActive: isRecordingUI,
            isPaused: isPaused,
            onStart: { start() },
            onLock: { isLocked = true },
            onCancel: { cancel() },
            onFinish: { finish() },
            onTogglePause: {
                model.togglePause()
                isPaused = model.isRecordingPaused
            })
    }

    // MARK: - Запись

    private func start() {
        Task {
            await model.startRecording()
            // Пока запись заводилась, палец могли уже отпустить — тогда её
            // остановит `finish()`, и включать счётчик обратно нельзя.
            guard isPressingMic || isLocked else { return }
            isRecording = model.isRecording
        }
    }

    /// Ждём внутри модели: короткое нажатие могло отпуститься раньше, чем
    /// запись успела начаться.
    private func finish() {
        resetRecordingUI()
        Task { await model.finishRecording() }
    }

    private func cancel() {
        resetRecordingUI()
        Task { await model.cancelRecording() }
    }

    private func resetRecordingUI() {
        isRecording = false
        isLocked = false
        isPaused = false
    }
}
