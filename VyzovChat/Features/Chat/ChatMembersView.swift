import SwiftUI

/// Список участников чата мероприятия. Тап по участнику открывает его профиль.
/// Добавлять участников может только админ чата.
struct ChatMembersView: View {
    let dealId: String
    let chatTitle: String
    var canManage: Bool = false

    @EnvironmentObject private var session: AppSession
    @ObservedObject private var realtime = RealtimeService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var members: [User] = []
    @State private var isLoading = true
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(members) { user in
                                NavigationLink { UserProfileView(user: user) } label: { row(user) }
                                    .buttonStyle(PressableStyle())
                                    .contextMenu {
                                        if canManage {
                                            Button {
                                                setRole(user, admin: user.eventRole != "admin")
                                            } label: {
                                                Label(user.eventRole == "admin" ? "Снять админа чата" : "Сделать админом чата",
                                                      systemImage: user.eventRole == "admin" ? "person.badge.minus" : "star.fill")
                                            }
                                            if user.id != session.currentUser?.id {
                                                Button(role: .destructive) {
                                                    remove(user)
                                                } label: {
                                                    Label("Удалить из мероприятия", systemImage: "person.badge.minus")
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(Spacing.m)
                    }
                }
            }
            .navigationTitle("Участники")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                if canManage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMemberView(dealId: dealId, existing: Set(members.map(\.id))) {
                    Task { await load() }
                }
                .environmentObject(session)
            }
            .task { await load() }
        }
    }

    private func load() async {
        members = await session.directory.members(dealId: dealId)
        isLoading = false
    }

    /// Назначить/снять админа чата (только глобальный админ).
    private func setRole(_ user: User, admin: Bool) {
        Task {
            try? await session.directory.setMemberRole(dealId: dealId, workerId: user.id,
                                                        role: admin ? "admin" : "member")
            Haptics.success()
            await load()
        }
    }

    /// Убрать участника из мероприятия (только глобальный админ).
    private func remove(_ user: User) {
        Task {
            try? await session.directory.removeMember(dealId: dealId, workerId: user.id)
            Haptics.success()
            await load()
        }
    }

    private func row(_ user: User) -> some View {
        let online = realtime.isOnline(user.id)
        return HStack(spacing: Spacing.s) {
            ZStack(alignment: .bottomTrailing) {
                avatar(user)
                OnlineDot(isOnline: online, size: 12).offset(x: 1, y: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.fullName).font(Typography.callout.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(user.position.isEmpty
                     ? Presence.text(isOnline: online, lastSeen: realtime.lastSeen(for: user.id) ?? user.lastSeen)
                     : user.position)
                    .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
    }

    private func avatar(_ user: User) -> some View {
        Group {
            if let url = user.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Avatar(name: user.fullName, size: 44, id: user.id)
                }
                .frame(width: 44, height: 44).clipShape(Circle())
            } else {
                Avatar(name: user.fullName, size: 44, id: user.id)
            }
        }
    }
}

/// Добавление участника в мероприятие (админ чата).
private struct AddMemberView: View {
    let dealId: String
    let existing: Set<String>
    let onAdded: () -> Void

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var workers: [User] = []
    @State private var query = ""
    @State private var busyId: String?
    @State private var errorText: String?

    private var candidates: [User] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return workers
            .filter { !existing.contains($0.id) }
            .filter { q.isEmpty || $0.fullName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(spacing: Spacing.xs) {
                        if let errorText { ErrorBanner(text: errorText) }
                        ForEach(candidates) { worker in
                            Button { add(worker) } label: {
                                HStack(spacing: Spacing.s) {
                                    Avatar(name: worker.fullName, size: 40, id: worker.id)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(worker.fullName).font(Typography.callout)
                                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                                        if !worker.position.isEmpty {
                                            Text(worker.position).font(.caption2).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    if busyId == worker.id {
                                        ProgressView().tint(Theme.accent)
                                    } else {
                                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(Spacing.s)
                                .glass(cornerRadius: Theme.cornerSmall, elevated: false)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(Spacing.m)
                }
            }
            .navigationTitle("Добавить участника")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Поиск выездника")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } } }
            .task { workers = await DirectoryCache.colleagues() }
        }
    }

    private func add(_ worker: User) {
        busyId = worker.id
        errorText = nil
        Task {
            do {
                try await session.directory.addMember(dealId: dealId, workerId: worker.id, role: "member")
                Haptics.success()
                onAdded()
                dismiss()
            } catch {
                errorText = error.localizedDescription
                Haptics.warning()
            }
            busyId = nil
        }
    }
}
