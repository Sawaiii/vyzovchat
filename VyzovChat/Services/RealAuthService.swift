import Foundation

/// Реальная авторизация против API Vyzov Chat (логин + пароль, токен в Keychain).
final class RealAuthService: AuthServicing {

    func restoreSession() async -> User? {
        guard TokenStore.token != nil else { return nil }
        do {
            let dto = try await APIClient.shared.get("/api/me", as: WorkerDTO.self)
            await AvatarStore.loadIfNeeded()
            return User(dto: dto)
        } catch {
            TokenStore.token = nil   // токен протух — выходим
            return nil
        }
    }

    func login(login: String, password: String) async throws -> User {
        // На новом бэкенде токен приходит отдельным полем, а не внутри карточки.
        let resp = try await APIClient.shared.post(
            "/api/login",
            json: LoginRequest(login: login.trimmingCharacters(in: .whitespaces), pass: password),
            as: LoginResponseDTO.self
        )
        TokenStore.token = resp.token
        await AvatarStore.reload()
        return User(dto: resp.worker)
    }

    /// Саморегистрация работает только при заданном на сервере коде-приглашении;
    /// без него сервер отвечает `registration_disabled`.
    func register(_ form: RegistrationForm) async throws -> User {
        let resp = try await APIClient.shared.post(
            "/api/register",
            json: RegisterRequest(invite: form.invite, fio: form.fio, login: form.login,
                                  pass: form.pass, email: form.email, phone: form.phone),
            as: LoginResponseDTO.self
        )
        TokenStore.token = resp.token
        await AvatarStore.reload()
        return User(dto: resp.worker)
    }

    /// Своя карточка правится тем же путём, что и чужая: отдельного `PATCH /api/me`
    /// на сервере нет.
    func updateAvatar(key: String, workerId: String) async throws -> User {
        var patch = UpdateWorkerRequest()
        patch.avatar = key
        let dto = try await APIClient.shared.patch("/api/workers/\(workerId)", json: patch, as: WorkerDTO.self)
        return User(dto: dto)
    }

    func signOut() async {
        _ = try? await APIClient.shared.post("/api/logout", json: EmptyBody(), as: OKDTO.self)
        TokenStore.token = nil
    }
}
