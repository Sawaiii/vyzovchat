import Foundation

/// Аутентификация по логину и паролю (как на реальном бэкенде vyezd-chat).
protocol AuthServicing {
    /// Восстановить сессию при запуске (по сохранённому токену).
    func restoreSession() async -> User?
    /// Вход по логину и паролю.
    func login(login: String, password: String) async throws -> User
    /// Регистрация (на реальном бэкенде отключена — сотрудников заводит админ).
    func register(_ form: RegistrationForm) async throws -> User
    /// Обновить фото профиля: `key` — ключ объекта, выданный presign.
    func updateAvatar(key: String, workerId: String) async throws -> User
    /// Выход.
    func signOut() async
}

/// Саморегистрация (`POST /api/register`). Открыта только по коду-приглашению:
/// сервер сверяет его со своим `REG_INVITE_CODE`, иначе регистрации нет вовсе.
/// Такой сотрудник получает Диск и Фотобанк, но чатов у него не будет, пока его
/// не добавят в мероприятие.
struct RegistrationForm: Encodable {
    var invite: String
    var fio: String
    var login: String
    var pass: String
    var email: String?
    var phone: String?
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case weakPassword
    case userNotFound
    case registrationDisabled
    case network

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Неверный логин или пароль"
        case .weakPassword: return "Пароль должен быть не короче 6 символов"
        case .userNotFound: return "Сотрудник не найден"
        case .registrationDisabled: return "Регистрация недоступна: аккаунт создаёт администратор"
        case .network: return "Нет связи с сервером. Попробуйте позже."
        }
    }
}

/// Мок: любой валидный ввод пускает под учётной записью демо-пользователя.
final class MockAuthService: AuthServicing {
    private let sessionKey = "vyzovchat.session.userId"

    func restoreSession() async -> User? {
        try? await Task.sleep(for: .milliseconds(600)) // имитация проверки токена
        guard UserDefaults.standard.string(forKey: sessionKey) != nil else { return nil }
        return MockData.currentUser
    }

    func login(login: String, password: String) async throws -> User {
        try await Task.sleep(for: .milliseconds(800))
        guard !login.trimmingCharacters(in: .whitespaces).isEmpty else { throw AuthError.invalidCredentials }
        guard password.count >= 4 else { throw AuthError.invalidCredentials }
        UserDefaults.standard.set(MockData.currentUser.id, forKey: sessionKey)
        return MockData.currentUser
    }

    func register(_ form: RegistrationForm) async throws -> User {
        try await Task.sleep(for: .milliseconds(900))
        guard form.pass.count >= 4 else { throw AuthError.weakPassword }
        UserDefaults.standard.set(MockData.currentUser.id, forKey: sessionKey)
        return MockData.currentUser
    }

    func updateAvatar(key: String, workerId: String) async throws -> User { MockData.currentUser }

    func signOut() async {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }
}
