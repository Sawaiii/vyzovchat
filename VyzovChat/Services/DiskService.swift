import Foundation

/// Общий диск: файловый менеджер поверх хранилища. Содержимое видят все вошедшие,
/// удалять может админ (и реализатор — у него на Диске полный доступ).
///
/// Поиска по папкам, скачивания архивом и перемещения на новом сервере нет —
/// таких эндпоинтов не существует, поэтому и в приложении этих действий больше нет.
protocol DiskServicing {
    func list(path: String) async -> DiskListDTO?
    /// Удалить файлы по ключам объектов. Папку удалить нельзя — только файлы.
    func delete(keys: [String]) async throws
    /// Сообщить остальным, что содержимое изменилось (после прямой заливки в хранилище).
    func notifyChanged() async
}

final class RealDiskService: DiskServicing {
    func list(path: String) async -> DiskListDTO? {
        // «+» кодируем сами. URLComponents оставляет его как есть, а сервер читает
        // плюс в query как пробел — папка компании «А+» превращалась в «А », и её
        // содержимое не открывалось вовсе.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return try? await APIClient.shared.get("/api/disk/list?path=\(encoded)", as: DiskListDTO.self)
    }

    func delete(keys: [String]) async throws {
        _ = try await APIClient.shared.post("/api/disk/delete",
                                            json: DiskDeleteRequest(keys: keys), as: OKDTO.self)
    }

    func notifyChanged() async {
        _ = try? await APIClient.shared.post("/api/disk/notify", json: EmptyBody(), as: OKDTO.self)
    }
}

final class MockDiskService: DiskServicing {
    /// Вымышленное содержимое диска — чтобы экран не выглядел пустым при съёмке.
    func list(path: String) async -> DiskListDTO? {
        try? await Task.sleep(for: .milliseconds(400))
        let folders = [
            "Конференция «Логистика 2026» (#4102)",
            "Свадьба Королёвых — Loft Hall (#4098)",
            "Корпоратив «ТехноПром» (#4091)",
            "Юбилей 50 лет — ресторан «Волга» (#4085)",
            "Выставка «АгроЭкспо» (#4077)"
        ]
        let files: [(String, Int)] = [
            ("Смета мероприятия.pdf", 486_000),
            ("Схема расстановки.pdf", 1_240_000),
            ("Акт приёма оборудования.pdf", 302_000)
        ]
        let entries = folders.map {
            DiskEntryDTO(name: $0, is_dir: true, key: "\(path)\($0)/", size: nil,
                         url: nil, download_url: nil)
        } + files.map {
            DiskEntryDTO(name: $0.0, is_dir: false, key: "\(path)\($0.0)", size: $0.1,
                         url: nil, download_url: nil)
        }
        return DiskListDTO(path: path, entries: entries)
    }
    func delete(keys: [String]) async throws {}
    func notifyChanged() async {}
}
