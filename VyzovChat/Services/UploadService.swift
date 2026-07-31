import UIKit

/// Выгрузка выбранных фотографий на сервер (в перспективе — S3),
/// с раскладкой по папкам названия мероприятия.
protocol UploadServicing {
    /// Загружает изображения в хранилище. Через `progress` отдаёт прогресс по
    /// каждому индексу (0...1). Возвращает ключи объектов — по ним сервер
    /// потом подписывает ссылки и раскладывает файлы по папкам.
    func upload(
        images: [UIImage],
        folder: String,
        progress: @escaping @MainActor (_ index: Int, _ fraction: Double) -> Void
    ) async throws -> [String]
}

enum UploadError: LocalizedError {
    case notConfigured
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Хранилище S3 ещё не подключено"
        case .failed(let m): return m
        }
    }
}

/// Мок выгрузки: имитирует прогресс и возвращает ключи вида `media/<файл>.jpg`.
final class MockUploadService: UploadServicing {
    func upload(
        images: [UIImage],
        folder: String,
        progress: @escaping @MainActor (Int, Double) -> Void
    ) async throws -> [String] {
        var keys: [String] = []
        for (index, _) in images.enumerated() {
            // Имитация пошаговой загрузки одного файла.
            for step in 1...10 {
                try await Task.sleep(for: .milliseconds(70))
                await progress(index, Double(step) / 10.0)
            }
            keys.append("media/IMG_\(String(format: "%03d", index + 1)).jpg")
        }
        return keys
    }
}
