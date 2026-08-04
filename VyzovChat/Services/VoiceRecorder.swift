import AVFoundation
import QuartzCore

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
        // Буфер побольше — реже прерывания. Аудио идёт в потоке с приоритетом
        // выше главного и вытесняет его на каждом буфере; при буфере по
        // умолчанию это десятки раз в секунду, и приходится это ровно на время,
        // когда палец ведёт кнопку. Для голосового сообщения задержка ввода
        // роли не играет — это не разговор.
        try? session.setPreferredIOBufferDuration(0.04)
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
    /// Громкость голоса, 0…1 — по ней дышит волна вокруг кнопки.
    /// Считается, только пока это кому-то нужно, см. `setMetering`.
    @Published private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    private var isMetering = false

    /// Время старта и накопленная пауза — по ним и считаем длительность.
    ///
    /// Спрашивать `recorder.currentTime` двадцать раз в секунду нельзя: это
    /// обращение к аудиоочереди, и главный поток на нём ждёт, пока очередь
    /// отпустит поток записи. Каждое ожидание короткое, но приходит двадцать
    /// раз в секунду и ровно поверх жеста — это и была вязкость, которая не
    /// проходила и через несколько секунд удержания. Часы для счётчика нам
    /// нужны обычные, а не «сколько именно записано».
    private var startedAt: CFTimeInterval = 0
    private var pausedTotal: CFTimeInterval = 0
    private var pausedAt: CFTimeInterval?

    private var elapsed: TimeInterval {
        let now = pausedAt ?? CACurrentMediaTime()
        return max(0, now - startedAt - pausedTotal)
    }

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
        startedAt = CACurrentMediaTime()
        pausedTotal = 0
        pausedAt = nil
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
                    // 24 кГц, а не 44,1: это речь, а не музыка. Слышимой разницы
                    // нет, а кодировщику работы вдвое меньше — и файл вдвое
                    // легче, что на площадке с плохой связью важнее качества,
                    // которого всё равно не слышно.
                    AVSampleRateKey: 24000,
                    AVNumberOfChannelsKey: 1,      // голос — моно, вдвое меньше данных
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
                guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
                    cont.resume(throwing: RecorderError.failed)
                    return
                }
                // Замер громкости включаем до старта: на ходу это работает не
                // везде. Спрашивать уровень будем только когда он нужен.
                recorder.isMeteringEnabled = true
                guard recorder.record() else {
                    cont.resume(throwing: RecorderError.failed)
                    return
                }
                cont.resume(returning: StartedRecorder(recorder: recorder))
            }
        }
    }

    /// Включить или выключить замер громкости.
    ///
    /// Отдельным выключателем, а не «всегда» — намеренно. `updateMeters` — это
    /// обращение к аудиоочереди, ровно то, из-за чего жест записи шёл рывками:
    /// главный поток на нём ждёт поток записи. Поэтому меряем только там, где
    /// волна видна и где пальца на экране уже нет — у зафиксированной записи.
    /// Сам замер в рекордере включён с самого начала: включать его на ходу
    /// ненадёжно, а считать громкость буфера потоку записи почти ничего не
    /// стоит. Дорого — спрашивать её отсюда, это и переключаем.
    func setMetering(_ on: Bool) {
        isMetering = on
        if !on { level = 0 }
    }

    /// Приостановить запись. Файл остаётся тем же — продолжение допишется в него.
    func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        recorder.pause()
        pausedAt = CACurrentMediaTime()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused, let recorder else { return }
        guard recorder.record() else { return }
        if let pausedAt { pausedTotal += CACurrentMediaTime() - pausedAt }
        pausedAt = nil
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
        isMetering = false
        level = 0
        Task { await AudioSessionGate.shared.deactivate() }
    }

    /// Пересчитать громкость в 0…1.
    ///
    /// Микрофон отдаёт децибелы относительно максимума: −160 это тишина, 0 —
    /// клиппинг. Речь живёт примерно между −45 и −5, поэтому и растягиваем
    /// именно этот отрезок — иначе волна почти не шевелилась бы. Сглаживаем:
    /// без этого она дёргается на каждом слоге вместо того, чтобы дышать.
    private func updateLevel(_ recorder: AVAudioRecorder) {
        recorder.updateMeters()
        let db = Double(recorder.averagePower(forChannel: 0))
        let loud = min(1, max(0, (db + 45) / 40))
        let smoothed = level * 0.6 + loud * 0.4
        // Мелкую рябь не публикуем: каждая публикация — обновление интерфейса.
        guard abs(smoothed - level) > 0.02 else { return }
        level = smoothed
    }

    private func startTimer() {
        timer?.invalidate()
        // Тикаем чаще, чем меняется цифра: так смена десятой доли не запаздывает
        // на полтика. Публикуем при этом только саму смену — см. ниже.
        let tick = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            // Таймер добавлен в главный цикл — значит, мы уже на главном
            // потоке, и прыгать через задачу незачем: двадцать задач в секунду
            // и сами по себе работа, и обновление счётчика от них отстаёт.
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                if self.isMetering { self.updateLevel(recorder) }
                // Считаем в десятых и публикуем, только когда цифра правда
                // сменилась. Каждая публикация — это обновление интерфейса, а
                // приходятся они на то же время, когда палец ведёт кнопку
                // записи. Сотые доли столько не стоят: их всё равно не успеть
                // прочитать, а обновлений от них вдвое больше.
                let value = Double(Int(self.elapsed * 10)) / 10
                guard value != self.duration else { return }
                self.duration = value
                if value >= self.maxDuration { self.onLimitReached?() }
            }
        }
        // В общий режим, а не в обычный: пока палец ведёт кнопку или лента
        // прокручивается, цикл событий работает в режиме отслеживания, и
        // счётчик просто замирал до конца жеста — а потом прыгал.
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }
}
