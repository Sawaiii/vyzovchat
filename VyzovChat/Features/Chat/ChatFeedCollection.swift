import SwiftUI
import UIKit

/// Лента чата на `UICollectionView`. Строки остаются теми же SwiftUI-вью
/// (`MessageBubble`, `DaySeparator`, `UploadingTile`) — меняется только то, что
/// их держит и прокручивает.
///
/// Зачем вообще: в ленивом списке SwiftUI прокрутка к сообщению целится по
/// прикидке высот, а построенные по дороге строки эту прикидку меняют — переход
/// не доезжал. Лечилось «доводчиками»: одна и та же прокрутка повторялась до
/// семи раз по таймеру (16…750 мс), и это ровно то, что видно как рывки. Здесь
/// доводить нечего: у коллекции есть настоящие атрибуты уложенных ячеек, и
/// нужное смещение считается арифметикой. Если после укладки строка всё же не
/// там, где надо (высоты уточнились), поправка идёт по факту раскладки, а не по
/// таймеру, и сама себя прекращает.
///
/// Что чинится само собой:
/// - **приход сообщения не двигает ленту.** Новая строка дописывается в конец, и
///   у того, кто читает середину, ничего не уезжает.
/// - **клавиатура.** Пока лента внизу, она внизу и остаётся.
struct ChatFeedCollection: UIViewRepresentable {
    /// Строки ленты вместе со всем, от чего зависит их вид: сравнением строк и
    /// решается, какую ячейку перерисовать.
    let rows: [ChatFeedRow]
    /// Сборка содержимого строки. Зовётся только для видимых ячеек.
    let content: (ChatFeedRow) -> AnyView
    /// Меняется, когда меняется общее для всех строк (карта упоминаний) —
    /// тогда перерисовываем всё видимое.
    var revision: Int = 0
    /// Общая на чат «память страниц»: где какая стояла и куда её просили встать.
    let store: ChatFeedStore
    let pageKey: String
    /// «Мы в конце ленты» — по нему показывается кнопка «вниз».
    var onAtBottomChange: (Bool) -> Void = { _ in }
    /// Ленту тронули рукой: чат по этому событию отменяет свои доводки.
    var onUserScroll: () -> Void = {}
    /// Тап по ленте — прячем клавиатуру.
    var onTap: () -> Void = {}

    /// Поля строки. Горизонтальное — вместо `.padding` у прежнего `LazyVStack`,
    /// вертикальное — вместо `spacing` между строками.
    static let horizontalMargin = Spacing.s
    static let verticalMargin = Spacing.xs / 2

    func makeUIView(context: Context) -> ChatFeedHostView {
        let host = ChatFeedHostView()
        context.coordinator.attach(to: host, store: store, pageKey: pageKey)
        return host
    }

    func updateUIView(_ host: ChatFeedHostView, context: Context) {
        let coordinator = context.coordinator
        coordinator.content = content
        coordinator.onAtBottomChange = onAtBottomChange
        coordinator.onUserScroll = onUserScroll
        coordinator.onTap = onTap
        coordinator.apply(rows: rows, revision: revision)
    }

    /// Лента занимает всё предложенное место — как и прежняя прокрутка. Без
    /// этого размер брался бы у `UIView`, у которого его нет.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChatFeedHostView,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    static func dismantleUIView(_ host: ChatFeedHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}

// MARK: - Строка ленты

/// Строка ленты со всем, что влияет на её вид.
///
/// Ячейка ничего не подписана слушать: в SwiftUI-ленте строки пересобирались на
/// каждое изменение модели (включая набор текста в поле ввода). Здесь строка —
/// значение, и ячейка перерисовывается ровно тогда, когда оно изменилось.
struct ChatFeedRow: Identifiable, Equatable {
    let id: String
    let item: ChatFeedItem
    /// Подсветка после перехода к сообщению.
    var highlighted = false
    /// Статус доставки своего сообщения в личной переписке.
    var readState: MessageBubble.ReadState = .none
    var groupRead: MessageBubble.GroupReadInfo?
    var readAt: Date?
    var sender: User?
    var isMine = false
    var replyToMe = false
    var canDelete = false
    var canEdit = false
    var canAck = false
}

/// «Поп» при удержании пузыря: он вдавливается и упруго возвращается.
///
/// Пружина живёт ВНУТРИ строки, а не снаружи. Снаружи она и не могла бы
/// сработать: ячейка перерисовывается по изменению своего содержимого, и
/// промежуточных кадров чужой анимации не увидит — «поп» получился бы рывком.
struct PressPop<Content: View>: View {
    /// Куда сжимается пузырь: своё сообщение прижато вправо, чужое — влево.
    let anchor: UnitPoint
    /// Содержимое строит вызывающий, а «нажали» сообщает через ручку.
    @ViewBuilder let content: (PressPopTrigger) -> Content

    @State private var scale: CGFloat = 1
    @State private var trigger = PressPopTrigger()

    var body: some View {
        content(trigger)
            .scaleEffect(scale, anchor: anchor)
            .onAppear { trigger.fire = press }
    }

    private func press() {
        withAnimation(.easeOut(duration: 0.08)) { scale = 0.92 }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) { scale = 1 }
    }
}

/// Ручка пружины. Ссылка, а не замыкание в параметре: `MessageBubble` хранит
/// обработчик удержания у себя, значит тот обязан быть убегающим, — а замыкание,
/// отданное параметром, таким быть не может.
final class PressPopTrigger {
    var fire: () -> Void = {}
}

// MARK: - Память страниц

enum ChatFeedPosition {
    case bottom, top, center
}

/// Где страница стояла: строка сверху экрана и на сколько она приподнята над
/// верхней кромкой. По смещению в точках восстанавливать нельзя — высоты ячеек
/// после пересборки уточняются, и то же смещение показывает уже другое место.
struct ChatFeedAnchor: Equatable {
    /// Пусто — стояли в конце ленты.
    let id: String?
    let delta: CGFloat
}

/// Просьба к ленте встать в определённое место.
struct ChatFeedRequest: Equatable {
    let id: String?
    let position: ChatFeedPosition
    let animated: Bool
}

/// Общая на чат память страниц: живая лента страницы, её последняя позиция и
/// невыполненная просьба прокрутиться.
///
/// Зачем: пейджер тем — это `UIPageViewController` внутри `TabView`, и он сносит
/// страницы, до которых далеко свайпнули. Возвращаясь, страница строится заново,
/// вместе с ней заново создаётся лента — и без этой памяти она открывалась бы в
/// конце, теряя место, где человек читал. По той же причине просьбу «встать на
/// сообщении» нельзя отдавать напрямую: страницы в этот момент может не быть.
final class ChatFeedStore {
    private var pages: [String: WeakBox] = [:]
    private var anchors: [String: ChatFeedAnchor] = [:]
    private var requests: [String: ChatFeedRequest] = [:]

    private struct WeakBox {
        weak var coordinator: ChatFeedCollection.Coordinator?
    }

    // MARK: Страницы

    @MainActor func register(_ coordinator: ChatFeedCollection.Coordinator, for key: String) {
        pages[key] = WeakBox(coordinator: coordinator)
    }

    @MainActor func unregister(_ key: String, if coordinator: ChatFeedCollection.Coordinator) {
        if pages[key]?.coordinator === coordinator { pages[key] = nil }
    }

    @MainActor private func page(_ key: String) -> ChatFeedCollection.Coordinator? {
        pages[key]?.coordinator
    }

    // MARK: Просьбы

    /// Прокрутить ленту страницы. Если страницы ещё нет или нужной строки в ней
    /// пока нет — просьба ждёт: её заберёт лента, как только сможет выполнить.
    @MainActor func scroll(to id: String, page key: String,
                position: ChatFeedPosition, animated: Bool) {
        send(ChatFeedRequest(id: id, position: position, animated: animated), to: key)
    }

    @MainActor func scrollToBottom(page key: String, animated: Bool) {
        send(ChatFeedRequest(id: nil, position: .bottom, animated: animated), to: key)
    }

    @MainActor private func send(_ request: ChatFeedRequest, to key: String) {
        if let page = page(key), page.perform(request) { return }
        requests[key] = request
    }

    func queue(_ request: ChatFeedRequest, for key: String) {
        requests[key] = request
    }

    func takeRequest(for key: String) -> ChatFeedRequest? {
        defer { requests[key] = nil }
        return requests[key]
    }

    func dropRequest(for key: String) {
        requests[key] = nil
    }

    // MARK: Позиция

    func save(_ anchor: ChatFeedAnchor, for key: String) {
        anchors[key] = anchor
    }

    func anchor(for key: String) -> ChatFeedAnchor? {
        anchors[key]
    }

    // MARK: Кадр сообщения

    /// Где строка лежит на экране (координаты окна) — по ней чат раскладывает
    /// всплывающее меню рядом с сообщением.
    @MainActor func windowFrame(forItem id: String, page key: String) -> CGRect? {
        page(key)?.windowFrame(forItem: id)
    }
}

// MARK: - Хост

/// Вью-обёртка: держит коллекцию и сообщает, что её размеры пересчитали.
/// Клавиатура, поворот, появление полосы закрепа — всё приходит сюда.
final class ChatFeedHostView: UIView {
    var onLayout: () -> Void = {}

    override func layoutSubviews() {
        super.layoutSubviews()
        subviews.first?.frame = bounds
        onLayout()
    }
}

/// Коллекция, которая сообщает о каждой своей раскладке. По этому событию
/// проверяется, доехала ли прокрутка до цели: высоты ячеек уточняются уже после
/// первой укладки, и это единственный честный момент для поправки — вместо
/// прежней очереди таймеров.
final class ChatFeedListView: UICollectionView {
    var onLayout: () -> Void = {}

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout()
    }
}

// MARK: - Координатор

extension ChatFeedCollection {

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        private var collection: ChatFeedListView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var order: [String] = []
        private var rowsById: [String: ChatFeedRow] = [:]
        private var revision = 0
        private var store: ChatFeedStore?
        private var pageKey = ""

        var content: (ChatFeedRow) -> AnyView = { _ in AnyView(EmptyView()) }
        var onAtBottomChange: (Bool) -> Void = { _ in }
        var onUserScroll: () -> Void = {}
        var onTap: () -> Void = {}

        /// Лента у конца (с запасом в экранный палец) — по этому показывается
        /// кнопка «вниз» и по нему же запоминается позиция страницы.
        private var pinnedToBottom = false
        /// Лента РОВНО в конце: только тогда она следует за растущим
        /// содержимым. С запасом нельзя — человека, стоящего в двух десятках
        /// точек от конца, дотягивало бы вниз при каждой подгрузке картинки.
        private var stickToBottom = false
        private var reportedAtBottom = true
        /// Первую позицию (запомненную или конец ленты) ставим один раз.
        private var didPlaceInitially = false
        /// Цель, до которой прокрутка ещё не подтверждена. Проверяется по факту
        /// раскладки и сама себя прекращает: либо доехали, либо кончились попытки.
        private var awaiting: (request: ChatFeedRequest, checks: Int)?

        // MARK: Сборка

        func attach(to host: ChatFeedHostView, store: ChatFeedStore, pageKey: String) {
            self.store = store
            self.pageKey = pageKey

            let view = ChatFeedListView(frame: host.bounds, collectionViewLayout: Self.makeLayout())
            view.backgroundColor = .clear
            view.allowsSelection = false
            view.alwaysBounceVertical = true
            // Клавиатура убирается тем же движением, что и в прежней ленте.
            view.keyboardDismissMode = .interactive
            // Прокрутка НЕ придерживает касания: иначе она сперва полторы десятых
            // секунды решает, не жест ли это, и только потом отдаёт нажатие
            // содержимому — удержание пузыря отзывалось с заметным опозданием.
            view.delaysContentTouches = false
            // Отступы держим сами: автоматический учёт безопасной области здесь
            // лишний — лента и так стоит между шапкой и строкой ввода.
            view.contentInsetAdjustmentBehavior = .never
            view.contentInset = UIEdgeInsets(top: Spacing.s, left: 0, bottom: Spacing.s, right: 0)
            view.verticalScrollIndicatorInsets = view.contentInset
            // Предзагрузка ячеек с SwiftUI-содержимым только мешает: она строит
            // хостинги заранее и меняет высоты за кадром.
            view.isPrefetchingEnabled = false
            view.delegate = self
            view.onLayout = { [weak self] in self?.listDidLayout() }

            let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
                guard let self, let row = self.rowsById[id] else { return }
                // Содержимое считаем ДО конфигурации, чтобы замыкание внутри неё
                // не держало координатор.
                let view = self.content(row)
                cell.contentConfiguration = UIHostingConfiguration { view }
                    .margins(.horizontal, ChatFeedCollection.horizontalMargin)
                    .margins(.vertical, ChatFeedCollection.verticalMargin)
                cell.backgroundConfiguration = .clear()
            }

            let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: view) { collection, indexPath, id in
                collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            // Не забираем нажатия у содержимого: кнопки и реакции в пузырях
            // должны работать как раньше.
            tap.cancelsTouchesInView = false
            tap.delegate = self
            view.addGestureRecognizer(tap)

            host.addSubview(view)
            host.onLayout = { [weak self] in self?.hostDidLayout() }

            collection = view
            dataSource = source
            store.register(self, for: pageKey)
        }

        func detach() {
            saveAnchor()
            store?.unregister(pageKey, if: self)
            collection = nil
            dataSource = nil
        }

        private static func makeLayout() -> UICollectionViewLayout {
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            config.backgroundColor = .clear
            return UICollectionViewCompositionalLayout.list(using: config)
        }

        // MARK: Данные

        func apply(rows: [ChatFeedRow], revision newRevision: Int) {
            guard let dataSource else { return }

            var map: [String: ChatFeedRow] = [:]
            map.reserveCapacity(rows.count)
            var changed: [String] = []
            for row in rows {
                map[row.id] = row
                if let old = rowsById[row.id], old != row { changed.append(row.id) }
            }
            let newOrder = rows.map(\.id)
            let orderChanged = newOrder != order
            let revisionChanged = newRevision != revision
            // Общее изменение (карта упоминаний) — перерисовываем всё, что есть.
            if revisionChanged { changed = newOrder.filter { rowsById[$0] != nil } }

            rowsById = map
            revision = newRevision
            guard orderChanged || !changed.isEmpty else {
                // Строки те же — может, ждёт невыполненная просьба.
                runPendingRequest()
                return
            }
            order = newOrder

            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(newOrder)
            if !changed.isEmpty {
                snapshot.reconfigureItems(changed.filter { map[$0] != nil })
            }

            let shouldStick = stickToBottom
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                if self.runPendingRequest() { return }
                if !self.didPlaceInitially {
                    self.placeInitially()
                } else if shouldStick {
                    // Лента стояла в конце — там и остаётся. Если человек читал
                    // середину, смещение не трогаем вовсе: новые строки дописаны
                    // ниже и на его место не влияют.
                    _ = self.perform(ChatFeedRequest(id: nil, position: .bottom, animated: false))
                }
            }
        }

        /// Первая установка страницы: где стояли в прошлый раз, иначе — конец.
        private func placeInitially() {
            didPlaceInitially = true
            guard let anchor = store?.anchor(for: pageKey), let id = anchor.id,
                  indexPath(for: id) != nil else {
                _ = perform(ChatFeedRequest(id: nil, position: .bottom, animated: false))
                return
            }
            restore(anchor)
        }

        @discardableResult
        private func runPendingRequest() -> Bool {
            guard let request = store?.takeRequest(for: pageKey) else { return false }
            if perform(request) {
                didPlaceInitially = true
                return true
            }
            // Строка ещё не доехала — просьба ждёт дальше.
            store?.queue(request, for: pageKey)
            return false
        }

        // MARK: Прокрутка

        /// Выполнить просьбу. `false` — строки пока нет, просьба должна подождать.
        @discardableResult
        func perform(_ request: ChatFeedRequest) -> Bool {
            guard let collection else { return false }
            if let id = request.id, indexPath(for: id) == nil { return false }
            collection.layoutIfNeeded()

            if request.animated {
                awaiting = (request, 4)
                if let id = request.id, let ip = indexPath(for: id) {
                    collection.scrollToItem(at: ip, at: uiPosition(request.position), animated: true)
                } else {
                    collection.setContentOffset(CGPoint(x: 0, y: bottomOffset()), animated: true)
                }
                return true
            }

            if let id = request.id, let ip = indexPath(for: id) {
                // Первый проход штатным методом: он по дороге укладывает ячейки,
                // и после него атрибуты цели уже настоящие.
                collection.scrollToItem(at: ip, at: uiPosition(request.position), animated: false)
                collection.layoutIfNeeded()
                applyExactOffset(for: ip, position: request.position)
                // Дальше высоты ещё могут уточниться — проверим по раскладке.
                awaiting = (request, 4)
            } else {
                collection.setContentOffset(CGPoint(x: 0, y: bottomOffset()), animated: false)
                collection.layoutIfNeeded()
                let corrected = bottomOffset()
                if abs(collection.contentOffset.y - corrected) > 0.5 {
                    collection.setContentOffset(CGPoint(x: 0, y: corrected), animated: false)
                }
            }
            updateAtBottom()
            return true
        }

        /// Вернуть страницу туда, где её оставили.
        private func restore(_ anchor: ChatFeedAnchor) {
            guard let collection, let id = anchor.id, let ip = indexPath(for: id) else { return }
            collection.layoutIfNeeded()
            collection.scrollToItem(at: ip, at: .top, animated: false)
            collection.layoutIfNeeded()
            guard let attrs = collection.layoutAttributesForItem(at: ip) else { return }
            let target = clamp(attrs.frame.minY - anchor.delta)
            if abs(collection.contentOffset.y - target) > 0.5 {
                collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            }
            updateAtBottom()
        }

        /// Точное смещение по реальным атрибутам уложенной ячейки.
        @discardableResult
        private func applyExactOffset(for ip: IndexPath, position: ChatFeedPosition) -> Bool {
            guard let collection,
                  let attrs = collection.layoutAttributesForItem(at: ip) else { return false }
            let height = collection.bounds.height
            let inset = collection.adjustedContentInset
            let raw: CGFloat
            switch position {
            case .top:    raw = attrs.frame.minY - inset.top
            case .center: raw = attrs.frame.midY - height / 2
            case .bottom: raw = attrs.frame.maxY - height + inset.bottom
            }
            let target = clamp(raw)
            guard abs(collection.contentOffset.y - target) > 1 else { return true }
            collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            return false
        }

        private func bottomOffset() -> CGFloat {
            guard let collection else { return 0 }
            return clamp(collection.contentSize.height - collection.bounds.height
                         + collection.adjustedContentInset.bottom)
        }

        private func clamp(_ y: CGFloat) -> CGFloat {
            guard let collection else { return y }
            let inset = collection.adjustedContentInset
            let maxY = max(-inset.top,
                           collection.contentSize.height - collection.bounds.height + inset.bottom)
            return min(max(y, -inset.top), maxY)
        }

        private func uiPosition(_ position: ChatFeedPosition) -> UICollectionView.ScrollPosition {
            switch position {
            case .bottom: return .bottom
            case .top:    return .top
            case .center: return .centeredVertically
            }
        }

        private func indexPath(for id: String) -> IndexPath? {
            guard let index = order.firstIndex(of: id) else { return nil }
            return IndexPath(item: index, section: 0)
        }

        // MARK: Кадр сообщения — для всплывающего меню

        /// Поля ячейки вычитаем: прежняя лента мерила пузырь без отступов списка,
        /// и меню раскладывается по такому же кадру.
        func windowFrame(forItem id: String) -> CGRect? {
            guard let collection, let window = collection.window,
                  let ip = indexPath(for: id),
                  let attrs = collection.layoutAttributesForItem(at: ip) else { return nil }
            let rect = collection.convert(attrs.frame, to: window)
            return rect.insetBy(dx: ChatFeedCollection.horizontalMargin,
                                dy: ChatFeedCollection.verticalMargin)
        }

        // MARK: Раскладка и прокрутка руками

        /// Раскладка коллекции: единственный честный момент, чтобы проверить,
        /// доехала ли прокрутка, и удержать ленту в конце, когда она там стоит.
        private func listDidLayout() {
            guard let collection else { return }
            // Страница может быть уложена с нулевой высотой (её ещё не показали):
            // считать по такой геометрии нечего, и попытки на неё тратить нельзя.
            guard collection.bounds.height > 1 else { return }
            if let (request, checks) = awaiting {
                if collection.isDragging || collection.isDecelerating || checks <= 0 {
                    awaiting = nil
                } else if let id = request.id, let ip = indexPath(for: id) {
                    let landed = applyExactOffset(for: ip, position: request.position)
                    awaiting = landed ? nil : (request, checks - 1)
                } else {
                    awaiting = nil
                }
                return
            }
            // Просьба, которую не удалось выполнить раньше (строки ещё не было):
            // пробуем на каждой раскладке, пока не выйдет или пока ленту не
            // тронут рукой. Это дешевле и честнее очереди таймеров.
            if runPendingRequest() { return }
            // Лента растёт (докрутились картинки, приехали строки), а человек
            // стоит в конце — держим конец. Под рукой не трогаем.
            guard stickToBottom, !collection.isDragging, !collection.isDecelerating else { return }
            let target = bottomOffset()
            if abs(collection.contentOffset.y - target) > 0.5 {
                collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            }
        }

        private func hostDidLayout() {
            // Размер ленты изменился (клавиатура, поворот, полоса закрепа).
            // Дальше всё сделает раскладка самой коллекции.
            collection?.setNeedsLayout()
        }

        /// Запомнить, где страница стоит: строка сверху экрана и на сколько она
        /// приподнята над кромкой.
        private func saveAnchor() {
            guard let collection, let store,
                  collection.bounds.height > 1, collection.contentSize.height > 1 else { return }
            if pinnedToBottom {
                store.save(ChatFeedAnchor(id: nil, delta: 0), for: pageKey)
                return
            }
            let top = collection.contentOffset.y + collection.adjustedContentInset.top
            guard let ip = collection.indexPathsForVisibleItems.sorted().first(where: {
                (collection.layoutAttributesForItem(at: $0)?.frame.maxY ?? 0) > top
            }), let attrs = collection.layoutAttributesForItem(at: ip),
                  ip.item < order.count else { return }
            store.save(ChatFeedAnchor(id: order[ip.item],
                                      delta: attrs.frame.minY - collection.contentOffset.y),
                       for: pageKey)
        }

        private func updateAtBottom() {
            guard let collection else { return }
            let maxOffset = collection.contentSize.height - collection.bounds.height
                + collection.adjustedContentInset.bottom
            let fits = collection.contentSize.height
                + collection.adjustedContentInset.top
                + collection.adjustedContentInset.bottom <= collection.bounds.height
            let atBottom = fits || collection.contentOffset.y >= maxOffset - 24
            pinnedToBottom = atBottom
            stickToBottom = fits || collection.contentOffset.y >= maxOffset - 2
            guard atBottom != reportedAtBottom else { return }
            reportedAtBottom = atBottom
            // Через цикл: считается это в том числе во время раскладки, а менять
            // состояние SwiftUI прямо посреди его же обновления нельзя.
            DispatchQueue.main.async { [onAtBottomChange] in onAtBottomChange(atBottom) }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateAtBottom()
            saveAnchor()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            awaiting = nil
            store?.dropRequest(for: pageKey)
            onUserScroll()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let (request, _) = awaiting else { return }
            awaiting = nil
            // Доводка после анимации: без анимации и на считаные точки — её не
            // видно. Это единственный повтор во всей ленте.
            if let id = request.id, let ip = indexPath(for: id) {
                applyExactOffset(for: ip, position: request.position)
            } else if let collection {
                let target = bottomOffset()
                if abs(collection.contentOffset.y - target) > 0.5 {
                    collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
                }
            }
            updateAtBottom()
        }

        @objc private func handleTap() {
            onTap()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
