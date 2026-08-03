import AVFoundation

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
    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() async throws {
        guard !isRecording else { return }
        guard await requestPermission() else { throw RecorderError.noPermission }

        let session = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord, а не .record: иначе после записи глохнет
            // воспроизведение уже отправленных голосовых.
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw RecorderError.failed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,          // голос — моно, вдвое меньше данных
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings), recorder.record() else {
            throw RecorderError.failed
        }
        self.recorder = recorder
        self.fileURL = url
        isRecording = true
        isPaused = false
        duration = 0
        startTimer()
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        timer?.invalidate()
        // Счётчик показывает сотые, поэтому и тикать он должен чаще десяти раз
        // в секунду — иначе цифры дёргаются через раз. Тикает он в отдельной
        // маленькой вью, так что перерисовка дешёвая.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.duration = recorder.currentTime
                if self.duration >= self.maxDuration { self.onLimitReached?() }
            }
        }
    }
}
