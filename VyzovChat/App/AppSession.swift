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

    func bootstrap() async {
        if let user = await auth.restoreSession() {
            authState = .signedIn(user)
            connectRealtime()
        } else {
            authState = .signedOut
        }
    }

    func handleSignedIn(_ user: User) {
        withAnimation(.smooth) { authState = .signedIn(user) }
        connectRealtime()
    }

    func signOut() async {
        RealtimeService.shared.reset()
        AvatarStore.clear()
        await auth.signOut()
        withAnimation(.smooth) { authState = .signedOut }
    }

    /// Открыть канал реального времени с сохранённым токеном.
    private func connectRealtime() {
        guard !AppConfig.useMockData, let token = TokenStore.token, let user = currentUser else { return }
        RealtimeService.shared.currentUserId = user.id
        RealtimeService.shared.currentUserFio = user.fio.isEmpty ? user.fullName : user.fio
        RealtimeService.shared.connect(token: token)
        LocationProvider.shared.requestAuthorization()   // геометки для фото (юр. инфа)
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
