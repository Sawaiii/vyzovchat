import SwiftUI
import AVFoundation

/// Голосовое сообщение в ленте: кнопка воспроизведения, полоса и длительность.
struct VoiceBubble: View {
    let attachment: Message.Attachment
    let isMine: Bool

    @StateObject private var player = AudioPlayer()

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button {
                if let url = attachment.remoteURL { player.toggle(url) }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.textOnAccent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                VoiceWaveform(seed: attachment.id, progress: player.progress)
                    .frame(height: 26)

                // Длительность до первого запуска неизвестна — сервер её не
                // присылает, поэтому до старта там прочерк, а не ноль из ниоткуда.
                Text(player.timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 170)
        }
        .padding(.vertical, 4)
        .onDisappear { player.stop() }
    }
}

/// Столбики голосового — «горы» вместо ровной полосы: сразу видно, что это
/// звук, и по ним же видно, докуда доиграло.
///
/// Форма нарисована, а не измерена. Волну сервер не хранит и не отдаёт, а
/// посчитать её по-настоящему можно только скачав и раскодировав сам файл —
/// ради картинки под кнопкой это слишком дорого, и до нажатия «играть» файла у
/// нас вообще нет. Зато форма постоянна: высоты выводятся из id вложения, и
/// одно и то же сообщение всегда выглядит одинаково — и после перерисовки, и
/// после перезапуска приложения.
struct VoiceWaveform: View {
    let seed: String
    /// Доля проигранного, 0…1.
    let progress: Double

    private static let barCount = 34
    private static let spacing: CGFloat = 2

    var body: some View {
        let bars = Self.bars(seed: seed)
        GeometryReader { geo in
            let total = Self.spacing * CGFloat(Self.barCount - 1)
            let width = max(1, (geo.size.width - total) / CGFloat(Self.barCount))
            HStack(spacing: Self.spacing) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(played(i) ? Theme.accent : Color.white.opacity(0.28))
                        .frame(width: width, height: max(3, geo.size.height * bars[i]))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func played(_ index: Int) -> Bool {
        Double(index) / Double(Self.barCount) < progress
    }

    /// Высоты столбиков из id вложения.
    ///
    /// Своя арифметика, а не `hashValue`: тот у строк солится при каждом запуске
    /// приложения, и волна у одного и того же сообщения менялась бы от запуска
    /// к запуску. Здесь — FNV поверх байтов и обычный линейный генератор.
    static func bars(seed: String) -> [CGFloat] {
        var state: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            state = (state ^ UInt64(byte)) &* 1099511628211
        }
        return (0..<barCount).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = CGFloat((state >> 33) % 1000) / 1000
            // Не ниже четверти высоты: столбик в ноль читается как пропуск,
            // будто там дырка в записи.
            return 0.25 + unit * 0.75
        }
    }
}

/// Проигрывание одного голосового. Отдельный объект на пузырь: несколько
/// сообщений в ленте не должны драться за один плеер.
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var timeLabel = "--:--"

    private var player: AVPlayer?
    private var observer: Any?

    func toggle(_ url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        isPlaying = true
        guard player == nil else {
            player?.play()
            return
        }
        // Настройка сессии — через общий шлюз и не на главном потоке: сам вызов
        // стоит десятки миллисекунд, а очередь нужна, чтобы он не столкнулся с
        // включением записи. Звук пускаем уже после: включи раньше — первые
        // мгновения ушли бы в прежнюю категорию, а с включённым беззвучным
        // переключателем это просто тишина.
        Task {
            await AudioSessionGate.shared.activatePlayback()
            guard isPlaying else { return }   // успели нажать паузу
            makePlayer(url)
            player?.play()
        }
    }

    private func makePlayer(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    func stop() {
        player?.pause()
        isPlaying = false
    }

    private func tick(_ time: CMTime) {
        guard let item = player?.currentItem else { return }
        let total = item.duration.seconds
        let current = time.seconds
        if total.isFinite, total > 0 {
            progress = min(1, current / total)
            timeLabel = Self.format(current) + " / " + Self.format(total)
        } else {
            timeLabel = Self.format(current)
        }
    }

    private func finish() {
        player?.seek(to: .zero)
        isPlaying = false
        progress = 0
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    deinit {
        if let observer { player?.removeTimeObserver(observer) }
    }
}
