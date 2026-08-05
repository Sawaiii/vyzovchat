import SwiftUI
import PhotosUI

/// Ссылка привязки Яндекса. Обёртка нужна `sheet(item:)` — URL не Identifiable.
struct YandexLinkTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @State private var avatarPick: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var showWorkers = false

    // Привязка Яндекса
    @State private var yandexLinked = false
    @State private var yandexBusy = false
    @State private var yandexNote: String?
    @State private var yandexLinkURL: YandexLinkTarget?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                ScrollView {
                    VStack(spacing: Spacing.m) {
                        if let user = session.currentUser {
                            header(user)
                            infoCard(user)
                        }
                        if session.currentUser?.isAdmin == true { adminCard }
                        yandexCard
                        settingsCard
                        signOutButton
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, Spacing.m)
                }
            }
            .navigationTitle("Профиль")
            // Внутри стека: полоса уезжает вместе с экраном при переходе.
            .appTabBar()
        }
    }

    private func header(_ user: User) -> some View {
        VStack(spacing: Spacing.s) {
            PhotosPicker(selection: $avatarPick, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    avatarImage(user)
                    Image(systemName: uploadingAvatar ? "arrow.triangle.2.circlepath" : "camera.fill")
                        .font(.caption).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                }
            }
            .onChange(of: avatarPick) {
                guard let avatarPick else { return }
                Task {
                    uploadingAvatar = true
                    if let data = try? await avatarPick.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await session.updateAvatar(image)
                    }
                    uploadingAvatar = false
                    self.avatarPick = nil
                }
            }

            Text(user.fullName)
                .font(Typography.title).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if !user.position.isEmpty {
                Text(user.position).font(Typography.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, Spacing.s)
    }

    private func avatarImage(_ user: User) -> some View {
        Group {
            if let url = user.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Avatar(name: user.fullName, size: 96, id: user.id)
                }
                .frame(width: 96, height: 96).clipShape(Circle())
            } else {
                Avatar(name: user.fullName, size: 96, id: user.id)
            }
        }
    }

    private func infoCard(_ user: User) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                row("ID", user.workerId, "number")
                Divider().opacity(0.3)
                row("Должность / специализация", user.position.isEmpty ? "—" : user.position, "briefcase.fill")
                Divider().opacity(0.3)
                row("Телефон", user.phone.isEmpty ? "—" : user.phone, "phone.fill")
                if !user.login.isEmpty {
                    Divider().opacity(0.3)
                    row("Логин", user.login, "person.fill")
                }
                if let dept = user.department {
                    Divider().opacity(0.3)
                    row("Отдел", dept, "building.2.fill")
                }
            }
        }
    }

    /// Админский раздел — управление сотрудниками.
    private var adminCard: some View {
        Button { showWorkers = true } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "person.3.fill").foregroundStyle(Theme.accent).frame(width: 24)
                Text("Сотрудники").font(Typography.callout).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(Spacing.m)
            .glass(cornerRadius: Theme.cornerLarge)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $showWorkers) {
            WorkersView().environmentObject(session)
        }
    }

    /// Яндекс: привязать вход к своей учётке или отвязать.
    ///
    /// Привязанный Яндекс — это способ войти без пароля, поэтому состояние
    /// спрашиваем у сервера (`yandex_linked` есть только в карточке одного
    /// человека), а не выводим из чего-то местного.
    private var yandexCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(Theme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Вход через Яндекс").font(Typography.callout)
                            .foregroundStyle(Theme.textPrimary)
                        Text(yandexLinked ? "Привязан" : "Не привязан")
                            .font(.caption2).foregroundStyle(yandexLinked ? Theme.success : Theme.textSecondary)
                    }
                    Spacer()
                    if yandexBusy {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Button(yandexLinked ? "Отвязать" : "Привязать") {
                            Task { yandexLinked ? await unlinkYandex() : await startLinkYandex() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(yandexLinked ? Theme.danger : Theme.accent)
                    }
                }
                if let yandexNote {
                    Text(yandexNote).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .task { await refreshYandex() }
        .sheet(item: $yandexLinkURL) { item in
            YandexLinkView(url: item.url) { result in
                switch result {
                case "linked": yandexNote = "Яндекс привязан — теперь им можно входить."
                case "taken":  yandexNote = "Этот Яндекс уже привязан к другому сотруднику."
                default:       yandexNote = "Привязать не получилось. Попробуйте ещё раз."
                }
                Task { await refreshYandex() }
            }
        }
    }

    @MainActor
    private func refreshYandex() async {
        guard let id = session.currentUser?.id, !AppConfig.useMockData else { return }
        yandexLinked = await YandexAccount.isLinked(workerId: id)
    }

    @MainActor
    private func startLinkYandex() async {
        yandexBusy = true
        yandexNote = nil
        defer { yandexBusy = false }
        do {
            yandexLinkURL = YandexLinkTarget(url: try await YandexAccount.linkURL())
        } catch {
            yandexNote = error.localizedDescription
        }
    }

    @MainActor
    private func unlinkYandex() async {
        guard let id = session.currentUser?.id else { return }
        yandexBusy = true
        defer { yandexBusy = false }
        do {
            try await YandexAccount.unlink(workerId: id)
            yandexLinked = false
            yandexNote = "Яндекс отвязан. Вход остаётся по логину и паролю."
        } catch {
            yandexNote = error.localizedDescription
        }
    }

    private var settingsCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                toggleRow("Уведомления", "bell.fill")
                Divider().opacity(0.3)
                toggleRow("Загрузка фото по Wi-Fi", "wifi")
            }
        }
    }

    private var signOutButton: some View {
        Button {
            Task { await session.signOut() }
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Выйти из аккаунта")
            }
            .font(Typography.button)
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity).frame(height: 54)
            .glass(cornerRadius: 27, elevated: false)
        }
        .buttonStyle(PressableStyle())
    }

    private func row(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).font(Typography.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Typography.callout.weight(.medium)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, Spacing.s)
    }

    private func toggleRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).font(Typography.callout).foregroundStyle(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: .constant(true)).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, Spacing.s)
    }
}
