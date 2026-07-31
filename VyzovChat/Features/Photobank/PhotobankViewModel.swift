import Foundation
import Combine

/// Состояние фотобанка: выбранные теги, фильтры и текущая выборка фото.
@MainActor
final class PhotobankViewModel: ObservableObject {
    @Published private(set) var items: [PhotobankItemDTO] = []
    @Published private(set) var facets: [PhotobankFacetDTO] = []
    @Published private(set) var counts = PhotobankCountsDTO(total: 0, newCount: 0)
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false

    // Фильтры
    @Published var selected: Set<String> = []
    @Published var op: PhotobankOp = .and
    @Published var eventId: Int? = nil
    @Published var onlyNew = false
    @Published var tagQuery = ""

    private let service: PhotobankServicing
    /// Токен последнего запроса выборки — чтобы поздний ответ не перезаписал свежий.
    private var searchToken = 0

    init(service: PhotobankServicing) { self.service = service }

    var hasFilters: Bool { !selected.isEmpty || eventId != nil || onlyNew }

    /// Мероприятия из текущей выборки — для выпадающего фильтра.
    var events: [(id: Int, name: String)] {
        var map: [Int: String] = [:]
        for it in items { if let id = it.event_id { map[id] = it.event_name ?? "—" } }
        return map.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Подсказки тегов по строке поиска (как в вебе: клик = добавить в фильтр).
    var tagSuggestions: [PhotobankFacetDTO] {
        let q = tagQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return facets
            .filter { !selected.contains($0.tag) && $0.tag.lowercased().contains(q) }
            .sorted { $0.count > $1.count }
            .prefix(12)
            .map { $0 }
    }

    /// Первая полная загрузка: облако тегов + счётчики + выборка.
    func loadAll() async {
        isLoading = true
        async let f = service.facets()
        async let c = service.counts()
        let searched = await runSearch()
        if let facets = await f { self.facets = facets }
        counts = await c
        if let searched { items = searched }
        isLoading = false
        didLoad = true
    }

    /// Перезапросить только выборку (после смены фильтра).
    func refreshItems() async {
        isLoading = true
        if let found = await runSearch() { items = found }
        isLoading = false
    }

    /// Обновить всё (pull-to-refresh / событие disk:change).
    ///
    /// Неудачный запрос НЕ затирает показанное: раньше сбой возвращал пустой
    /// список, и фотобанк опустошался прямо во время прокрутки.
    func reloadFacetsAndItems() async {
        async let f = service.facets()
        async let c = service.counts()
        let searched = await runSearch()
        if let facets = await f { self.facets = facets }
        counts = await c
        if let searched { items = searched }
    }

    /// `nil` — либо запрос не удался, либо ответ устарел: в обоих случаях
    /// показанное трогать нельзя.
    private func runSearch() async -> [PhotobankItemDTO]? {
        searchToken &+= 1
        let token = searchToken
        let result = await service.search(tags: Array(selected), op: op,
                                          event: eventId, onlyNew: onlyNew)
        // Если за время запроса фильтры сменились — отбрасываем устаревший ответ.
        guard token == searchToken else { return nil }
        return result
    }

    // MARK: - Действия с фильтрами

    func toggle(_ tag: String) {
        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
        Task { await refreshItems() }
    }

    func pick(_ tag: String) {
        selected.insert(tag)
        tagQuery = ""
        Task { await refreshItems() }
    }

    func setEvent(_ id: Int?) {
        eventId = id
        Task { await refreshItems() }
    }

    func setOp(_ newOp: PhotobankOp) {
        op = newOp
        if selected.count >= 2 { Task { await refreshItems() } }
    }

    func setOnlyNew(_ value: Bool) {
        onlyNew = value
        Task { await refreshItems() }
    }

    func clearFilters() {
        selected.removeAll()
        eventId = nil
        onlyNew = false
        Task { await refreshItems() }
    }

    // MARK: - Правки тегов (админ)

    func addTag(_ tag: String, to item: PhotobankItemDTO) async {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        await service.addTag(itemId: item.id, tag: t)
        await reloadFacetsAndItems()
    }

    func removeTag(_ tag: String, from item: PhotobankItemDTO) async {
        await service.removeTag(itemId: item.id, tag: tag)
        await reloadFacetsAndItems()
    }

    /// Пометить как просмотренное (админ открыл «новое» фото).
    func markSeen(_ item: PhotobankItemDTO) async {
        guard item.isNew else { return }
        await service.markModerated(itemId: item.id)
        counts = PhotobankCountsDTO(total: counts.total, newCount: max(0, counts.newCount - 1))
    }

    /// Актуальная версия item из выборки (после reload тегов).
    func current(_ item: PhotobankItemDTO) -> PhotobankItemDTO {
        items.first { $0.id == item.id } ?? item
    }

    /// Подсказки тегов для ручной разметки: словарь ИИ-тегов + уже известные теги.
    func taxonomySuggestions() async -> [String] {
        let tax = await service.taxonomy()
        let set = Set(tax).union(facets.map { $0.tag })
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
