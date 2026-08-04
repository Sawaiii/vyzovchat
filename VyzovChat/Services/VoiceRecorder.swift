import AVFoundation

/// Включение и выключение аудиосессии.
///
/// Вынесено в актор по двум причинам. Первая: `setActive` — синхронный вызов на
/// десятки миллисекунд, и с главного потока он приходился ровно на начало
/// жеста записи, когда палец уже поехал, — получался рывок. Вторая: включение и
/// выключение должны идти строго по очереди, иначе запоздавшее выключение
/// гасит уже начатую следующую запись.
actor AudioSessionGate {
    static let shared = AudioSessionGate()

    func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord, а не .record: иначе после записи глохнет
        // воспроизведение уже отправленных голосовых.
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    /// Сессия под прослушивание голосового. `.playback` — иначе звук уходит в
    /// «тихий» режим и на выезде его не слышно при включённом переключателе.
    func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Запись голосового сообщения.
///
/// Пишем в m4a (AAC) — этот формат сервер принимает по белому списку загрузок
/// (`audio/mp4`) и его же понимают браузеры, так что запись из приложения
/// слушается и в веб-версии.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    /// Сколько секунд уже пишем — для счётчика в поле ввода.
    @Published private(set) var duration: TimeInterval = 0
    /// Запись на паузе. Доступна только после фиксации: пока держат палец,
    /// ставить паузу нечем и незачем.
    @Published private(set) var isPaused = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    /// Максимальная длина: случайно оставленная запись не должна съесть память
    /// и трафик выездника.
    private let maxDuration: TimeInterval = 5 * 60
    /// Достигнут предел — владелец решает, отправить запись или бросить.
    /// Сам рекордер её не останавливает: иначе интерфейс остался бы думать,
    /// что запись идёт.
    var onLimitReached: (() -> Void)?

    enum RecorderError: LocalizedError {
        case noPermission
        case failed

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return "Нет доступа к микрофону. Разрешите запись в настройках телефона."
            case .failed:
                return "Не удалось начать запись"
            }
        }
    }

    /// Спросить разрешение на микрофон (в первый раз система покажет запрос).
    /// Когда доступ уже выдан — отвечаем сразу, без похода в систему: этот
    /// поход стоит миллисекунд, а приходится он ровно на начало жеста.
    func requestPermission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() async throws {
        guard !isRecording else { return }
        guard await requestPermission() else { throw RecorderError.noPermission }

        do {
            try await AudioSessionGate.shared.activateRecording()
        } catch {
            throw RecorderError.failed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let started = try await Self.makeRecorder(at: url)
        self.recorder = started.recorder
        self.fileURL = url
        isRecording = true
        isPaused = false
        duration = 0
        startTimer()
    }

    /// Готовый рекордер, уже пишущий в файл.
    ///
    /// `@unchecked Sendable` здесь честно: объект создаётся в фоне и сразу
    /// отдаётся на главный поток, после чего в фоне к нему никто не обращается.
    private struct StartedRecorder: @unchecked Sendable {
        let recorder: AVAudioRecorder
    }

    /// Создать рекордер и запустить запись — в фоне.
    ///
    /// И создание (поднимается AAC-кодировщик), и `record()` (заводится
    /// аудиоочередь) занимают вместе сотни миллисекунд. На главном потоке они
    /// приходились ровно на первые кадры жеста: кнопка уже едет за пальцем, а
    /// поток занят — отсюда «первые секунды дико лагает, потом нормально».
    private nonisolated static func makeRecorder(at url: URL) async throws -> StartedRecorder {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,      // голос — моно, вдвое меньше данных
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
                guard let recorder = try? AVAudioRecorder(url: url, settings: settings),
                      recorder.record() else {
                    cont.resume(throwing: RecorderError.failed)
                    return
                }
                cont.resume(returning: StartedRecorder(recorder: recorder))
            }
        }
    }

    /// Приостановить запись. Файл остаётся тем же — продолжение допишется в него.
    func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        recorder.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused, let recorder else { return }
        guard recorder.record() else { return }
        isPaused = false
    }

    /// Закончить запись и отдать файл. `nil` — записи не было или она пустая.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let recorder, let url = fileURL else { return nil }
        let seconds = recorder.currentTime
        recorder.stop()
        finish()
        // Совсем короткие записи (случайное касание) не отправляем.
        guard seconds >= 0.7 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, seconds)
    }

    /// Бросить запись и удалить файл.
    func cancel() {
        guard let url = fileURL else { finish(); return }
        recorder?.stop()
        try? FileManager.default.removeItem(at: url)
        finish()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        fileURL = nil
        isRecording = false
        isPaused = false
        duration = 0
        Task { await AudioSessionGate.shared.deactivate() }
    }

    private func startTimer() {
        timer?.invalidate()
        // Счётчик показывает сотые, поэтому и тикать он должен чаще десяти раз
        // в секунду — иначе цифры дёргаются через раз. Тикает он в отдельной
        // маленькой вью, так что перерисовка дешёвая.
        let tick = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.duration = recorder.currentTime
                if self.duration >= self.maxDuration { self.onLimitReached?() }
            }
        }
        // В общий режим, а не в обычный: пока палец ведёт кнопку или лента
        // прокручивается, цикл событий работает в режиме отслеживания, и
        // счётчик просто замирал до конца жеста — а потом прыгал.
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }
}
