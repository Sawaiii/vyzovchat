import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @ObservedObject private var router = Router.shared
    @StateObject private var vm = ChatListViewModel()
    @State private var query = ""
    @State private var segment: Segment = .events
    @State private var openChat: Chat?
    @Namespace private var segmentPill

    enum Segment: String, CaseIterable, Identifiable {
        case events = "Мероприятия"
        case dms = "Личные"
        case archive = "Архив"
        var id: String { rawValue }
    }

    private func chats(for seg: Segment) -> [Chat] {
        switch seg {
        case .events: return vm.activeEventChats
        case .dms: return vm.dmChats
        case .archive: return vm.archivedEventChats
        }
    }

    private var allChats: [Chat] { vm.activeEventChats + vm.archivedEventChats + vm.dmChats }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchResults: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return allChats.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: Spacing.s) {
                    if !isSearching { segmentBar }

                    if vm.isLoading {
                        LoadingList(); Spacer()
                    } else if isSearching {
                        searchList
                    } else {
                        pager
                    }
                }
                .padding(.top, metrics.contentTopPadding)
            }
            .navigationTitle("Чаты")
            // Крупный заголовок съедал полсотни точек над списком: название
            // вкладки и так написано в полосе внизу. Отступ под панелью —
            // от устройства: у «островка» строка состояния и так выше.
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            // Внутри стека, а не снаружи: полоса вкладок должна уезжать вместе
            // с этим экраном, когда поверх него открывают чат.
            .appTabBar()
            .searchable(text: $query, prompt: "Поиск по названию")
            .navigationDestination(item: $openChat) { chat in
                ChatView(chat: chat, currentUserId: session.currentUser?.id ?? "")
                    .environmentObject(session)
            }
            .task { await vm.load(session: session) }
            .refreshable { await vm.load(session: session) }
            // Возврат из чата — снимаем счётчик прочитанного (дёшево, 1 запрос).
            .onAppear { Task { await vm.refreshUnread(session: session) } }
            .onChange(of: router.pendingChatId) { openPending() }
            // Живое обновление: новое/изменённое мероприятие, состав, аватары.
            .onReceive(RealtimeService.shared.eventsChanged) { _ in
                Task { await vm.load(session: session) }
            }
            .onReceive(RealtimeService.shared.workersChanged) { _ in
                Task { await vm.load(session: session) }
            }
            // Счётчики в реальном времени: прочитали — обнулился, пришло — вырос.
            .onReceive(RealtimeService.shared.localRead) { chatId in
                withAnimation(.smooth(duration: 0.2)) { vm.markChatRead(chatId) }
            }
            .onReceive(RealtimeService.shared.incoming) { message in
                withAnimation(.smooth(duration: 0.2)) { vm.applyIncoming(message) }
            }
            // (Пере)подключение сокета: за офлайн (сон/потеря сети) могли прийти
            // сообщения, которых список не видел — обновляем превью и счётчики.
            // dropFirst — только реальные переподключения (первую загрузку делает
            // .task), иначе на открытии список грузился бы дважды (мигание).
            .onReceive(RealtimeService.shared.$isConnected.removeDuplicates().dropFirst().filter { $0 }) { _ in
                Task { await vm.reloadAfterReconnect(session: session) }
            }
        }
    }

    /// Непрочитанные во вкладке — сумма по её чатам.
    private func unread(in seg: Segment) -> Int {
        chats(for: seg).reduce(0) { $0 + $1.unreadCount }
    }

    /// Свой сегмент-контрол: нативный не умеет бейджи.
    private var segmentBar: some View {
        HStack(spacing: 4) {
            ForEach(Segment.allCases) { seg in
                let isSelected = segment == seg
                let count = unread(in: seg)
                Button {
                    withAnimation(.smooth(duration: 0.25)) { segment = seg }
                } label: {
                    HStack(spacing: 5) {
                        Text(seg.rawValue)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if count > 0 {
                            UnreadBadge(count: count,
                                        background: isSelected ? Color.white.opacity(0.3) : Theme.accent)
                        }
                    }
                    .foregroundStyle(isSelected ? Theme.textOnAccent : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    // Синяя капсула «перетекает» между вкладками, а не перерисовывается.
                    .background {
                        if isSelected {
                            Capsule().fill(Theme.accent)
                                .matchedGeometryEffect(id: "segmentPill", in: segmentPill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.panel2, in: Capsule())
        .padding(.horizontal, metrics.horizontalPadding)
    }

    /// Интерактивный пейджер: видно соседнюю вкладку при перетаскивании, снап к ближайшей.
    private var pager: some View {
        TabView(selection: $segment.animation(.smooth(duration: 0.25))) {
            ForEach(Segment.allCases) { seg in
                chatColumn(for: seg).tag(seg)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func chatColumn(for seg: Segment) -> some View {
        let list = chats(for: seg)
        if list.isEmpty {
            VStack {
                Spacer()
                EmptyState(icon: emptyIcon(seg), title: emptyTitle(seg), message: emptyMessage(seg))
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(list) { chat in chatLink(chat) }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private var searchList: some View {
        Group {
            if searchResults.isEmpty {
                VStack {
                    Spacer()
                    EmptyState(icon: "magnifyingglass", title: "Ничего не найдено",
                               message: "Нет чатов с таким названием (искали во всех вкладках, включая архив).")
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(searchResults) { chat in chatLink(chat) }
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.xl)
                }
            }
        }
    }

    private func chatLink(_ chat: Chat) -> some View {
        NavigationLink {
            ChatView(chat: chat, currentUserId: session.currentUser?.id ?? "")
                .environmentObject(session)
        } label: {
            ChatRow(chat: chat)
        }
        .buttonStyle(PressableStyle())
    }

    private func openPending() {
        guard let id = router.pendingChatId else { return }
        router.pendingChatId = nil
        Task {
            if allChats.isEmpty { await vm.load(session: session) }
            if let chat = allChats.first(where: { $0.id == id }) { openChat = chat }
        }
    }

    private func emptyIcon(_ s: Segment) -> String {
        switch s { case .events: return "bubble.left.and.bubble.right"; case .dms: return "person.2"; case .archive: return "archivebox" }
    }
    private func emptyTitle(_ s: Segment) -> String {
        switch s { case .events: return "Нет чатов мероприятий"; case .dms: return "Нет личных чатов"; case .archive: return "Архив пуст" }
    }
    private func emptyMessage(_ s: Segment) -> String {
        switch s {
        case .events: return "Чаты создаются автоматически, когда заказ переходит на нужный этап."
        case .dms: return "Личная переписка появится здесь."
        case .archive: return "Сюда попадают чаты прошедших мероприятий."
        }
    }
}

/// Строка чата (мероприятие или ЛС).
struct ChatRow: View {
    let chat: Chat
    @State private var muted = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chat.title)
                        .font(Typography.headline)
                        .foregroundStyle(chat.isDirect ? Theme.textPrimary : Theme.groupTitle)
                        .lineLimit(1)
                    if muted {
                        Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let date = chat.lastMessageDate {
                        Text(RelativeDate.short(date)).font(Typography.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                if !chat.isDirect && !chat.isSystem {
                    HStack(spacing: 5) {
                        if let company = chat.company { CompanyBadge(name: company) }
                        // Своя роль в мероприятии: старший и кладовщик отвечают
                        // за этапы, и знать об этом надо ещё до входа в чат.
                        if let role = chat.myRoleChip { RoleChip(role: role) }
                        StatusBadgesRow(badges: chat.statusBadges, compact: true)
                    }
                }

                HStack {
                    // «Вы: » рисуем здесь, а не подмешиваем в текст: по тексту
                    // список сверяет, то же это сообщение или новое.
                    Text(preview)
                        .font(Typography.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Spacer()
                    // Упоминание и ответ — отдельными значками: их ждут адресно
                    // и среди обычных непрочитанных они бы потерялись.
                    if chat.hasMention {
                        Image(systemName: "at.circle.fill")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                    if chat.hasReply {
                        Image(systemName: "arrowshape.turn.up.left.circle.fill")
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                    if chat.unreadCount > 0 {
                        UnreadBadge(count: chat.unreadCount, compact: false)
                    }
                }
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerMedium)
        .contentShape(Rectangle())
        .onAppear { muted = MuteStore.isMuted(chat.id) }
        .contextMenu {
            Button {
                // У мероприятия «без звука» хранится на сервере: иначе выключил
                // с телефона, а с компьютера всё равно звенит.
                Task { muted = await MuteStore.toggle(chat.id) }
            } label: {
                Label(muted ? "Включить звук" : "Без звука",
                      systemImage: muted ? "bell.fill" : "bell.slash.fill")
            }
        }
    }

    /// Текст последнего сообщения. В личной переписке своё помечаем «Вы: » —
    /// иначе на двоих не понять, ждёт ли собеседник ответа или последнее слово
    /// осталось за тобой. В общем чате отправитель и так виден по превью.
    private var preview: String {
        guard let text = chat.lastMessagePreview, !text.isEmpty else { return "Нет сообщений" }
        return chat.isDirect && chat.lastMessageIsMine ? "Вы: \(text)" : text
    }

    private var avatar: some View {
        Group {
            if chat.isSystem {
                // Служебный чат — не мероприятие: буквенный кружок с именем
                // «Жалобы» читался бы как чья-то переписка.
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.title3).foregroundStyle(Theme.warning)
                    .frame(width: 52, height: 52)
                    .background(Theme.warning.opacity(0.16), in: Circle())
            } else if let url = chat.avatarURL {
                CachedAsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Avatar(name: chat.title, size: 52, id: chat.id)
                }
                .frame(width: 52, height: 52).clipShape(Circle())
            } else {
                Avatar(name: chat.title, size: 52, id: chat.id)
            }
        }
    }
}
