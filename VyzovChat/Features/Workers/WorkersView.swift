import SwiftUI

/// Управление сотрудниками — только глобальный админ.
struct WorkersView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    @State private var workers: [User] = []
    @State private var query = ""
    @State private var editing: User?
    @State private var creating = false
    @State private var isLoading = true

    private var filtered: [User] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return workers }
        return workers.filter {
            $0.fullName.localizedCaseInsensitiveContains(q) || $0.login.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.xs) {
                            // Экрана статистики больше нет: эндпоинта
                            // /api/workers/{id}/stats на сервере не существует.
                            ForEach(filtered) { worker in
                                NavigationLink { UserProfileView(user: worker) } label: { row(worker) }
                                    .buttonStyle(PressableStyle())
                                    .contextMenu {
                                        Button { editing = worker } label: {
                                            Label("Редактировать", systemImage: "pencil")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Сотрудники")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Поиск по ФИО или логину")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "person.badge.plus") }
                }
            }
            .sheet(isPresented: $creating) {
                WorkerEditView(worker: nil) { Task { await load(force: true) } }
                    .environmentObject(session)
            }
            .sheet(item: $editing) { worker in
                WorkerEditView(worker: worker) { Task { await load(force: true) } }
                    .environmentObject(session)
            }
            .task { await load() }
            .refreshable { await load(force: true) }
        }
    }

    private func row(_ worker: User) -> some View {
        HStack(spacing: Spacing.s) {
            avatar(worker)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worker.fullName).font(Typography.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if worker.isAdmin {
                        Text("админ").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.16), in: Capsule())
                    }
                }
                Text([worker.login, worker.position].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
    }

    private func avatar(_ worker: User) -> some View {
        Group {
            if let url = worker.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Avatar(name: worker.fullName, size: 40, id: worker.id)
                }
                .frame(width: 40, height: 40).clipShape(Circle())
            } else {
                Avatar(name: worker.fullName, size: 40, id: worker.id)
            }
        }
    }

    private func load(force: Bool = false) async {
        if force { DirectoryCache.invalidate() }
        workers = await DirectoryCache.colleagues()
        isLoading = false
    }
}
