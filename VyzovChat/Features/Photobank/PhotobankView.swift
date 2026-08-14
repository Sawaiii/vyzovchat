import SwiftUI

/// Фотобанк — теговая библиотека (вкладка «Фотобанк» внутри Диска). Менеджеры ищут
/// оборудование по тегам (ИИ-разметка + ручные), фильтруют по мероприятию, открывают
/// в полноэкранном просмотре. Админ правит теги и видит «новые» (непросмотренные).
/// Встраивается в DiskView без собственного NavigationStack — навигацию даёт Диск.
struct PhotobankBrowser: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @StateObject private var vm = PhotobankViewModel(service: Backend.photobank())

    @State private var preview: MediaPreview?
    @State private var editing: PhotobankItemDTO?
    /// Фото, которое убираем из фотобанка (спрашиваем подтверждение).
    @State private var removing: PhotobankItemDTO?
    @FocusState private var searchFocused: Bool

    // Отбор для скачивания архивом
    @State private var zipIds: Set<Int> = []
    @State private var zipURL: URL?
    @State private var zipping = false

    private var isAdmin: Bool { session.currentUser?.isAdmin ?? false }
    private let grid = [GridItem(.adaptive(minimum: 108), spacing: 6)]

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                header
                contentArea
                if !zipIds.isEmpty { zipBar }
            }
        }
        .task { if !vm.didLoad { await vm.loadAll() } }
        .onReceive(RealtimeService.shared.diskChanged) { _ in
            Task { await vm.reloadFacetsAndItems() }
        }
        .fullScreenCover(item: $preview) { p in
            MediaPager(items: p.items, startIndex: p.index)
        }
        .sheet(item: $editing) { item in
            PhotobankTagEditor(item: vm.current(item), vm: vm)
        }
        .confirmationDialog("Убрать фото из фотобанка?",
                            isPresented: .init(get: { removing != nil },
                                               set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                if let item = removing { Task { await vm.remove(item) } }
                removing = nil
            }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: {
            Text("В чате мероприятия фото останется — пропадёт только из фотобанка.")
        }
    }

    // MARK: - Шапка с поиском и фильтрами

    private var header: some View {
        VStack(spacing: Spacing.s) {
            searchField
            if searchFocused && !vm.tagSuggestions.isEmpty {
                suggestions
            } else {
                if !vm.selected.isEmpty { selectedChips }
                facetStrip
            }
            controlsRow
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Поиск по тегам (мебель, шатёр…)", text: $vm.tagQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    if let first = vm.tagSuggestions.first { vm.pick(first.tag); searchFocused = false }
                }
            if !vm.tagQuery.isEmpty {
                Button { vm.tagQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 10)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    /// Выпадающие подсказки тегов под строкой поиска.
    private var suggestions: some View {
        VStack(spacing: 0) {
            ForEach(vm.tagSuggestions) { f in
                Button {
                    vm.pick(f.tag); searchFocused = false
                } label: {
                    HStack {
                        Text(f.tag).font(Typography.callout).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(f.count)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if f.id != vm.tagSuggestions.last?.id { Divider().opacity(0.2) }
            }
        }
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    /// Выбранные теги — чипами с крестиком.
    private var selectedChips: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(vm.selected).sorted(), id: \.self) { tag in
                Button { vm.toggle(tag) } label: {
                    HStack(spacing: 4) {
                        Text(tag).font(.footnote.weight(.medium))
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.textOnAccent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Облако тегов: ДВА ряда, прокрутка только влево-вправо (горизонтальный
    /// ScrollView + LazyHGrid по 2 строкам). Так видно больше тегов, и нет
    /// вертикальной прокрутки/обновления, которые тут не нужны.
    private static let facetRowH: CGFloat = 32
    private var facetStrip: some View {
        let rows = [GridItem(.fixed(Self.facetRowH), spacing: 6),
                    GridItem(.fixed(Self.facetRowH), spacing: 6)]
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 6) {
                ForEach(vm.facets.filter { !vm.selected.contains($0.tag) }) { f in
                    Button { vm.toggle(f.tag) } label: {
                        HStack(spacing: 4) {
                            Text(f.tag).font(.footnote).lineLimit(1)
                            Text("\(f.count)").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: Self.facetRowH)
                        .glass(cornerRadius: Self.facetRowH / 2, elevated: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // Высота ровно под два ряда и никакого отскока: облако тегов ездит
        // только вбок. «Потяни-обнови» сюда не попадает — он висит на сетке
        // фото, а не на экране целиком.
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .frame(height: Self.facetRowH * 2 + 6)
    }

    /// Строка фильтров: мероприятие, И/ИЛИ, «новые» (админ), сброс.
    private var controlsRow: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
                Button("Все мероприятия") { vm.setEvent(nil) }
                ForEach(vm.events, id: \.id) { e in
                    Button(e.name) { vm.setEvent(e.id) }
                }
            } label: {
                filterChip(icon: "calendar", text: eventTitle, active: vm.eventId != nil)
            }

            if vm.selected.count >= 2 {
                Picker("", selection: Binding(get: { vm.op }, set: { vm.setOp($0) })) {
                    Text("Все").tag(PhotobankOp.and)
                    Text("Любой").tag(PhotobankOp.or)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }

            if isAdmin && vm.counts.newCount > 0 {
                Button { vm.setOnlyNew(!vm.onlyNew) } label: {
                    filterChip(icon: "sparkles", text: "Новые \(vm.counts.newCount)", active: vm.onlyNew)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if vm.hasFilters {
                Button("Сбросить") { vm.clearFilters() }
                    .font(.footnote).foregroundStyle(Theme.accent)
            }
        }
    }

    private func filterChip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.footnote).lineLimit(1)
        }
        .foregroundStyle(active ? Theme.textOnAccent : Theme.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            Group {
                if active { Capsule().fill(Theme.accent) }
                else { Capsule().fill(Theme.panel2) }
            }
        )
    }

    private var eventTitle: String {
        if let id = vm.eventId {
            return vm.events.first { $0.id == id }?.name ?? "Мероприятие"
        }
        return "Все мероприятия"
    }

    // MARK: - Сетка / состояния

    @ViewBuilder
    private var contentArea: some View {
        if vm.isLoading && vm.items.isEmpty {
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        } else if vm.items.isEmpty {
            Spacer()
            EmptyState(icon: "photo.on.rectangle.angled",
                       title: vm.hasFilters ? "Ничего не найдено" : "Фотобанк пуст",
                       message: vm.hasFilters
                            ? "Под выбранные теги/фильтры фото нет. Попробуйте другой тег."
                            : "Здесь появятся размеченные фото с мероприятий.")
            Spacer()
        } else {
            ScrollView {
                HStack {
                    Text("Фото: \(vm.items.count)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, Spacing.xs)

                LazyVGrid(columns: grid, spacing: 6) {
                    ForEach(vm.items) { item in cell(item) }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, Spacing.xs)
            }
            // Pull-to-refresh только на сетке фото — не на шапке/тегах.
            .refreshable { await vm.reloadFacetsAndItems() }
        }
    }

    private func cell(_ item: PhotobankItemDTO) -> some View {
        Button { open(item) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        CachedAsyncImage(url: item.previewURL) { $0.resizable().scaledToFill() }
                            placeholder: { Theme.panel2 }
                    )
                    .overlay(alignment: .topLeading) {
                        if item.isNew && isAdmin {
                            Text("🆕").font(.caption2)
                                .padding(4)
                                .background(.black.opacity(0.35), in: Capsule())
                                .padding(4)
                        }
                    }
                    // Клиент запретил использовать съёмку — предупреждение прямо
                    // на кадре, чтобы его не утащили в рекламу по невнимательности.
                    .overlay(alignment: .bottom) {
                        if item.restricted == true { restrictedBadge }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(tagline(item))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isAdmin {
                Button { editing = item } label: { Label("Изменить теги", systemImage: "tag") }
            }
            Button { toggleForZip(item) } label: {
                Label(zipIds.contains(item.id) ? "Убрать из архива" : "Добавить в архив",
                      systemImage: zipIds.contains(item.id) ? "minus.circle" : "plus.circle")
            }
            if let url = item.imageURL {
                ShareLink(item: url) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            }
            if isAdmin {
                // Убирает только из фотобанка: в чате мероприятия фото остаётся,
                // и вернуть его можно повторным отбором.
                Button(role: .destructive) { removing = item } label: {
                    Label("Убрать из фотобанка", systemImage: "trash")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if zipIds.contains(item.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .background(Circle().fill(.black.opacity(0.3)))
                    .padding(6)
            }
        }
    }

    /// Отобранное для архива. Сервер собирает zip сам и отдаёт файлом —
    /// скачивать пачку по одному фото было бы мучением.
    private func toggleForZip(_ item: PhotobankItemDTO) {
        if zipIds.contains(item.id) { zipIds.remove(item.id) } else { zipIds.insert(item.id) }
        zipURL = nil
        Haptics.selection()
    }

    private var zipBar: some View {
        HStack(spacing: Spacing.s) {
            Text("Выбрано: \(zipIds.count)")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Снять") { zipIds.removeAll(); zipURL = nil }
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if let zipURL {
                ShareLink(item: zipURL) {
                    Label("Сохранить архив", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                }
            } else {
                Button {
                    Task { await makeZip() }
                } label: {
                    Label(zipping ? "Готовим…" : "Скачать архивом", systemImage: "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                }
                .disabled(zipping)
            }
        }
        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
        .background(Theme.panel)
    }

    private func makeZip() async {
        zipping = true
        defer { zipping = false }
        zipURL = try? await Backend.photobank().zip(ids: Array(zipIds))
        if zipURL != nil { Haptics.success() } else { Haptics.warning() }
    }

    /// Красная плашка «нельзя использовать» поверх кадра.
    private var restrictedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 8))
            Text("НЕЛЬЗЯ ИСПОЛЬЗОВАТЬ")
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Theme.danger)
    }

    private func tagline(_ item: PhotobankItemDTO) -> String {
        let tags = item.tagList.prefix(3).map(\.tag)
        if !tags.isEmpty { return tags.joined(separator: ", ") }
        return item.event_name ?? "без тегов"
    }

    private func open(_ item: PhotobankItemDTO) {
        if isAdmin && item.isNew { Task { await vm.markSeen(item) } }
        let atts = vm.items.map { i in
            Message.Attachment(id: String(i.id), remoteURL: i.imageURL,
                               fileName: i.event_name, sizeBytes: nil,
                               isVideo: false, isFile: false)
        }
        let idx = vm.items.firstIndex { $0.id == item.id } ?? 0
        preview = MediaPreview(items: atts, index: idx)
    }
}
