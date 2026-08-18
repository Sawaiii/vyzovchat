import SwiftUI
import UIKit
import Combine

/// Глобальное состояние сессии: кто вошёл, какие сервисы используются.
/// Все сервисы объявлены через протоколы — на этом этапе это моки,
/// Реализации сервисов подставляются здесь — экраны работают через протоколы.
@MainActor
final class AppSession: ObservableObject {

    enum AuthState: Equatable {
        case loading
        case signedOut
        case signedIn(User)
    }

    @Published private(set) var authState: AuthState = .loading

    /// Токен приглашения по ссылке `/join/<token>`, которое надо показать поверх
    /// всего: и до входа (гость склада вообще не заводит пароля), и после —
    /// приглашение приходит в переписке в любой момент.
    @Published var pendingInvite: String?

    // MARK: - Сервисы (dependency container)
    let auth: AuthServicing
    let chats: ChatServicing
    let directory: DirectoryServicing
    let uploader: UploadServicing
    let disk: DiskServicing
    let shifts: ShiftsServicing
    let eventInfo: EventInfoServicing
    let dashboard: DashboardServicing

    init(
        auth: AuthServicing = Backend.auth(),
        chats: ChatServicing = Backend.chat(),
        directory: DirectoryServicing = Backend.directory(),
        uploader: UploadServicing = Backend.uploader(),
        disk: DiskServicing = Backend.disk(),
        shifts: ShiftsServicing = Backend.shifts(),
        eventInfo: EventInfoServicing = Backend.eventInfo(),
        dashboard: DashboardServicing = Backend.dashboard()
    ) {
        self.auth = auth
        self.chats = chats
        self.directory = directory
        self.uploader = uploader
        self.disk = disk
        self.shifts = shifts
        self.eventInfo = eventInfo
        self.dashboard = dashboard
    }

    var currentUser: User? {
        if case let .signedIn(user) = authState { return user }
        return nil
    }

    /// Вошли гостем (роль `guest`, с 14 августа 2026): смотреть можно всё, менять
    /// нельзя ничего. Поле статическое, потому что знать об этом должны и модели,
    /// которым сессию не передают, — например `ChatViewModel`, гасящий по нему
    /// права из `me_rights`: гостя сервер считает админом любого чата, иначе
    /// половина окон ему просто не открылась бы.
    private(set) static var isGuest = false

    private func rememberRole(_ user: User?) {
        AppSession.isGuest = user?.isGuest ?? false
    }

    /// Открыть приглашение по ссылке (deep link или вставленная руками ссылка).
    func openInvite(rawLink: String) -> Bool {
        guard let token = InviteLink.token(from: rawLink) else { return false }
        pendingInvite = token
        return true
    }

    func bootstrap() async {
        if let user = await auth.restoreSession() {
            authState = .signedIn(user)
            rememberRole(user)
            connectRealtime()
        } else {
            authState = .signedOut
            rememberRole(nil)
        }
    }

    func handleSignedIn(_ user: User) {
        withAnimation(.smooth) { authState = .signedIn(user) }
        rememberRole(user)
        connectRealtime()
    }

    func signOut() async {
        RealtimeService.shared.reset()
        AvatarStore.clear()
        await auth.signOut()
        withAnimation(.smooth) { authState = .signedOut }
        rememberRole(nil)
    }

    /// Открыть канал реального времени с сохранённым токеном.
    private func connectRealtime() {
        guard !AppConfig.useMockData, let token = TokenStore.token, let user = currentUser else { return }
        RealtimeService.shared.currentUserId = user.id
        RealtimeService.shared.currentUserFio = user.fio.isEmpty ? user.fullName : user.fio
        RealtimeService.shared.connect(token: token)
        // Геолокацию тут больше не просим. Сразу после входа этот запрос ничем
        // не объяснён: человек ещё ничего не снимал и на смену не вставал, —
        // а App Store требует спрашивать разрешение там, где видно зачем.
        // Спрашиваем при открытии выбора фото и при отметке смены.
        Task { await AvatarStore.loadIfNeeded() }        // фото профилей для ленты и списков
    }

    /// Обновить аватар: залить фото в хранилище и записать ключ в профиль.
    func updateAvatar(_ image: UIImage) async {
        guard case .signedIn(let user) = authState else { return }
        if AppConfig.useMockData { return }
        do {
            let key = try await MediaUploader.uploadAvatar(image)
            let updated = try await auth.updateAvatar(key: key, workerId: user.id)
            await AvatarStore.reload()   // карта аватаров общая — перечитываем целиком
            authState = .signedIn(updated)
        } catch {
            // молча игнорируем — можно показать тост позже
        }
    }
}
