import UIKit

/// Выгрузка фото в хранилище (presign → прямой PUT в S3).
///
/// Возвращает ключи объектов, а не ссылки: ссылку на показ подписывает сервер,
/// и живёт она сутки, так что хранить её как результат загрузки бессмысленно.
/// Раскладку по папкам мероприятия делает выгрузка отчёта
/// (`POST /api/events/{id}/export`), а не сама загрузка.
final class RealUploadService: UploadServicing {
    func upload(
        images: [UIImage],
        folder: String,
        progress: @escaping @MainActor (Int, Double) -> Void
    ) async throws -> [String] {
        var keys: [String] = []
        for (index, image) in images.enumerated() {
            await progress(index, 0.1)
            let name = "IMG_\(String(format: "%03d", index + 1)).jpg"
            guard let media = try? await MediaUploader.uploadImage(image, filename: name) else { continue }
            await progress(index, 1.0)
            keys.append(media.key)
        }
        return keys
    }
}
