import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    // Общие поля
    @Published var login = ""
    @Published var phone = ""
    @Published var password = ""

    // Поля регистрации
    @Published var fio = ""
    /// Код-приглашение: без него сервер регистрацию не примет.
    @Published var invite = ""
    @Published var email = ""

    @Published var isLoading = false
    @Published var errorText: String?

    private var auth: AuthServicing
    private var onSuccess: (User) -> Void
    private var bound = false

    init(auth: AuthServicing, onSuccess: @escaping (User) -> Void) {
        self.auth = auth
        self.onSuccess = onSuccess
    }

    /// Привязка к реальным сервисам сессии. EnvironmentObject недоступен
    /// в init, поэтому связываем один раз в onAppear экрана.
    func rebindIfNeeded(auth: AuthServicing, onSuccess: @escaping (User) -> Void) {
        guard !bound else { return }
        self.auth = auth
        self.onSuccess = onSuccess
        bound = true
    }

    var loginEnabled: Bool {
        !login.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 4
    }

    var registerEnabled: Bool {
        !fio.trimmingCharacters(in: .whitespaces).isEmpty
            && !login.trimmingCharacters(in: .whitespaces).isEmpty
            && !invite.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 4
    }

    func login() async {
        await run { try await self.auth.login(login: self.login, password: self.password) }
    }

    func register() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let form = RegistrationForm(
            invite: invite.trimmingCharacters(in: .whitespaces),
            fio: fio.trimmingCharacters(in: .whitespaces),
            login: login.trimmingCharacters(in: .whitespaces),
            pass: password,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone
        )
        await run { try await self.auth.register(form) }
    }

    private func run(_ operation: @escaping () async throws -> User) async {
        isLoading = true
        errorText = nil
        do {
            let user = try await operation()
            Haptics.success()
            onSuccess(user)
        } catch {
            Haptics.warning()
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
