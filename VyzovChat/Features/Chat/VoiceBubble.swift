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
                // Полоса воспроизведения. Длительность до первого запуска
                // неизвестна — сервер её не присылает, поэтому до старта
                // показываем ровную линию, а не ноль из ниоткуда.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Theme.accent)
                            .frame(width: geo.size.width * player.progress)
                    }
                }
                .frame(height: 4)

                Text(player.timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 150)
        }
        .padding(.vertical, 4)
        .onDisappear { player.stop() }
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
        if player == nil {
            // .playback — иначе звук уходит в «тихий» режим и на выезде его
            // просто не слышно при включённом беззвучном переключателе.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
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
        player?.play()
        isPlaying = true
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
