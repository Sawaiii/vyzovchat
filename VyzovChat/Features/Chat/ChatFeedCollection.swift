import SwiftUI
import UIKit

/// Лента чата на `UICollectionView`. Строки остаются теми же SwiftUI-вью
/// (`MessageBubble`, `DaySeparator`, `UploadingTile`) — меняется только то, что
/// их держит и прокручивает.
///
/// Зачем вообще: в ленивом списке SwiftUI прокрутка к сообщению целится по
/// прикидке высот, а построенные по дороге строки эту прикидку меняют — переход
/// не доезжал. Лечилось «доводчиками»: одна и та же прокрутка повторялась до
/// семи раз (16…750 мс), и это ровно то, что видно как рывки. Здесь доводить
/// нечего: у коллекции есть реальные атрибуты уже уложенных ячеек, и нужное
/// смещение считается арифметикой — один проход, без таймеров.
///
/// Что ещё чинится само собой:
/// - **приход сообщения не двигает ленту.** В прижатой к низу SwiftUI-ленте
///   новое сообщение подпирало содержимое снизу; здесь оно просто дописывается
///   в конец, и если человек читает середину, у него ничего не уезжает.
/// - **клавиатура.** Пока лента внизу, она внизу и остаётся: пересчёт идёт в
///   `layoutSubviews`, а не гонкой анимаций.
struct ChatFeedCollection: UIViewRepresentable {
    /// Строки ленты вместе со всем, от чего зависит их вид: сравнением строк и
    /// решается, какую ячейку перерисовать.
    let rows: [ChatFeedRow]
    /// Сборка содержимого строки. Зовётся только для видимых ячеек.
    let content: (ChatFeedRow) -> AnyView
    /// Меняется, когда меняется общее для всех строк (карта упоминаний) —
    /// тогда перерисовываем всё видимое.
    var revision: Int = 0
    /// Куда себя записать, чтобы чат мог попросить прокрутку и кадр сообщения.
    let registry: ChatFeedRegistry
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
        context.coordinator.attach(to: host)
        registry.register(context.coordinator, for: pageKey)
        return host
    }

    func updateUIView(_ host: ChatFeedHostView, context: Context) {
        let coordinator = context.coordinator
        coordinator.content = content
        coordinator.onAtBottomChange = onAtBottomChange
        coordinator.onUserScroll = onUserScroll
        coordinator.onTap = onTap
        registry.register(coordinator, for: pageKey)
        coordinator.apply(rows: rows, revision: revision)
    }

    /// Лента занимает всё предложенное место — как и прежняя прокрутка. Без
    /// этого размер брался бы у `UIView`, у которого его нет, и в стопке с
    /// шапкой и строкой ввода лента могла бы схлопнуться.
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
/// каждое изменение модели (включая набор текста в поле ввода), и это было
/// заметно. Здесь строка — значение, и ячейка перерисовывается ровно тогда,
/// когда это значение изменилось.
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
        scale = 0.9
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.12)) { scale = 1 }
    }
}

/// Ручка пружины. Ссылка, а не замыкание в параметре: `MessageBubble` хранит
/// обработчик удержания у себя, значит тот обязан быть убегающим, — а замыкание,
/// отданное параметром, таким быть не может.
final class PressPopTrigger {
    var fire: () -> Void = {}
}

// MARK: - Доступ из SwiftUI

enum ChatFeedPosition {
    case bottom, top, center
}

/// Куда чат складывает ленты страниц (у пейджера тем их несколько) и через что
/// потом просит прокрутку. Ссылки слабые: страница живёт, пока живёт её вью.
final class ChatFeedRegistry {
    private var pages: [String: WeakBox] = [:]

    private struct WeakBox {
        weak var coordinator: ChatFeedCollection.Coordinator?
    }

    func register(_ coordinator: ChatFeedCollection.Coordinator, for key: String) {
        pages[key] = WeakBox(coordinator: coordinator)
    }

    subscript(key: String) -> ChatFeedCollection.Coordinator? {
        pages[key]?.coordinator
    }
}

// MARK: - Хост

/// Вью-обёртка: держит коллекцию и сообщает, что её размеры пересчитали.
/// Клавиатура, поворот, появление полосы закрепа — всё приходит сюда, и если
/// лента стояла в конце, она там и остаётся.
final class ChatFeedHostView: UIView {
    var onLayout: () -> Void = {}

    override func layoutSubviews() {
        super.layoutSubviews()
        subviews.first?.frame = bounds
        onLayout()
    }
}

// MARK: - Координатор

extension ChatFeedCollection {

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        private var collection: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var order: [String] = []
        private var rowsById: [String: ChatFeedRow] = [:]
        private var revision = 0

        var content: (ChatFeedRow) -> AnyView = { _ in AnyView(EmptyView()) }
        var onAtBottomChange: (Bool) -> Void = { _ in }
        var onUserScroll: () -> Void = {}
        var onTap: () -> Void = {}

        /// Лента стоит в конце — значит, растёт вниз вместе с новыми строками.
        private var pinnedToBottom = true
        private var reportedAtBottom = true
        /// Прокрутка, которую попросили до того, как строки доехали.
        private var pending: (id: String?, position: ChatFeedPosition)?
        /// Что доводить после анимированной прокрутки: штатный метод целится по
        /// прикидке, и на пару точек промахивается. Доводим один раз и молча.
        private var correction: (id: String?, position: ChatFeedPosition)?

        // MARK: Сборка

        func attach(to host: ChatFeedHostView) {
            let view = UICollectionView(frame: host.bounds, collectionViewLayout: Self.makeLayout())
            view.backgroundColor = .clear
            view.allowsSelection = false
            view.alwaysBounceVertical = true
            // Клавиатура убирается тем же движением, что и в прежней ленте.
            view.keyboardDismissMode = .interactive
            // Отступы держим сами: автоматический учёт безопасной области здесь
            // лишний — лента и так стоит между шапкой и строкой ввода.
            view.contentInsetAdjustmentBehavior = .never
            view.contentInset = UIEdgeInsets(top: Spacing.s, left: 0, bottom: Spacing.s, right: 0)
            view.verticalScrollIndicatorInsets = view.contentInset
            // Предзагрузка ячеек с SwiftUI-содержимым только мешает: она строит
            // хостинги заранее и меняет высоты за кадром.
            view.isPrefetchingEnabled = false
            view.delegate = self

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
        }

        func detach() {
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
            guard orderChanged || !changed.isEmpty else { return }
            order = newOrder

            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(newOrder)
            if !changed.isEmpty {
                snapshot.reconfigureItems(changed.filter { map[$0] != nil })
            }

            let shouldStick = pinnedToBottom
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                if let pending = self.pending {
                    self.pending = nil
                    self.perform(id: pending.id, position: pending.position, animated: false)
                } else if shouldStick {
                    // Лента стояла в конце — там и остаётся. Если человек читал
                    // середину, offset не трогаем вовсе: новые строки дописаны
                    // ниже и на его место не влияют.
                    self.scrollToBottom(animated: false)
                }
            }
        }

        // MARK: Прокрутка

        func scrollToBottom(animated: Bool) {
            perform(id: nil, position: .bottom, animated: animated)
        }

        func scroll(to id: String, position: ChatFeedPosition, animated: Bool) {
            perform(id: id, position: position, animated: animated)
        }

        private func perform(id: String?, position: ChatFeedPosition, animated: Bool) {
            guard let collection else { return }
            if let id, indexPath(for: id) == nil {
                // Строка ещё не доехала — прокрутим, как только придёт.
                pending = (id, position)
                return
            }
            collection.layoutIfNeeded()

            if animated {
                correction = (id, position)
                if let id, let ip = indexPath(for: id) {
                    collection.scrollToItem(at: ip, at: uiPosition(position), animated: true)
                } else {
                    collection.setContentOffset(CGPoint(x: 0, y: bottomOffset()), animated: true)
                }
                return
            }

            if let id, let ip = indexPath(for: id) {
                // Первый проход штатным методом: он по дороге укладывает ячейки,
                // и после него атрибуты цели уже настоящие.
                collection.scrollToItem(at: ip, at: uiPosition(position), animated: false)
                collection.layoutIfNeeded()
                applyExactOffset(for: ip, position: position)
            } else {
                collection.setContentOffset(CGPoint(x: 0, y: bottomOffset()), animated: false)
                collection.layoutIfNeeded()
                let corrected = bottomOffset()
                if abs(collection.contentOffset.y - corrected) > 0.5 {
                    collection.setContentOffset(CGPoint(x: 0, y: corrected), animated: false)
                }
            }
            updateAtBottom()
        }

        /// Точное смещение по реальным атрибутам уложенной ячейки.
        private func applyExactOffset(for ip: IndexPath, position: ChatFeedPosition) {
            guard let collection,
                  let attrs = collection.layoutAttributesForItem(at: ip) else { return }
            let height = collection.bounds.height
            let inset = collection.adjustedContentInset
            let raw: CGFloat
            switch position {
            case .top:    raw = attrs.frame.minY - inset.top
            case .center: raw = attrs.frame.midY - height / 2
            case .bottom: raw = attrs.frame.maxY - height + inset.bottom
            }
            let target = clamp(raw)
            if abs(collection.contentOffset.y - target) > 0.5 {
                collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            }
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

        /// Где строка лежит на экране (координаты окна). По ней чат раскладывает
        /// меню рядом с сообщением. Поля ячейки вычитаем: прежняя SwiftUI-лента
        /// мерила пузырь без отступов списка, и меню считает так же.
        func windowFrame(forItem id: String) -> CGRect? {
            guard let collection, let window = collection.window,
                  let ip = indexPath(for: id),
                  let attrs = collection.layoutAttributesForItem(at: ip) else { return nil }
            let rect = collection.convert(attrs.frame, to: window)
            return rect.insetBy(dx: ChatFeedCollection.horizontalMargin,
                                dy: ChatFeedCollection.verticalMargin)
        }

        // MARK: Прокрутка руками

        private func hostDidLayout() {
            guard let collection else { return }
            // Размер ленты изменился (клавиатура, поворот, полоса закрепа).
            // Стояли в конце — там и остаёмся; под рукой человека не трогаем.
            guard pinnedToBottom, !collection.isDragging, !collection.isDecelerating else { return }
            scrollToBottom(animated: false)
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
            guard atBottom != reportedAtBottom else { return }
            reportedAtBottom = atBottom
            // Через цикл: считается это в том числе во время раскладки, а менять
            // состояние SwiftUI прямо посреди его же обновления нельзя.
            DispatchQueue.main.async { [onAtBottomChange] in onAtBottomChange(atBottom) }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateAtBottom()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            correction = nil
            pending = nil
            onUserScroll()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let correction else { return }
            self.correction = nil
            // Доводка после анимации: без анимации и на считаные точки — её не
            // видно. Это единственный повтор во всей ленте.
            if let id = correction.id, let ip = indexPath(for: id) {
                applyExactOffset(for: ip, position: correction.position)
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
