import Foundation

/// Точка выбора реализации сервисов: реальный API или моки (по флагу AppConfig).
enum Backend {
    static func auth() -> AuthServicing {
        AppConfig.useMockData ? MockAuthService() : RealAuthService()
    }
    static func chat() -> ChatServicing {
        AppConfig.useMockData ? MockChatService() : RealChatService()
    }
    static func directory() -> DirectoryServicing {
        AppConfig.useMockData ? MockDirectoryService() : RealDirectoryService()
    }
    static func uploader() -> UploadServicing {
        AppConfig.useMockData ? MockUploadService() : RealUploadService()
    }
    static func dashboard() -> DashboardServicing {
        AppConfig.useMockData ? MockDashboardService() : RealDashboardService()
    }
    static func eventInfo() -> EventInfoServicing {
        AppConfig.useMockData ? MockEventInfoService() : RealEventInfoService()
    }
    static func shifts() -> ShiftsServicing {
        AppConfig.useMockData ? MockShiftsService() : RealShiftsService()
    }
    static func disk() -> DiskServicing {
        AppConfig.useMockData ? MockDiskService() : RealDiskService()
    }
    static func photobank() -> PhotobankServicing {
        AppConfig.useMockData ? MockPhotobankService() : RealPhotobankService()
    }
}

/// Кэш справочника сотрудников: не дёргаем /api/workers при каждом открытии чата.
@MainActor
enum DirectoryCache {
    private static var users: [User] = []
    private static var loadedAt: Date?
    private static let ttl: TimeInterval = 300   // 5 минут

    static func colleagues() async -> [User] {
        if let loadedAt, !users.isEmpty, Date().timeIntervalSince(loadedAt) < ttl {
            return users
        }
        let fresh = await Backend.directory().fetchColleagues()
        if !fresh.isEmpty {
            users = fresh
            loadedAt = Date()
        }
        return users
    }

    static func invalidate() {
        users = []
        loadedAt = nil
    }
}
