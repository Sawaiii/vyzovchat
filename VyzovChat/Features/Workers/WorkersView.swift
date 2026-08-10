import SwiftUI

/// Управление сотрудниками — только глобальный админ.
struct WorkersView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics

    /// Кого показываем. Гости склада и подрядчики приходят по ссылке на одно
    /// мероприятие — в общем списке они мешают, поэтому у них своя вкладка.
    private enum Tab: String, CaseIterable, Identifiable {
        case staff = "Штат"
        case guests = "Гости"
        case archived = "Уволены"
        var id: String { rawValue }

        var scope: WorkersScope {
            switch self {
            case .staff:    return .staff
            case .guests:   return .guests
            case .archived: return .archived
            }
        }

        var emptyIcon: String {
            switch self {
            case .staff:    return "person.2"
            case .guests:   return "person.badge.clock"
            case .archived: return "archivebox"
            }
        }

        var emptyTitle: String {
            switch self {
            case .staff:    return "Сотрудников нет"
            case .guests:   return "Гостей нет"
            case .archived: return "Уволенных нет"
            }
        }

        var emptyMessage: String {
            switch self {
            case .staff:    return "Заведите сотрудника кнопкой в правом верхнем углу."
            case .guests:   return "Здесь появятся те, кто пришёл по ссылке: склад и подрядчики."
            case .archived: return "Уволенный не входит в систему, но его смены и переписка остаются."
            }
        }
    }

    @State private var tab: Tab = .staff
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
                VStack(spacing: Spacing.s) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, Spacing.s)

                    if isLoading {
                        Spacer()
                        ProgressView().tint(Theme.accent)
                        Spacer()
                    } else if filtered.isEmpty {
                        Spacer()
                        EmptyState(icon: tab.emptyIcon, title: tab.emptyTitle, message: tab.emptyMessage)
                        Spacer()
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
            .onChange(of: tab) { Task { await load(force: true) } }
        }
    }

    private func row(_ worker: User) -> some View {
        HStack(spacing: Spacing.s) {
            avatar(worker)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worker.fullName).font(Typography.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    // Плашка роли, а не «админ»: полные права теперь даёт именно
                    // роль, и «владельца» сервер переименовал в админа.
                    let role = SystemRole(worker.globalRole)
                    if role != .worker {
                        Text(role.title.lowercased()).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(role.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(role.color.opacity(0.16), in: Capsule())
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
        isLoading = workers.isEmpty
        // Кэш справочника общий и живёт под «всех, кроме гостей склада»,
        // а здесь список свой на каждую вкладку — спрашиваем сервер напрямую.
        workers = await session.directory.fetchWorkers(scope: tab.scope)
        isLoading = false
    }
}
