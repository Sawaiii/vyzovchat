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
    /// Открыто окно поиска. Отдельным окном, а не строкой под шапкой: строка
    /// занимала место всегда, а найденное подменяло собой ленту.
    @State private var showSearch = false
    @State private var showEventInfo = false
    @State private var showGallery = false
    @State private var showCreateTopic = false
    @State private var editingTopic: TopicDTO?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var mediaPreview: MediaPreview?
    @State private var profileUser: User?
    /// Сообщение, по которому смотрим список ознакомившихся.
    @State private var ackMessageId: AckTarget?
    @State private var scrollTarget: String?
    @State private var highlightedId: String?
    /// Доводка прокрутки к сообщению — держим, чтобы прервать её, как только
    /// ленту тронут рукой.
    @State private var settleTask: Task<Void, Never>?
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
    /// Открытый чеклист оборудования: погрузка или приёмка.
    @State private var checklistKind: EquipCheckKind?
    /// Темы, чью ленту уже довели до конца при первом показе. Повторно не
    /// доводим: человек мог уйти вверх по переписке, и возврат в тему не
    /// должен утаскивать его в конец.
    @State private var settledTopics: Set<String> = []
    /// Ленты страниц (у пейджера тем их несколько) — через них просим прокрутку
    /// и узнаём, где на экране лежит сообщение.
    @State private var feeds = ChatFeedRegistry()
    /// Где начинается чат в координатах окна: кадр сообщения новая лента отдаёт
    /// в оконных координатах, а меню раскладывается в координатах чата.
    @State private var chatOrigin: CGPoint = .zero
    /// Новая лента (UICollectionView) вместо прежней SwiftUI-прокрутки.
    /// Читаем один раз при открытии чата: менять реализацию на лету посреди
    /// открытой переписки незачем.
    @State private var useCollectionFeed = ChatFeedSettings.useCollection

    init(chat: Chat, currentUserId: String = MockData.currentUser.id) {
        _model = StateObject(wrappedValue: ChatViewModel(
            chat: chat, service: Backend.chat(), currentUserId: currentUserId))
    }

    private var uploadErrorBinding: Binding<Bool> {
        Binding(get: { model.uploadError != nil },
                set: { if !$0 { model.uploadError = nil } })
    }

    private var pinErrorBinding: Binding<Bool> {
        Binding(get: { model.pinError != nil },
                set: { if !$0 { model.pinError = nil } })
    }

    private var stageErrorBinding: Binding<Bool> {
        Binding(get: { model.stageError != nil },
                set: { if !$0 { model.stageError = nil } })
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
                    // Шапка — один блок с общим фоном и общим шагом по
                    // вертикали: раньше каждая полоса несла свои отступы, и они
                    // складывались в разнобой.
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: 6) {
                            if let company = model.chat.company {
                                CompanyBadge(name: company, compact: false)
                            }
                            StatusBadgesRow(badges: model.chat.statusBadges)
                        }
                        .padding(.horizontal, Spacing.m)

                        eventTimeLine
                            .padding(.horizontal, Spacing.m)

                        // Дорожка этапов — над темами: она про мероприятие
                        // целиком, а темы уже про переписку внутри него.
                        StagesTrack(model: model) { kind in checklistKind = kind }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
                    // Непрозрачно: сквозь полупрозрачную панель светлые обои
                    // просвечивали, и серые подписи этапов по ним не читались.
                    .background(Theme.panel)

                    TopicBar(
                        topics: model.topics,
                        selected: model.selectedTopicId,
                        canManage: model.isChatAdmin,
                        unread: { model.unreadCount(for: $0) },
                        onSelect: { id in Task { await model.selectTopic(id) } },
                        onCreate: { showCreateTopic = true },
                        onEditAccess: { topic in editingTopic = topic },
                        onDelete: { topic in Task { await model.deleteTopic(topic.id) } },
                        onToggleMute: { topic in
                            Task { await model.toggleTopicMute(topic.id) }
                        },
                        isTopicMuted: { topic in model.isTopicMuted(topic.id) }
                    )
                }

                // Полоса закрепа лежит ПОВЕРХ ленты, а не над ней. В потоке она
                // меняла высоту прокрутки при каждом свайпе между темами — где
                // закреп есть и где его нет, — и лента дёргалась к концу. Плюс
                // закрепы есть и в личной переписке, поэтому полоса живёт
                // снаружи блока мероприятия.
                Group {
                    if model.chat.isDirect || model.topics.isEmpty {
                        messagesScroll
                    } else {
                        topicPager
                    }
                }
                .overlay(alignment: .top) { pinBar }

                if model.isReadOnly {
                    // Гость переписку читает, но не пишет: сокет от него принимает
                    // только вход в комнату. Пустая строка ввода без объяснения
                    // выглядела бы поломкой.
                    guestNote
                } else {
                    if !model.mentionSuggestions.isEmpty { mentionBar }
                    if let editing = model.editingMessage { editBar(editing) }
                    else if let reply = model.replyingTo { replyBar(reply) }
                    // Строка ввода — отдельная вью: состояние записи меняется
                    // несколько раз за секунду жеста, и держи мы его здесь, каждое
                    // изменение перерисовывало бы шапку, темы и все ленты разом.
                    ChatInputBar(model: model,
                                 showPhotoPicker: $showPhotoPicker,
                                 showFileImporter: $showFileImporter)
                }
            }
            // Размытия чата здесь больше нет. `.blur` — фильтр слоя, и он
            // работает всегда, а не только когда радиус больше нуля: весь чат
            // уходил в отдельный буфер и пересобирался на каждом кадре. Отсюда
            // и общая вязкость — и прокрутки, и любой анимации поверх ленты.
            // Размывает теперь сама подложка меню, и только пока меню открыто.
            // (scaleEffect тут был убран раньше: уменьшение ленты к центру
            // «переякоривало» прижатую к низу ленту, и чат съезжал.)

            if let msg = menuMessage { messageMenu(msg) }
        }
        .coordinateSpace(name: Self.chatSpace)
        // Начало координат чата в окне. Меряется при раскладке (появилась
        // клавиатура, повернули экран), а не при прокрутке, — поэтому дёшево.
        // По нему кадр сообщения из новой ленты переводится в координаты чата.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { chatOrigin = geo.frame(in: .global).origin }
                    .onChange(of: geo.frame(in: .global).origin) { chatOrigin = $1 }
            }
        )
        .navigationTitle(model.chat.title)
        .navigationBarTitleDisplayMode(.inline)
        // Нижние вкладки в переписке НЕ прячем. `.toolbar(.hidden, for: .tabBar)`
        // здесь работает, но появляется и исчезает бар отдельно от перехода:
        // при входе пропадает разом, при возврате выскакивает поверх уже
        // открытого списка. Сгладить это средствами SwiftUI не выходит —
        // объявленная на списке видимость распространяется на весь стек и
        // отменяет скрытие вовсе. Пусть лучше стоит на месте.
        // Штатного `searchable` здесь нет намеренно: он держит под шапкой целую
        // строку всегда, а ищут в чате изредка. Поиск живёт в своём окне.
        .sheet(isPresented: $showSearch) {
            ChatSearchView(model: model) { message in
                Task { await model.openFound(message) }
            }
        }
        .toolbar {
            if model.chat.isDirect {
                ToolbarItem(placement: .principal) {
                    DMHeaderView(title: model.chat.title,
                                 avatarURL: model.chat.avatarURL,
                                 otherId: model.chat.otherUserId,
                                 onTap: openOtherProfile)
                }
            }
            // Смены — отдельной кнопкой, а не пунктом меню: отметиться на месте
            // выездник должен в одно касание, а не вспоминать, что это спрятано
            // за многоточием. Остальное меню держим одним пунктом (см. ниже),
            // так что кнопок в тулбаре по-прежнему две и переполнение не грозит.
            if !model.chat.isDirect {
                // Поиск — только у мероприятия: искать по переписке сервер
                // не умеет, а её последняя сотня и так вся перед глазами.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Поиск в чате")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShifts = true } label: {
                        Image(systemName: "clock.badge.checkmark")
                    }
                    .accessibilityLabel("Смены")
                }
            }
            // Одно меню вместо россыпи кнопок: их набралось до шести, система
            // прятала лишние в своё переполнение — то самое «троеточие, которое
            // ничего не делает». Заодно совпадает с бургером в веб-версии.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showGallery = true } label: { Label("Медиа чата", systemImage: "photo.stack") }
                    if !model.chat.isDirect {
                        // Смен здесь нет — они вынесены отдельной кнопкой рядом.
                        Button { showEventInfo = true } label: { Label("О мероприятии", systemImage: "info.circle") }
                        Button { showMembers = true } label: { Label("Участники", systemImage: "person.2.fill") }
                        // Отбор фото ведёт админ чата и старший; отправку в
                        // «Отчёт» и «Фотобанк» внутри увидит только админ.
                        if model.canPickPhotos && model.chat.isPhotoReportOpen {
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
        .alert("Закреп", isPresented: pinErrorBinding) {
            Button("Понятно", role: .cancel) { model.pinError = nil }
        } message: {
            Text(model.pinError ?? "")
        }
        .alert("Этап", isPresented: stageErrorBinding) {
            Button("Понятно", role: .cancel) { model.stageError = nil }
        } message: {
            Text(model.stageError ?? "")
        }
        .sheet(item: $checklistKind) { kind in
            EquipChecklistView(dealId: model.chat.dealId,
                               kind: kind,
                               canCheck: model.canCheck(kind),
                               canEdit: model.canEditEquipment,
                               canClaim: model.canClaims,
                               myWarehouses: session.currentUser?.warehouseIds ?? []) {
                Task { await model.loadStages() }
            }
        }
        .sheet(isPresented: $showEventInfo) {
            EventInfoView(dealId: model.chat.dealId,
                          eventTitle: model.chat.title,
                          isChatAdmin: model.isChatAdmin,
                          canInvite: model.canInvite,
                          canDocs: model.canDocs,
                          canClaims: model.canClaims,
                          canReview: model.canReview,
                          claimTopicId: model.claimTopicId,
                          address: model.chat.address,
                          crmURL: model.chat.crmURL,
                          actURL: model.chat.actURL)
                .environmentObject(session)
        }
        .sheet(isPresented: $showShifts) {
            EventShiftsView(dealId: model.chat.dealId,
                            eventTitle: model.chat.title,
                            isChatAdmin: model.isChatAdmin,
                            canCheckin: model.canCheckin,
                            canEditShifts: model.canEditShifts)
                .environmentObject(session)
        }
        .sheet(item: $ackMessageId) { target in
            AckListView(messageId: target.id) { await model.ackList(messageId: $0) }
        }
        .sheet(isPresented: $showMembers) {
            // Управление участниками — только глобальный админ.
            ChatMembersView(dealId: model.chat.dealId, chatTitle: model.chat.title,
                            canManage: model.isChatAdmin,
                            canAssignRoles: model.canAssignRoles)
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
        // Разрешение на геолокацию спрашиваем здесь: человек открыл выбор фото,
        // и системный вопрос про геометку снимка на этом месте объясним. Пока он
        // выбирает кадры, ответ успевает прийти — координата попадёт уже в первое фото.
        .onChange(of: showPhotoPicker) {
            if showPhotoPicker { LocationProvider.shared.requestAuthorization() }
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

    @ViewBuilder
    private func feed(for topicId: Int?) -> some View {
        if useCollectionFeed {
            collectionFeed(for: topicId)
        } else {
            legacyFeed(for: topicId)
        }
    }

    /// Прежняя лента на SwiftUI-прокрутке. Остаётся запасным вариантом, пока
    /// новая не обкатана: переключатель — в профиле.
    private func legacyFeed(for topicId: Int?) -> some View {
        let isActive = topicId == model.loadedTopicId
        let pageKey = topicId.map(String.init) ?? "main"
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
                                // Лента всегда лента. Режима поиска, в котором
                                // сообщения превращались в ссылки, здесь больше
                                // нет: найденное живёт в своём окне.
                                bubble(for: message, showRead: showRead)
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
                    // Колесо — только когда показывать нечего. Раньше оно
                    // висело поверх уже загруженной ленты, пока догружалась
                    // обвязка чата, и выглядело как «всё ещё грузится».
                    if items.isEmpty {
                        if loading { ProgressView().tint(Theme.accent) } else { emptyState }
                    }
                }
                .modifier(BottomTracking { if isActive { updateAtBottom($0) } })
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded {
                    UIApplication.shared.endEditing()
                    settleTask?.cancel()
                })
                // Только чтобы узнать, что ленту листают рукой: прокрутке этот
                // жест не мешает (идёт рядом и ничего не забирает), а доводку
                // после перехода к сообщению надо в этот момент прекратить.
                .simultaneousGesture(DragGesture(minimumDistance: 8)
                    .onChanged { _ in settleTask?.cancel() })
                .modifier(FeedBehaviors(
                    view: self, isActive: isActive, pageKey: pageKey,
                    toBottom: { animated in
                        // Прежняя лента: только доводкой. Одиночная прокрутка в
                        // ленивом списке не доезжает.
                        if animated { jumpToBottom(proxy) } else { settleAtBottom(proxy) }
                    },
                    toItem: { id, position, animated in
                        switch position {
                        case .center: settleCentered(proxy, to: id)
                        case .top:    settle(proxy, to: id)
                        case .bottom:
                            if animated {
                                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .bottom) }
                            } else {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }))

                // Только на активной странице: на соседних кнопка не нужна.
                scrollDownButton { jumpToBottom(proxy) }.opacity(isActive ? 1 : 0)
            }
        }
    }

    /// Новая лента: строки те же, держит их `UICollectionView`.
    private func collectionFeed(for topicId: Int?) -> some View {
        let isActive = topicId == model.loadedTopicId
        let pageKey = topicId.map(String.init) ?? "main"
        let loading = isActive ? model.isLoading : !model.isTopicLoaded(topicId)
        let items = isActive ? model.activeFeed : model.staticFeed(for: topicId)

        return ZStack(alignment: .bottomTrailing) {
            ChatFeedCollection(
                rows: feedRows(items),
                content: { row in AnyView(rowContent(row, pageKey: pageKey)) },
                // Карта упоминаний общая для всех строк и приезжает позже
                // сообщений: пока её нет, «@Иванов» в тексте не кликабелен.
                revision: model.mentionIndex.count,
                registry: feeds,
                pageKey: pageKey,
                onAtBottomChange: { atBottom in if isActive { updateAtBottom(atBottom) } },
                onUserScroll: { settleTask?.cancel() },
                onTap: {
                    UIApplication.shared.endEditing()
                    settleTask?.cancel()
                }
            )
            .overlay {
                if items.isEmpty {
                    if loading { ProgressView().tint(Theme.accent) } else { emptyState }
                }
            }
            .modifier(FeedBehaviors(
                view: self, isActive: isActive, pageKey: pageKey,
                toBottom: { animated in feeds[pageKey]?.scrollToBottom(animated: animated) },
                toItem: { id, position, animated in
                    feeds[pageKey]?.scroll(to: id, position: position, animated: animated)
                }))

            scrollDownButton { feeds[pageKey]?.scrollToBottom(animated: true) }
                .opacity(isActive ? 1 : 0)
        }
    }

    /// Строки для новой ленты: всё, от чего зависит вид пузыря, считаем здесь.
    /// Ячейка ничего не слушает и перерисовывается ровно тогда, когда её строка
    /// изменилась, — поэтому набор текста в поле ввода ленты больше не касается.
    private func feedRows(_ items: [ChatFeedItem]) -> [ChatFeedRow] {
        items.map { item in
            guard case let .message(message, showRead) = item else {
                return ChatFeedRow(id: item.id, item: item)
            }
            return ChatFeedRow(
                id: item.id,
                item: item,
                highlighted: highlightedId == message.id,
                readState: showRead ? readState(for: message) : .none,
                groupRead: showRead ? model.groupReadInfo(for: message) : nil,
                readAt: model.partnerReadAt,
                sender: model.sender(message),
                isMine: model.isMine(message),
                replyToMe: message.replyToId != nil && message.replySender != nil
                    && message.replySender == myFio,
                canDelete: model.isMine(message) || isAdmin,
                canEdit: model.isMine(message) && (message.text?.isEmpty == false),
                canAck: model.canAck
            )
        }
    }

    @ViewBuilder
    private func rowContent(_ row: ChatFeedRow, pageKey: String) -> some View {
        switch row.item {
        case .separator(let title, _):
            // По центру строки: в прежнем списке это делал сам VStack, а ячейка
            // выравнивания за собой не приносит.
            DaySeparator(title: title).frame(maxWidth: .infinity)
        case .uploading(let pending):
            UploadingTile(pending: pending)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .message(let message, _):
            // «Поп» при удержании заводится внутри строки: снаружи ячейка увидела
            // бы только конечное значение, и вместо пружины вышел бы рывок.
            PressPop(anchor: row.isMine ? .trailing : .leading) { trigger in
                collectionBubble(message, row: row, pageKey: pageKey,
                                 pop: { trigger.fire() })
            }
        }
    }

    private func collectionBubble(_ message: Message, row: ChatFeedRow,
                                  pageKey: String, pop: @escaping () -> Void) -> some View {
        MessageBubble(
            message: message,
            isMine: row.isMine,
            sender: row.sender,
            replyToMe: row.replyToMe,
            canDelete: row.canDelete,
            canEdit: row.canEdit,
            isDM: model.chat.isDirect,
            readState: row.readState,
            readAt: row.readAt,
            groupRead: row.groupRead,
            highlighted: row.highlighted,
            mentionPeople: model.mentionIndex,
            onLongPress: {
                // Кадр сообщения берём у коллекции: он всегда настоящий, включая
                // момент прокрутки. Прежняя лента мерила его SwiftUI-геометрией,
                // но внутри ячейки такой замер устаревает — ячейку двигает
                // прокрутка, а SwiftUI об этом не пересчитывается.
                if let frame = feeds[pageKey]?.windowFrame(forItem: message.id) {
                    menuFrame = frame.offsetBy(dx: -chatOrigin.x, dy: -chatOrigin.y)
                    menuFrameId = message.id
                }
                // Пружину заводит сама строка (`PressPop`) — здесь остаётся
                // только показать меню.
                pop()
                withAnimation(.smooth(duration: 0.16)) { menuMessage = message }
            },
            onReact: { emoji in model.toggleReaction(message, emoji: emoji) },
            onOpenProfile: { id in profileUser = model.user(for: id) },
            onOpenMedia: { att in openMedia(att) },
            onOpenReply: { rid in scrollTarget = rid },
            canAck: row.canAck,
            onAck: { Task { await model.ack(message) } },
            onShowAcks: { ackMessageId = AckTarget(id: message.id) }
        )
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


    /// Доводчик для перехода в середину ленты. Тот же приём, что и у конца
    /// ленты: в ленивом списке первая попытка часто не доезжает — ячейки ещё
    /// не построены, а после подмены ленты нужной может не быть вовсе.
    /// Без анимации: анимировать доводку к цели, которая ещё едет, — это и
    /// есть та самая дёрганая прокрутка.
    private func settleCentered(_ proxy: ScrollViewProxy, to id: String) {
        proxy.scrollTo(id, anchor: .center)
        settleTask?.cancel()
        settleTask = Task {
            // С запасом: лента прижата к низу, и пока она достраивается после
            // подмены, каждый её перерасчёт тянет прокрутку обратно в конец.
            // Побеждает тот, кто скажет последним.
            for delay in [16, 60, 120, 200, 320, 500, 750] {
                try? await Task.sleep(for: .milliseconds(delay))
                // Тронули ленту рукой — доводка прекращается. Иначе очередной
                // повтор дёргал обратно к сообщению человека, который уже начал
                // листать от него дальше.
                if Task.isCancelled { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// Поведение ленты, общее для обеих реализаций: первый показ, приход
    /// сообщения, возврат в тему и переход к найденному. Различаются они только
    /// тем, КАК прокручивают, — это и приходит закрытиями.
    private struct FeedBehaviors: ViewModifier {
        let view: ChatView
        let isActive: Bool
        let pageKey: String
        let toBottom: (_ animated: Bool) -> Void
        let toItem: (_ id: String, _ position: ChatFeedPosition, _ animated: Bool) -> Void

        func body(content: Content) -> some View {
            content
                // Первая загрузка чата: есть непрочитанные — встаём там, где они
                // начинаются; иначе строго в конце ленты.
                .onChange(of: view.model.messages.count) {
                    guard isActive, !view.didInitialScroll else { return }
                    view.didInitialScroll = true
                    if let anchor = view.model.initialAnchorId {
                        toItem(anchor, .top, false)
                    } else {
                        toBottom(false)
                    }
                }
                // Пришло новое сообщение. Именно ДОБАВИЛОСЬ, а не «в ленте стало
                // другое число»: при смене темы массив подменяется целиком, и по
                // счётчику лента уезжала в конец на каждом свайпе. И только если
                // человек и так внизу — иначе выдёргивали бы из середины.
                .onChange(of: view.model.appendedMessageId) {
                    guard isActive, let id = view.model.appendedMessageId else { return }
                    view.model.appendedMessageId = nil
                    // Своё сообщение показываем всегда: отправил — жду увидеть.
                    let mine = view.model.messages.first { $0.id == id }
                        .map(view.model.isMine) ?? false
                    guard view.isAtBottom || mine else { return }
                    toItem(id, .bottom, true)
                }
                // Стали активной темой — её лента открывается с конца, но ровно
                // один раз. Раньше доводчик срабатывал на каждый возврат в тему
                // и швырял ленту в конец, даже если человек читал середину, —
                // это и был резкий баунс при свайпе туда-обратно.
                .onChange(of: isActive) {
                    guard isActive, !view.settledTopics.contains(pageKey) else { return }
                    view.settledTopics.insert(pageKey)
                    toBottom(false)
                }
                // Страница, открытая сразу при входе в чат: её доводит
                // didInitialScroll, и второй раз при возврате не нужно.
                .onAppear { if isActive { view.settledTopics.insert(pageKey) } }
                // Переход из поиска: окно ленты уже загружено, осталось встать
                // на найденном сообщении и подсветить его. Просим прокрутку
                // сразу, не через `scrollTarget`: лишний цикл здесь означает,
                // что лента успевала встать в конец только что подставленного
                // окна и лишь потом прыгала к сообщению.
                .onChange(of: view.model.jumpToMessageId) {
                    guard isActive, let target = view.model.jumpToMessageId else { return }
                    view.model.jumpToMessageId = nil
                    view.model.jumpNeedsSettle = false
                    jump(to: target)
                }
                // Переход по цитате: сообщение уже в этой ленте.
                .onChange(of: view.scrollTarget) {
                    guard isActive, let target = view.scrollTarget else { return }
                    view.scrollTarget = nil
                    jump(to: target)
                }
        }

        private func jump(to target: String) {
            // Вести надо к строке ленты, а не к сообщению: у фотографии из
            // альбома своей строки нет, альбом склеен в одну.
            let anchor = view.model.feedAnchorId(for: target) ?? target
            view.highlightedId = anchor
            toItem(anchor, .center, false)
            Task {
                try? await Task.sleep(for: .milliseconds(1800))
                withAnimation { view.highlightedId = nil }
            }
        }
    }

    /// Кнопка «в конец диалога». Видна, только когда пользователь листает вниз
    /// и ещё не достиг конца.
    private func scrollDownButton(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
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
            mentionPeople: model.mentionIndex,
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
            onOpenReply: { rid in scrollTarget = rid },
            canAck: model.canAck,
            onAck: { Task { await model.ack(message) } },
            onShowAcks: { ackMessageId = AckTarget(id: message.id) }
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
        // Своего .id(message.id) здесь нет намеренно. Строка ленты и так
        // опознаётся этим же идентификатором — им же её и находит прокрутка.
        // А вот второй такой же id внутри строки прокрутке мешал: пока строка
        // не построена, найти его негде, и переход к сообщению, которого сейчас
        // нет на экране, молча не срабатывал.
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
                // Подложка и размывает чат, и затемняет его. Размытие живёт
                // здесь, а не на самом чате: слой-фильтр поверх ленты работает
                // постоянно, даже с нулевым радиусом, и стоит кадра. Меню же
                // появляется на секунду и на статичном экране.
                Color.black.opacity(0.45)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
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
        if model.canPin { n += 1 }                                       // Закрепить
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
            if model.canPin {
                menuDivider
                if model.pins.contains(where: { $0.id == msg.id }) {
                    actionRow("Открепить", "pin.slash") { Task { await model.unpin(msg) } }
                } else {
                    actionRow("Закрепить", "pin") { Task { await model.pin(msg) } }
                }
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
                      isDM: model.chat.isDirect,
                      mentionPeople: model.mentionIndex)
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

    /// Заглушка пустой ленты. Про поиск здесь больше ничего нет: он в своём
    /// окне, и «ничего не найдено» говорит оно само.
    private var emptyState: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle).foregroundStyle(Theme.textSecondary)
            Text("Пока нет сообщений")
                .font(Typography.subheadline).foregroundStyle(Theme.textSecondary)
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

    /// Подпись вместо строки ввода у гостя.
    private var guestNote: some View {
        Text("Гостевой доступ: только просмотр.")
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .background(Theme.panel)
    }

    /// Полоса закреплённых сообщений — своя у «Общего», у каждой темы и у
    /// личной переписки. Нажатие ведёт к сообщению (даже если оно давно уехало
    /// из ленты) и переходит к следующему закрепу.
    @ViewBuilder
    private var pinBar: some View {
        if let pinned = model.pinned {
            HStack(spacing: Spacing.s) {
                Capsule().fill(Theme.accent).frame(width: 3, height: 28)
                Button {
                    Task { await model.goToPinned() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pinned.senderName ?? "Закреплённое")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                            Text(pinned.previewText)
                                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        // Счётчик только когда листать есть что.
                        if model.pins.count > 1 {
                            Text("\(model.pinIndex + 1)/\(model.pins.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // В мероприятии открепляет админ чата, в личной переписке — оба.
                if model.canPin {
                    Button { Task { await model.unpin() } } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Та же левая линия и тот же шаг по вертикали, что у остальной шапки.
            // Фон непрозрачный: полоса лежит поверх сообщений, и сквозь неё не
            // должен просвечивать текст.
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
            .background(Theme.panel)
        }
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
            // Непрозрачная капсула: на светлых обоях дата сквозь полупрозрачную
            // подложку читалась серым по сиреневому.
            .background(Theme.bubbleOther, in: Capsule())
            .padding(.vertical, Spacing.xs)
    }
}
