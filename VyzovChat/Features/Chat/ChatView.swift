import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var realtime = RealtimeService.shared
    @StateObject private var model: ChatViewModel
    @State private var showPhotoReport = false
    @State private var showMembers = false
    @State private var showEditEvent = false
    @State private var showShifts = false
    @State private var showEventInfo = false
    @State private var showGallery = false
    @State private var showCreateTopic = false
    @State private var editingTopic: TopicDTO?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var mediaPreview: MediaPreview?
    @State private var profileUser: User?
    @State private var scrollTarget: String?
    @State private var highlightedId: String?
    @State private var forwardingMessage: Message?
    @State private var didInitialScroll = false
    @State private var menuMessage: Message?
    // Кадр выбранного сообщения в системе координат чата — чтобы меню всплывало
    // почти там же, где сообщение было, а не по центру экрана (как в телеграме).
    @State private var menuFrame: CGRect = .zero
    @State private var menuFrameId: String?
    // Пружинный «пульс» поднятой копии при вызове меню (как в телеграме).
    @State private var menuPop = false
    @State private var isAtBottom = true
    @State private var showScrollDown = false
    /// Палец сейчас на микрофоне. Отдельно от «идёт запись»: запись стартует
    /// асинхронно, а кнопка должна реагировать сразу.
    @State private var isPressingMic = false
    /// Насколько кнопка записи уехала за пальцем.
    @State private var micDrag: CGSize = .zero
    /// Палец дошёл до замка — подсвечиваем цель, чтобы было видно, что дальше
    /// вести не надо.
    @State private var lockArmed = false

    init(chat: Chat, currentUserId: String = MockData.currentUser.id) {
        _model = StateObject(wrappedValue: ChatViewModel(
            chat: chat, service: Backend.chat(), currentUserId: currentUserId))
    }

    private var uploadErrorBinding: Binding<Bool> {
        Binding(get: { model.uploadError != nil },
                set: { if !$0 { model.uploadError = nil } })
    }

    /// Дата и время мероприятия в шапке чата.
    ///
    /// Пока начало ещё не наступило, время подписано как «приезд» и выделено:
    /// выезднику важнее всего, к какому часу быть на месте. После начала —
    /// обычный интервал «с … до …».
    @ViewBuilder
    private var eventTimeLine: some View {
        if let start = model.chat.startsAt {
            let upcoming = start > Date()
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 10))
                Text(Self.dayFormatter.string(from: start))
                Text("·")
                if upcoming {
                    Text("приезд \(Self.timeFormatter.string(from: start))")
                        .foregroundStyle(Theme.accent)
                } else if let end = model.chat.endsAt {
                    Text("\(Self.timeFormatter.string(from: start)) — \(Self.timeFormatter.string(from: end))")
                } else {
                    Text("с \(Self.timeFormatter.string(from: start))")
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var myFio: String? { session.currentUser?.fio }
    private var isAdmin: Bool { session.currentUser?.isAdmin ?? false }

    var body: some View {
        ZStack {
            chatBackground
            VStack(spacing: 0) {
                if !model.chat.isDirect {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let company = model.chat.company {
                                CompanyBadge(name: company, compact: false)
                            }
                            StatusBadgesRow(badges: model.chat.statusBadges)
                        }
                        eventTimeLine
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, 6)
                        .background(Theme.panel.opacity(0.6))

                    TopicBar(
                        topics: model.topics,
                        selected: model.selectedTopicId,
                        canManage: model.isChatAdmin,
                        unread: { model.unreadCount(for: $0) },
                        onSelect: { id in Task { await model.selectTopic(id) } },
                        onCreate: { showCreateTopic = true },
                        onEditAccess: { topic in editingTopic = topic },
                        onDelete: { topic in Task { await model.deleteTopic(topic.id) } }
                    )
                }

                if model.chat.isDirect || model.topics.isEmpty {
                    messagesScroll
                } else {
                    topicPager
                }

                if !model.mentionSuggestions.isEmpty { mentionBar }
                if let editing = model.editingMessage { editBar(editing) }
                else if let reply = model.replyingTo { replyBar(reply) }
                inputBar
            }
            // Пока держим меню — чат уходит на задний план: размывается, на виду
            // остаётся только выбранное сообщение. ТОЛЬКО blur (рендер-фильтр, не
            // трогает лейаут/скролл). scaleEffect убран: уменьшение ленты к центру
            // сдвигало нижние сообщения вверх и «переякоривало» прижатую к низу
            // ленту — в ЛС при вызове меню на последних сообщениях чат съезжал, а
            // после закрытия приходилось листать обратно. Глубину даёт затемнение
            // из messageMenu. Без .animation(value:) — анимируем через withAnimation.
            .blur(radius: menuMessage != nil ? 8 : 0)

            if let msg = menuMessage { messageMenu(msg) }
        }
        .coordinateSpace(name: Self.chatSpace)
        .navigationTitle(model.chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Поиск в чате")
        .toolbar {
            if model.chat.isDirect {
                ToolbarItem(placement: .principal) {
                    DMHeaderView(title: model.chat.title,
                                 avatarURL: model.chat.avatarURL,
                                 otherId: model.chat.otherUserId,
                                 onTap: openOtherProfile)
                }
            }
            // Одно меню вместо россыпи кнопок: их набралось до шести, система
            // прятала лишние в своё переполнение — то самое «троеточие, которое
            // ничего не делает». Заодно совпадает с бургером в веб-версии.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showGallery = true } label: { Label("Медиа чата", systemImage: "photo.stack") }
                    if !model.chat.isDirect {
                        // Смена — основное действие выездника, держим первым.
                        Button { showShifts = true } label: { Label("Смены", systemImage: "clock.badge.checkmark") }
                        Button { showEventInfo = true } label: { Label("О мероприятии", systemImage: "info.circle") }
                        Button { showMembers = true } label: { Label("Участники", systemImage: "person.2.fill") }
                        // Отчёт — только админ чата и пока мероприятие не завершено.
                        if model.isChatAdmin && model.chat.isPhotoReportOpen {
                            Button { showPhotoReport = true } label: {
                                Label("Отчёт", systemImage: "camera.badge.ellipsis")
                            }
                        }
                        // Параметры мероприятия меняет только глобальный админ.
                        if isAdmin {
                            Divider()
                            Button { showEditEvent = true } label: {
                                Label("Изменить мероприятие", systemImage: "square.and.pencil")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // Неудачная отправка вложения должна быть видна: раньше снимок просто
        // исчезал, и человек считал, что отправил его.
        .alert("Вложение не отправлено", isPresented: uploadErrorBinding) {
            Button("Понятно", role: .cancel) { model.uploadError = nil }
        } message: {
            Text(model.uploadError ?? "")
        }
        .sheet(isPresented: $showEventInfo) {
            EventInfoView(dealId: model.chat.dealId,
                          eventTitle: model.chat.title,
                          isChatAdmin: model.isChatAdmin,
                          canInvite: model.canInvite,
                          claimTopicId: model.claimTopicId)
                .environmentObject(session)
        }
        .sheet(isPresented: $showShifts) {
            EventShiftsView(dealId: model.chat.dealId,
                            eventTitle: model.chat.title,
                            isChatAdmin: model.isChatAdmin)
                .environmentObject(session)
        }
        .sheet(isPresented: $showMembers) {
            // Управление участниками — только глобальный админ.
            ChatMembersView(dealId: model.chat.dealId, chatTitle: model.chat.title,
                            canManage: isAdmin)
                .environmentObject(session)
        }
        .sheet(isPresented: $showGallery) {
            ChatGalleryView(items: model.mediaAttachments)
        }
        // Тему заводим не через алерт: у неё есть приватность (кому видна),
        // а её в одном текстовом поле не задать.
        .sheet(isPresented: $showCreateTopic) {
            TopicAccessView(topic: nil, dealId: model.chat.dealId, members: model.members) {
                Task { await model.reloadTopics() }
            }
            .environmentObject(session)
        }
        .sheet(item: $editingTopic) { topic in
            TopicAccessView(topic: topic, dealId: model.chat.dealId, members: model.members) {
                Task { await model.reloadTopics() }
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $showEditEvent) {
            EditEventView(dealId: model.chat.dealId)
                .environmentObject(session)
        }
        .sheet(item: $forwardingMessage) { msg in
            ForwardPickerView { target in
                Task { await model.forward(msg, to: target) }
                forwardingMessage = nil
            }
            .environmentObject(session)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems,
                      maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
        .onChange(of: pickerItems) { handlePickedMedia() }
        .sheet(isPresented: $showPhotoReport) {
            ReportView(model: model)
        }
        .fullScreenCover(item: $mediaPreview) { preview in
            MediaPager(items: preview.items, startIndex: preview.index)
        }
        .navigationDestination(item: $profileUser) { u in
            UserProfileView(user: u, sharedAttachments: sharedAttachments(for: u))
        }
        .task { await model.load() }
        .onAppear {
            model.setActive(true)
            NotificationsManager.shared.clearDelivered()
        }
        .onDisappear { model.setActive(false) }
    }

    /// Фон чата: цвет-обои мероприятия с дудл-паттерном — как в веб-версии.
    private var chatBackground: some View {
        ChatWallpaper(colorHex: model.chat.colorHex)
    }

    private func openOtherProfile() {
        guard let id = model.chat.otherUserId else { return }
        profileUser = model.user(for: id)
    }

    private func sharedAttachments(for user: User) -> [Message.Attachment] {
        (model.chat.isDirect && user.id == model.chat.otherUserId) ? model.allAttachments : []
    }


    // MARK: - Вложения (видео/файлы)

    private func handlePickedMedia() {
        let items = pickerItems
        pickerItems = []
        guard !items.isEmpty else { return }
        Task {
            var images: [UIImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                if let ui = UIImage(data: data) {
                    images.append(ui)
                } else {
                    await model.sendMediaData(data, fileName: "VIDEO.mov")
                }
            }
            if !images.isEmpty { await model.sendImages(images) }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task {
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                // Тип содержимого сервер определяет сам по расширению имени и
                // присланному клиентом не доверяет — угадывать его здесь незачем.
                let name = url.lastPathComponent
                if access { url.stopAccessingSecurityScopedResource() }
                if let data { await model.sendMediaData(data, fileName: name) }
            }
        }
    }

    // MARK: - Лента

    /// Свайпы между темами с перелистыванием экрана — как во вкладках чатов.
    /// Все страницы устроены одинаково: иначе живая лента «перепрыгивала» с одной
    /// страницы на другую прямо во время жеста, и свайп замирал между темами.
    private var topicPager: some View {
        TabView(selection: topicSelection) {
            ForEach(model.topicPages, id: \.self) { topicId in
                feed(for: topicId).tag(topicId)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var topicSelection: Binding<Int?> {
        Binding(
            get: { model.selectedTopicId },
            set: { id in
                guard id != model.selectedTopicId else { return }
                let target = oneStep(toward: id)
                // Без withAnimation: анимировать выбор поверх интерактивного
                // жеста — значит драться с самим жестом. Капсулу анимирует TopicBar.
                model.selectedTopicId = target
                Task { await model.selectTopic(target) }
            }
        )
    }

    /// Один свайп — одна тема: резкий флик через весь экран иначе перекидывает
    /// сразу через несколько страниц. Тап по чипу в TopicBar идёт мимо пейджера,
    /// поэтому им по-прежнему можно прыгнуть на любую тему.
    private func oneStep(toward id: Int?) -> Int? {
        let pages = model.topicPages
        guard let from = pages.firstIndex(of: model.selectedTopicId),
              let to = pages.firstIndex(of: id), abs(to - from) > 1 else { return id }
        return pages[from + (to > from ? 1 : -1)]
    }

    /// Лента чата. Для ЛС и чата без тем — единственная; в пейджере тем такой же
    /// вью показывается на каждой странице (активная берёт живые сообщения,
    /// соседние — префетч), поэтому структура страниц не меняется на лету.
    private var messagesScroll: some View { feed(for: model.selectedTopicId) }

    private func feed(for topicId: Int?) -> some View {
        let isActive = topicId == model.loadedTopicId
        let loading = isActive ? model.isLoading : !model.isTopicLoaded(topicId)
        // Готовую ленту берём из модели: она пересобирается только при изменении
        // сообщений/поиска, а не на каждом рендере/нажатии клавиши (было — во вью).
        let items = isActive ? model.activeFeed : model.staticFeed(for: topicId)

        return ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(items) { item in
                            switch item {
                            case .separator(let title, _):
                                DaySeparator(title: title)
                            case .uploading(let pending):
                                UploadingTile(pending: pending)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            case .message(let message, let showRead):
                                if model.search.isEmpty {
                                    bubble(for: message, showRead: showRead)
                                } else {
                                    // В режиме поиска сообщение — это ссылка: по нажатию
                                    // подгружаем окно ленты вокруг него и открываем там.
                                    // Найденное может быть и в другой теме, и вне
                                    // последней сотни — иначе перейти к нему некуда.
                                    Button {
                                        UIApplication.shared.endEditing()
                                        Task { await model.openFound(message) }
                                    } label: {
                                        bubble(for: message, showRead: showRead)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Якорь конца ленты — к нему прыгаем по кнопке.
                        Color.clear.frame(height: 1).id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.s)
                }
                // Лента прижата к низу: чат открывается в конце, а не «где-то».
                .defaultScrollAnchor(.bottom)
                // Заглушки — по центру экрана: внутри прижатой к низу ленты
                // они уезжали вниз.
                .overlay {
                    if loading {
                        ProgressView().tint(Theme.accent)
                    } else if items.isEmpty {
                        emptyState
                    }
                }
                .modifier(BottomTracking { if isActive { updateAtBottom($0) } })
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { UIApplication.shared.endEditing() })
                .onChange(of: model.messages.count) {
                    guard isActive else { return }
                    if !didInitialScroll {
                        didInitialScroll = true
                        // Есть непрочитанные — встаём там, где они начинаются;
                        // иначе строго в конце ленты.
                        settle(proxy, to: model.initialAnchorId ?? Self.bottomAnchor)
                    } else if let last = model.messages.last {
                        withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                // Стали активной темой — её лента открывается с конца.
                .onChange(of: isActive) { if isActive { settleAtBottom(proxy) } }
                // Переход из поиска: окно ленты уже загружено, осталось встать
                // на найденном сообщении и подсветить его.
                .onChange(of: model.jumpToMessageId) {
                    guard isActive, let target = model.jumpToMessageId else { return }
                    scrollTarget = target
                    model.jumpToMessageId = nil
                }
                .onChange(of: scrollTarget) {
                    if isActive, let target = scrollTarget {
                        withAnimation(.smooth) { proxy.scrollTo(target, anchor: .center) }
                        highlightedId = target
                        scrollTarget = nil
                        Task {
                            try? await Task.sleep(for: .milliseconds(1300))
                            withAnimation { highlightedId = nil }
                        }
                    }
                }

                // Только на активной странице: на соседних кнопка не нужна.
                scrollDownButton(proxy).opacity(isActive ? 1 : 0)
            }
        }
    }

    static let bottomAnchor = "chat-bottom-anchor"

    private func settleAtBottom(_ proxy: ScrollViewProxy) { settle(proxy, to: Self.bottomAnchor) }

    /// Доводчик: в ленивом списке первый переход часто не доезжает,
    /// пока нижние ячейки ещё не построены, поэтому повторяем.
    private func settle(_ proxy: ScrollViewProxy, to id: String) {
        proxy.scrollTo(id, anchor: id == Self.bottomAnchor ? .bottom : .top)
        Task {
            for delay in [50, 150, 350] {
                try? await Task.sleep(for: .milliseconds(delay))
                proxy.scrollTo(id, anchor: id == Self.bottomAnchor ? .bottom : .top)
            }
        }
    }


    /// Кнопка «в конец диалога». Видна, только когда пользователь листает вниз
    /// и ещё не достиг конца.
    private func scrollDownButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            jumpToBottom(proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .glass(cornerRadius: 20)
        }
        .padding(.trailing, Spacing.m)
        .padding(.bottom, Spacing.s)
        .opacity(showScrollDown ? 1 : 0)
        .allowsHitTesting(showScrollDown)
        .animation(.smooth(duration: 0.2), value: showScrollDown)
    }

    /// Прыжок в самый конец. Повторяем через мгновение: в ленивом списке первый
    /// scrollTo часто доезжает не до конца, пока нижние ячейки ещё не построены.
    private func jumpToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        }
    }

    /// Видимость последнего сообщения = «мы внизу». Отслеживаем по реальной
    /// вью пузыря: у неё есть высота, поэтому onAppear/onDisappear в ленивом
    /// списке отрабатывают надёжно (в отличие от невидимого якоря).
    private func updateAtBottom(_ atBottom: Bool) {
        isAtBottom = atBottom
        withAnimation(.smooth(duration: 0.2)) { showScrollDown = !atBottom }
    }

    /// Масштаб «попа» для пузыря, который держат: вдавлен (0.9), пока пружина не
    /// вернёт его к 1.0. На остальных — 1.0.
    private func pressScale(_ message: Message) -> CGFloat {
        guard menuMessage?.id == message.id else { return 1 }
        return menuPop ? 1 : 0.9
    }

    private func bubble(for message: Message, showRead: Bool = true) -> some View {
        MessageBubble(
            message: message,
            isMine: model.isMine(message),
            sender: model.sender(message),
            replyToMe: message.replyToId != nil && message.replySender != nil && message.replySender == myFio,
            canDelete: model.isMine(message) || isAdmin,
            canEdit: model.isMine(message) && (message.text?.isEmpty == false),
            isDM: model.chat.isDirect,
            readState: showRead ? readState(for: message) : .none,
            readAt: model.partnerReadAt,
            groupRead: showRead ? model.groupReadInfo(for: message) : nil,
            highlighted: highlightedId == message.id,
            onLongPress: {
                // «Поп» на САМОМ пузыре в чате (не на копии в меню): пузырь чуть
                // вдавливается и упруго возвращается. Пузырь всегда отрисован,
                // поэтому срабатывает с первого раза (у копии в меню была задержка
                // из-за асинхронного замера кадра — оттого «поп» шёл со второго раза).
                menuPop = false
                withAnimation(.smooth(duration: 0.16)) { menuMessage = message }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.12)) { menuPop = true }
            },
            onReact: { emoji in model.toggleReaction(message, emoji: emoji) },
            onOpenProfile: { id in profileUser = model.user(for: id) },
            onOpenMedia: { att in openMedia(att) },
            onOpenReply: { rid in scrollTarget = rid }
        )
        .scaleEffect(pressScale(message), anchor: model.isMine(message) ? .trailing : .leading)
        .background(
            // Запоминаем положение пузыря в момент вызова меню — по нему потом
            // раскладываем всплывающее меню рядом с сообщением.
            GeometryReader { geo in
                Color.clear.onChange(of: menuMessage?.id) { _, newId in
                    if newId == message.id {
                        menuFrame = geo.frame(in: .named(Self.chatSpace))
                        menuFrameId = message.id
                    }
                }
            }
        )
        .id(message.id)
    }

    static let chatSpace = "chatSpace"

    /// Статус своего сообщения в ЛС: отправлено / доставлено (собеседник в сети) / прочитано.
    private func readState(for message: Message) -> MessageBubble.ReadState {
        guard model.chat.isDirect, model.isMine(message) else { return .none }
        let id = Int(message.id) ?? 0
        if id > 0 && id <= model.partnerReadUpTo { return .read }
        if let other = model.chat.otherUserId, realtime.isOnline(other) { return .delivered }
        return .sent
    }

    // MARK: - Меню сообщения (реакции сразу видны, как в телеграме)

    private static let quickEmojis = ["👍", "❤️", "🔥", "😂", "💩", "✅"]

    private func messageMenu(_ msg: Message) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { closeMenu() }

                // Раскладываем, только когда известен кадр сообщения — иначе
                // на один кадр меню мигнуло бы в углу.
                if menuFrameId == msg.id {
                    let l = menuLayout(for: msg, in: geo)
                    let mine = model.isMine(msg)
                    let W = geo.size.width

                    reactionsBar(msg)
                        .position(x: menuBlockX(width: Self.reactionsBarWidth, isMine: mine, containerW: W), y: l.reactionsMidY)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))

                    // Копия сообщения. Медиа показываем ТОЛЬКО как само фото/видео по
                    // ЦЕНТРУ экрана (без аватара и распорок пузыря) и масштабируем от
                    // центра — иначе копия наследует выравнивание ряда: своё фото в ЛС
                    // прижималось к правому краю и «съезжало» вбок. Текст оставляем на
                    // прежнем месте у своей стенки. Фрейм фиксируем жёстко (ширину и
                    // высоту), чтобы медиа не перерендеривалось и высота не разъезжалась
                    // с расчётом меню.
                    if isMediaMessage(msg) {
                        liftedMedia(msg)
                            .frame(width: 240, height: l.naturalH)
                            .scaleEffect(l.scale, anchor: .center)
                            .position(x: W / 2, y: l.msgMidY)
                    } else {
                        liftedMessage(msg)
                            .frame(width: menuFrame.width, height: l.naturalH)
                            .scaleEffect(l.scale, anchor: mine ? .trailing : .leading)
                            .position(x: menuFrame.midX, y: l.msgMidY)
                    }

                    if let status = statusLine(for: msg) {
                        statusChip(status)
                            .position(x: min(max(menuFrame.midX, 110), W - 110), y: l.statusMidY)
                            .transition(.opacity)
                    }

                    actionsMenu(msg)
                        .position(x: menuBlockX(width: 250, isMine: mine, containerW: W), y: l.actionsMidY)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .transition(.opacity)
    }

    /// Геометрия всплывающего меню: держим сообщение как можно ближе к тому месту,
    /// где оно было, но так, чтобы реакции сверху и действия снизу поместились.
    private struct MenuLayout {
        var scale: CGFloat        // во сколько раз показать копию сообщения
        var naturalH: CGFloat     // высота копии до масштаба (для жёсткого фрейма)
        var messageH: CGFloat     // её высота на экране (уже с учётом scale)
        var msgMidY: CGFloat
        var reactionsMidY: CGFloat
        var statusMidY: CGFloat
        var actionsMidY: CGFloat
    }

    /// Высота МЕДИА-части сообщения по реальному аспекту загруженной картинки, а не
    /// по замеру пузыря (menuFrame): в пейджере тем (чаты мероприятий) замер кадра
    /// мог давать завышенную высоту, из-за чего масштаб падал и фото выводилось
    /// мелким. Ширина медиа в чате — 240. Только для «чистого» медиа (как рисует
    /// mediaOnlyBubble); при тексте/цитате высоту заменять нельзя.
    private func mediaNaturalHeight(for msg: Message) -> CGFloat? {
        // Меню для любого сообщения с фото показывает ТОЛЬКО медиа (liftedMedia),
        // поэтому высоту считаем по медиа независимо от подписи/ответа/пересылки —
        // иначе для фото с подписью высота падала в догадку 320 и горизонтальное
        // фото обрезалось под портрет.
        let media = msg.attachments.filter { $0.isImage || $0.isVideo }
        guard !media.isEmpty else { return nil }
        if media.count > 1 {
            // Альбом: та же телеграм-мозаика, что и в чате, и с тем же пределом
            // плиток — иначе расчёт высоты расходился бы с тем, что реально рисуем.
            let shown = Array(media.prefix(MessageBubble.albumMaxTiles))
            let aspects = shown.map { MessageBubble.aspect($0) }
            return AlbumMosaicLayout.frames(aspects: aspects, count: shown.count, width: 240).size.height
        }
        let att = media[0]
        if att.isVideo { return 150 }   // videoTile — фиксированные 240×150
        // Размеры из БД — точная высота сразу (совпадает с чатом, см. imageTile).
        let a = MessageBubble.aspect(att)
        if a > 0 { return min(240 / a, 2000) }
        if let url = att.remoteURL,
           let img = ImageMemoryCache.thumbnails.object(forKey: ImageMemoryCache.key(url)),
           img.size.width > 0 {
            return min(240 * img.size.height / img.size.width, 2000)
        }
        return 240 * 4.0 / 3.0   // кэш не прогрет — считаем 4:3, но НЕ берём кривой menuFrame
    }

    private func menuLayout(for msg: Message, in geo: GeometryProxy) -> MenuLayout {
        let gap: CGFloat = 4            // внутренний зазор (статус ↔ действия)
        let edgeGap: CGFloat = 4        // отступ сообщения от реакций и действий
        let reactionsH: CGFloat = 44
        let hasStatus = statusLine(for: msg) != nil
        let statusH: CGFloat = hasStatus ? 26 : 0
        let actionsH = CGFloat(actionCount(for: msg)) * 44

        // geo здесь — уже безопасная область контента (под шапкой/поиском, над
        // таб-баром), поэтому НЕ вычитаем safeAreaInsets повторно: раньше это
        // сжимало площадь под фото почти вдвое, и фото/сетка выходили мелкими
        // (мельче, чем в самом чате). Небольшие поля от краёв.
        let topSafe: CGFloat = 8
        let bottomSafe = geo.size.height - 8

        // Для медиа — «растянутая» раскладка: сначала считаем размер фото, потом
        // ВЕСЬ кластер (реакции + фото + статус + действия) центрируем по вертикали
        // с одинаковыми зазорами. Иначе реакции/действия прибиты к краям экрана и
        // короткое горизонтальное фото висит с огромными полями сверху/снизу, а
        // высокое вертикальное липнет к реакциям.
        if isMediaMessage(msg) {
            let naturalH = mediaNaturalHeight(for: msg) ?? 320
            let sideMargin: CGFloat = 20   // поля фото от краёв экрана по бокам
            let mediaGap: CGFloat = 14     // воздух между фото и реакциями/действиями

            // Масштаб: вписываем фото в доступную область по ширине и высоте, не
            // мельче 0.5× и не крупнее 2.4×.
            let chromeH = reactionsH + mediaGap * 2 + (hasStatus ? statusH + gap : 0) + actionsH
            let availH = max(160, bottomSafe - topSafe - chromeH)
            let fitByWidth = (geo.size.width - sideMargin * 2) / 240
            let scale = max(0.5, min(availH / naturalH, fitByWidth, 2.4))
            let messageH = naturalH * scale

            // Центрируем кластер целиком, с одинаковым воздухом вокруг фото.
            let clusterH = reactionsH + mediaGap + messageH + mediaGap
                         + (hasStatus ? statusH + gap : 0) + actionsH
            let clusterTop = max(topSafe, topSafe + (bottomSafe - topSafe - clusterH) / 2)

            let msgTop = clusterTop + reactionsH + mediaGap
            let belowPhoto = msgTop + messageH + mediaGap
            let actionsTop = belowPhoto + (hasStatus ? statusH + gap : 0)
            return MenuLayout(
                scale: scale,
                naturalH: naturalH,
                messageH: messageH,
                msgMidY: msgTop + messageH / 2,
                reactionsMidY: clusterTop + reactionsH / 2,
                statusMidY: belowPhoto + statusH / 2,
                actionsMidY: actionsTop + actionsH / 2
            )
        }

        // Текст — компактная раскладка возле исходного места сообщения.
        let aboveChrome = reactionsH + edgeGap
        let belowChrome = edgeGap + (hasStatus ? statusH + gap : 0) + actionsH
        let available = max(80, bottomSafe - topSafe - aboveChrome - belowChrome)
        let naturalH = max(menuFrame.height, 40)
        let scale = min(1.05, available / naturalH)   // текст не увеличиваем
        let messageH = naturalH * scale

        let msgTopMin = topSafe + aboveChrome
        let msgTopMax = bottomSafe - belowChrome - messageH
        let msgTop = min(max(menuFrame.minY, msgTopMin), max(msgTopMin, msgTopMax))

        let statusTop = msgTop + messageH + edgeGap
        return MenuLayout(
            scale: scale,
            naturalH: naturalH,
            messageH: messageH,
            msgMidY: msgTop + messageH / 2,
            reactionsMidY: msgTop - edgeGap - reactionsH / 2,
            statusMidY: statusTop + statusH / 2,
            actionsMidY: statusTop + (hasStatus ? statusH + gap : 0) + actionsH / 2
        )
    }

    /// Сообщение содержит фото/видео — для него «растянутая» раскладка меню с
    /// крупным фото (см. menuLayout).
    private func isMediaMessage(_ msg: Message) -> Bool {
        msg.attachments.contains { $0.isImage || $0.isVideo }
    }

    /// Сколько строк действий в меню — чтобы заранее знать его высоту.
    private func actionCount(for msg: Message) -> Int {
        var n = 2   // Ответить, Переслать
        if model.isMine(msg) && msg.text?.isEmpty == false { n += 1 }   // Изменить
        if let text = msg.text, !text.isEmpty { n += 1 }                 // Копировать
        if model.isMine(msg) || isAdmin { n += 1 }                       // Удалить
        return n
    }

    /// Центр по X для блока меню: прижимаем к стороне сообщения, но держим на экране.
    private func menuBlockX(width: CGFloat, isMine: Bool, containerW: CGFloat) -> CGFloat {
        let margin: CGFloat = 14
        let raw = isMine ? (menuFrame.maxX - width / 2) : (menuFrame.minX + width / 2)
        return min(max(raw, margin + width / 2), containerW - margin - width / 2)
    }

    // Фиксированная ширина панели реакций — та же, что передаём в menuBlockX,
    // чтобы кламп по краям экрана считался по реальному размеру (иначе панель
    // уезжала за край). Влезает и на узких экранах (iPhone SE).
    private static let reactionsBarWidth: CGFloat = 272

    private func reactionsBar(_ msg: Message) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.quickEmojis, id: \.self) { emoji in
                Button {
                    model.toggleReaction(msg, emoji: emoji)
                    closeMenu()
                } label: {
                    Text(emoji).font(.system(size: 26))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: Self.reactionsBarWidth)
        .padding(.vertical, 5)
        .glass(cornerRadius: 26)
    }

    private func actionsMenu(_ msg: Message) -> some View {
        VStack(spacing: 0) {
            actionRow("Ответить", "arrowshape.turn.up.left") { model.replyingTo = msg }
            menuDivider
            actionRow("Переслать", "arrowshape.turn.up.right") { forwardingMessage = msg }
            if model.isMine(msg) && msg.text?.isEmpty == false {
                menuDivider
                actionRow("Изменить", "pencil") { model.startEditing(msg) }
            }
            if let text = msg.text, !text.isEmpty {
                menuDivider
                actionRow("Копировать", "doc.on.doc") { UIPasteboard.general.string = text }
            }
            if model.isMine(msg) || isAdmin {
                menuDivider
                actionRow("Удалить", "trash", destructive: true) {
                    Task { await model.deleteMessage(msg) }
                }
            }
        }
        .glass(cornerRadius: 14)
        .frame(width: 250)
    }

    private func statusChip(_ status: String) -> some View {
        Text(status)
            .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glass(cornerRadius: 12, elevated: false)
    }

    /// Само сообщение поверх размытого чата. Копия неинтерактивна: жесты тут
    /// принадлежат меню. Масштаб задаёт вызывающий (вписывает высокое фото).
    private func liftedMessage(_ msg: Message) -> some View {
        MessageBubble(message: msg,
                      isMine: model.isMine(msg),
                      sender: model.sender(msg),
                      isDM: model.chat.isDirect)
            .allowsHitTesting(false)
    }

    /// Медиа-копия для меню: ТОЛЬКО фото/видео/альбом по центру, без аватара и
    /// выравнивающих распорок пузыря (те прижимали копию к краю отправителя и своё
    /// фото в ЛС «съезжало» вбок). Стиль повторяет mediaOnlyBubble (ширина 240).
    @ViewBuilder
    private func liftedMedia(_ msg: Message) -> some View {
        let all = msg.attachments.filter { $0.isImage || $0.isVideo }
        // Тот же предел плиток, что и в ленте: иначе поднятая копия разворачивалась
        // в полотно на несколько экранов, хотя в ленте было аккуратное «+N».
        let media = Array(all.prefix(MessageBubble.albumMaxTiles))
        let hidden = all.count - media.count
        Group {
            if media.count > 1 {
                let aspects = media.map { MessageBubble.aspect($0) }
                let layout = AlbumMosaicLayout.frames(aspects: aspects, count: media.count, width: 240)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(media.enumerated()), id: \.element.id) { idx, att in
                        let r = idx < layout.rects.count ? layout.rects[idx] : .zero
                        let isLast = idx == media.count - 1 && hidden > 0
                        Color.clear
                            .frame(width: r.width, height: r.height)
                            .overlay(
                                // Превью, а не оригинал: копия живёт доли секунды,
                                // тянуть ради неё полноразмерные фото незачем.
                                CachedAsyncImage(url: att.previewURL) { $0.resizable().scaledToFill() }
                                    placeholder: { Theme.panel2 }
                            )
                            .overlay {
                                if isLast {
                                    ZStack {
                                        Color.black.opacity(0.45)
                                        Text("+\(hidden)").font(.title3.weight(.semibold))
                                            .foregroundStyle(.white)
                                    }
                                } else if att.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title3).foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            .clipped()
                            .offset(x: r.minX, y: r.minY)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            } else if let att = media.first {
                if att.isVideo {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .frame(width: 240, height: 150)
                        .overlay(Image(systemName: "play.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(.white.opacity(0.95)))
                } else {
                    // scaledToFit — фото показываем целиком, без обрезки (горизонтальное
                    // не должно кадрироваться под портрет). Рамку задаёт внешний
                    // .frame(240×naturalH) с корректной высотой из размеров/кэша, поэтому
                    // фото её заполняет и скругляется общей обрезкой блока.
                    CachedAsyncImage(url: att.remoteURL) { $0.resizable().scaledToFit() }
                        placeholder: { Theme.panel2 }
                }
            }
        }
        // Единая скруглённая обрезка для одиночного фото И альбома — в чате
        // скругление даёт пузырь, а у копии в меню его нет, поэтому альбом выходил
        // без скругления. Клипаем весь блок целиком.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
    }

    private var menuDivider: some View { Divider().opacity(0.25) }

    private func actionRow(_ title: String, _ icon: String,
                           destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button {
            action()
            closeMenu()
        } label: {
            HStack {
                Text(title).font(Typography.callout)
                Spacer()
                Image(systemName: icon)
            }
            .foregroundStyle(destructive ? Theme.danger : Theme.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func closeMenu() {
        withAnimation(.smooth(duration: 0.2)) { menuMessage = nil }
        menuPop = false
    }

    /// Строка статуса: в ЛС — прочитано/доставлено (+время), в группе — «прочитали N из M».
    private func statusLine(for msg: Message) -> String? {
        if model.chat.isDirect, model.isMine(msg) {
            switch readState(for: msg) {
            case .read:
                if let at = model.partnerReadAt { return "Прочитано в \(RelativeDate.time(at))" }
                return "Прочитано"
            case .delivered: return "Доставлено"
            case .sent: return "Отправлено"
            case .none: return nil
            }
        }
        if let info = model.groupReadInfo(for: msg) {
            return "Прочитали \(info.read) из \(info.total)"
        }
        return nil
    }

    private func openMedia(_ att: Message.Attachment) {
        let all = model.mediaAttachments
        let idx = all.firstIndex(where: { $0.id == att.id }) ?? 0
        mediaPreview = MediaPreview(items: all, index: idx)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.s) {
            // Пока ответ поиска не пришёл, «Ничего не найдено» показывать нельзя —
            // иначе оно мигает на каждой букве.
            if model.isSearching {
                ProgressView().tint(Theme.accent)
                Text("Ищем по всему мероприятию…")
                    .font(Typography.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: model.search.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                    .font(.largeTitle).foregroundStyle(Theme.textSecondary)
                Text(model.search.isEmpty ? "Пока нет сообщений" : "Ничего не найдено")
                    .font(Typography.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
        .allowsHitTesting(false)   // заглушка не должна перехватывать свайп между темами
    }

    // MARK: - Панель ответа

    private func editBar(_ editing: Message) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "pencil").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Редактирование").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(editing.text ?? "").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Button { model.cancelEditing() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.s).padding(.vertical, 6)
        .background(Theme.panel)
    }

    private func replyBar(_ reply: Message) -> some View {
        HStack(spacing: Spacing.s) {
            Rectangle().fill(Theme.accent).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(reply.senderName ?? "Ответ").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(reply.previewText).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Button { model.replyingTo = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.s).padding(.vertical, 6)
        .background(Theme.panel)
    }

    // MARK: - Ввод

    /// Подсказка при вводе «@»: сервер сверяет упоминание с ФИО целиком,
    /// поэтому имя должно попасть в текст ровно так, как оно в составе —
    /// набирать его руками ненадёжно.
    private var mentionBar: some View {
        VStack(spacing: 0) {
            ForEach(model.mentionSuggestions) { item in
                Button { model.applyMention(item) } label: {
                    HStack(spacing: Spacing.s) {
                        Avatar(name: item.title, size: 28, id: item.id)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(Typography.callout)
                                .foregroundStyle(Theme.textPrimary).lineLimit(1)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle).font(.caption2)
                                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.s).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.panel2)
    }

    /// Идёт запись или её вот-вот начнут — поле ввода уступает место счётчику.
    /// Палец учитываем отдельно: запись стартует асинхронно, а строка должна
    /// смениться в тот же миг, когда её коснулись.
    private var isRecordingUI: Bool { isPressingMic || model.isRecording }

    private var inputBar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if isRecordingUI {
                    // Счётчик тикает двадцать раз в секунду. Он живёт в отдельной
                    // вью со своим наблюдением за рекордером — иначе
                    // перерисовывался бы весь чат на каждый тик.
                    RecordingBar(recorder: model.recorder,
                                 isLocked: model.isRecordingLocked,
                                 onCancel: { Task { await model.cancelRecording() } })
                } else {
                    textInputBar
                }
            }
            .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
            .background(Theme.panel)

            // Правая кнопка нарисована поверх строки, а не внутри неё: во время
            // записи она вырастает в круг с ореолом и вылезает за её пределы, а
            // над ней всплывает замок. И, что важнее, она одна на все состояния —
            // убери её из дерева при смене ветки, и посреди удержания оборвался
            // бы жест, а вместе с ним и запись.
            trailingControl
                .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
        }
    }

    /// Что справа от поля: отправка текста, микрофон или — у зафиксированной
    /// записи — отправка голосового.
    @ViewBuilder
    private var trailingControl: some View {
        if hasDraft && !isRecordingUI {
            Button { Task { await model.send() } } label: {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.accent, in: Circle())
            }
        } else {
            micButton
        }
    }

    /// Всплывающая панель над кнопкой записи: пока держим — замок, к которому
    /// ведут палец, после фиксации — пауза.
    ///
    /// Замок здесь видимая цель, а не догадка: раньше фиксация была «увести
    /// палец вверх», и понять, увёл ли достаточно, было неоткуда.
    @ViewBuilder
    private var floatingPanel: some View {
        if model.isRecordingLocked {
            Button { model.togglePause() } label: {
                Image(systemName: model.isRecordingPaused ? "mic.fill" : "pause.fill")
                    .font(.headline).foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.panel2, in: Circle())
            }
            .offset(y: -52)
        } else {
            VStack(spacing: 6) {
                Image(systemName: lockArmed ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(lockArmed ? Theme.accent : Theme.textSecondary)
            .frame(width: 40, height: 72)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: lockArmed)
            .offset(y: -64)
        }
    }

    private var hasDraft: Bool { !model.draft.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Запись голосового удержанием, как в мессенджерах: держим — пишем,
    /// ведём вверх — фиксируем и можно отпустить, ведём влево — отменяем.
    ///
    /// После фиксации палец не нужен: круг становится отправкой, над ним
    /// появляется пауза, а отмена — обычной кнопкой в строке. На площадке в
    /// перчатках жест срывается, и без этого запасного пути записанное
    /// терялось бы.
    private var micButton: some View {
        // После фиксации круг перестаёт быть микрофоном и становится отправкой:
        // запись уже идёт сама, держать нечего.
        Image(systemName: model.isRecordingLocked ? "arrow.up" : "mic.fill")
            .font(.headline).foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Theme.accent, in: Circle())
            // Растёт под пальцем, как в мессенджерах: видно, что жест поймался.
            .scaleEffect(isPressingMic ? 1.6 : 1)
            // Ореол — уже поверх выросшего круга, поэтому и рисуется после
            // увеличения: иначе он множился бы на масштаб и залил пол-экрана.
            .background {
                if isPressingMic {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.10)).scaleEffect(2.6)
                        Circle().fill(Theme.accent.opacity(0.16)).scaleEffect(1.95)
                    }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isPressingMic)
            .contentShape(Rectangle())
            // Круг едет за пальцем к замку. Смещение не меняет место в лейауте,
            // поэтому сам замок остаётся стоять — к нему и ведут.
            .offset(micDrag)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Зафиксированную запись жест не трогает: круг стал
                        // обычной кнопкой «отправить».
                        guard !model.isRecordingLocked else { return }
                        if !isPressingMic {
                            isPressingMic = true
                            lockArmed = false
                            Task { await model.startRecording() }
                        }
                        let dx = max(min(0, value.translation.width), -80)
                        let dy = max(min(0, value.translation.height), -70)
                        micDrag = CGSize(width: dx, height: dy)
                        // Вверх до замка — фиксируем, влево — отменяем.
                        if dy < -lockDistance {
                            model.isRecordingLocked = true
                            isPressingMic = false
                            lockArmed = false
                            micDrag = .zero
                            Haptics.success()
                        } else if value.translation.width < -80 {
                            isPressingMic = false
                            lockArmed = false
                            micDrag = .zero
                            Task { await model.cancelRecording() }
                        } else {
                            lockArmed = dy < -25
                        }
                    }
                    .onEnded { value in
                        micDrag = .zero
                        lockArmed = false
                        if model.isRecordingLocked {
                            // Касание по кругу отправляет. Смазанное касание —
                            // это уже прокрутка чего-то другого, не отправка.
                            if abs(value.translation.width) < 12,
                               abs(value.translation.height) < 12 {
                                Task { await model.finishRecording() }
                            }
                            return
                        }
                        guard isPressingMic else { return }
                        isPressingMic = false
                        // Ждём внутри модели: короткое нажатие могло отпуститься
                        // раньше, чем запись успела начаться.
                        Task { await model.finishRecording() }
                    }
            )
            .overlay(alignment: .bottom) {
                if isRecordingUI { floatingPanel }
            }
    }

    /// Насколько вести палец вверх до фиксации. Ровно до замка: он висит на
    /// этом же расстоянии, и «дошёл до иконки» должно значить «сработало».
    private let lockDistance: CGFloat = 64

    private var textInputBar: some View {
        HStack(spacing: Spacing.s) {
            Menu {
                Button { showPhotoPicker = true } label: { Label("Фото и видео", systemImage: "photo.on.rectangle") }
                Button { showFileImporter = true } label: { Label("Файл", systemImage: "doc") }
            } label: {
                Image(systemName: "paperclip").font(.title3).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
            }

            TextField("Сообщение", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, Spacing.m).padding(.vertical, 10)
                .background(Theme.panel2, in: Capsule())

            // Место под правую кнопку: сама она нарисована поверх строки.
            Color.clear.frame(width: 40, height: 40)
        }
    }

}

/// Шапка личного чата: аватар + имя + статус. Отдельная вью со стабильными
/// входами — иначе тулбар пересоздавал её на каждое обновление модели и она мигала.
/// Точное отслеживание «мы внизу ленты» по штатной геометрии прокрутки (iOS 18+).
/// Единственный источник правды: раньше параллельно работала эвристика по
/// последнему пузырю и они перебивали друг друга.
private struct BottomTracking: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geo in
                // visibleRect учитывает отступы (safe area, клавиатура),
                // поэтому «низ виден» считается честно.
                geo.contentSize.height <= geo.visibleRect.height + 1
                    || geo.visibleRect.maxY >= geo.contentSize.height - 60
            } action: { _, atBottom in
                onChange(atBottom)
            }
        } else {
            content
        }
    }
}

private struct DMHeaderView: View {
    let title: String
    let avatarURL: URL?
    let otherId: String?
    let onTap: () -> Void

    @ObservedObject private var realtime = RealtimeService.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                avatar
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if let otherId {
                        Text(Presence.text(isOnline: realtime.isOnline(otherId),
                                           lastSeen: realtime.lastSeen(for: otherId)))
                            .font(.caption2)
                            .foregroundStyle(realtime.isOnline(otherId) ? Theme.success : Theme.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL {
            CachedAsyncImage(url: avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                Avatar(name: title, size: 30, id: otherId ?? "")
            }
            .frame(width: 30, height: 30).clipShape(Circle())
        } else {
            Avatar(name: title, size: 30, id: otherId ?? "")
        }
    }
}

private struct DaySeparator: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Typography.caption).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Spacing.s).padding(.vertical, 4)
            .background(Theme.panel.opacity(0.7), in: Capsule())
            .padding(.vertical, Spacing.xs)
    }
}
