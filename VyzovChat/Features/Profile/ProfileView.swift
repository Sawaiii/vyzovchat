import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @State private var avatarPick: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var showWorkers = false

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
