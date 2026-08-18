import SwiftUI

/// Чеклист оборудования: что грузим в машину и что вернули на склад.
///
/// Список один — позиции мероприятия, — а отметки у погрузки и приёмки свои.
/// Отмечает кладовщик или админ чата; остальные видят состояние, но нажать
/// не могут (сервер им всё равно откажет).
struct EquipChecklistView: View {
    let dealId: String
    let kind: EquipCheckKind
    /// Можно ли ставить галочки.
    let canCheck: Bool
    /// Можно ли заводить и убирать позиции — это право админа чата.
    var canEdit: Bool = false
    /// Можно ли фиксировать претензию по позиции (`me_rights.claims`).
    var canClaim: Bool = false
    /// Склады этого человека (справочник Tony): его группа стоит первой и
    /// раскрыта. Позиций в заказе бывает под двадцать, а грузит он только свои.
    var myWarehouses: [String] = []
    /// Отметили позицию — чтобы чат перечитал счётчики этапов.
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [EquipmentDTO] = []
    @State private var isLoading = true
    @State private var busyId: Int?
    @State private var errorText: String?
    /// Позиция, по которой заводим претензию прямо из чеклиста приёма.
    @State private var claiming: EquipmentDTO?
    // Добавление позиции руками: в CRM попадает не всё, а грузить надо всё.
    @State private var newName = ""
    @State private var newQty = ""
    @State private var adding = false

    /// Какие склады человек свернул руками. По умолчанию раскрыт свой, а если
    /// складов за человеком не числится — все.
    @State private var expandedOverride: [String: Bool] = [:]

    private var checked: Int { items.filter { $0.isChecked(kind) }.count }

    /// Позиции, разложенные по складам: с миграции 00075 сервер шлёт, откуда что
    /// едет. Свой склад — первым, остальные видны, но свёрнуты: отметить чужую
    /// позицию иногда всё-таки надо, прятать её совсем нельзя.
    private struct WarehouseGroup: Identifiable {
        let id: String
        let title: String
        let isMine: Bool
        let items: [EquipmentDTO]
    }

    private var groups: [WarehouseGroup] {
        var order: [String] = []
        var byKey: [String: [EquipmentDTO]] = [:]
        for item in items {
            let key = item.warehouseKey
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        let list = order.map { key -> WarehouseGroup in
            let group = byKey[key] ?? []
            return WarehouseGroup(id: key,
                                  title: group.first?.warehouseTitle ?? "Без склада",
                                  isMine: !key.isEmpty && myWarehouses.contains(key),
                                  items: group)
        }
        // Свой склад наверх, остальные — в порядке сервера. Сортировка в Swift
        // неустойчивая, поэтому порядок внутри держим индексом.
        return list.enumerated().sorted { a, b in
            a.element.isMine == b.element.isMine ? a.offset < b.offset : a.element.isMine
        }.map { $0.element }
    }

    /// Разбивку показываем, только когда складов правда несколько: на одном она
    /// превращается в лишний заголовок над списком.
    private var showsWarehouses: Bool { groups.count > 1 }

    private func isExpanded(_ group: WarehouseGroup) -> Bool {
        expandedOverride[group.id] ?? (myWarehouses.isEmpty ? true : group.isMine)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground().ignoresSafeArea()
                content
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Чеклист", isPresented: .init(get: { errorText != nil },
                                                 set: { if !$0 { errorText = nil } })) {
                Button("Понятно", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            // Претензия прямо отсюда: на приёмке недостача и бой видны как раз в
            // тот момент, когда по списку идут, — уходить за этим в другой экран
            // значит забыть.
            .confirmationDialog(claiming?.name ?? "Претензия",
                                isPresented: .init(get: { claiming != nil },
                                                   set: { if !$0 { claiming = nil } }),
                                titleVisibility: .visible) {
                Button("Повреждено") { Task { await fileClaim(kind: "damage") } }
                Button("Утеряно") { Task { await fileClaim(kind: "loss") } }
                Button("Отмена", role: .cancel) { claiming = nil }
            } message: {
                Text("Претензия попадёт в список мероприятия и в подтему «Претензия».")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(Theme.accent)
        } else {
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    if items.isEmpty {
                        EmptyState(icon: "shippingbox",
                                   title: "Оборудования нет",
                                   message: canEdit
                                        ? "К мероприятию не привязано ни одной позиции. Добавьте их ниже."
                                        : "К мероприятию не привязано ни одной позиции — отмечать нечего.")
                    } else {
                        header
                        ForEach(groups) { group in
                            if showsWarehouses {
                                warehouseHeader(group)
                                if isExpanded(group) {
                                    ForEach(group.items) { item in row(item) }
                                }
                            } else {
                                ForEach(group.items) { item in row(item) }
                            }
                        }
                    }
                    if canEdit { addRow }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
            }
        }
    }

    /// Своя позиция: из CRM приезжает не всё, а в машину грузится всё.
    private var addRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("ДОБАВИТЬ ПОЗИЦИЮ")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Spacing.xs) {
                TextField("Название", text: $newName)
                    .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                    .background(Theme.panel2, in: Capsule())
                TextField("шт.", text: $newQty)
                    .keyboardType(.numberPad)
                    .frame(width: 56)
                    .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                    .background(Theme.panel2, in: Capsule())
                Button { Task { await add() } } label: {
                    if adding {
                        ProgressView().tint(Theme.accent).frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "plus.circle.fill").font(.title3)
                            .foregroundStyle(canAdd ? Theme.accent : Theme.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canAdd || adding)
            }
        }
        .padding(.top, Spacing.s)
    }

    private var canAdd: Bool { !newName.trimmingCharacters(in: .whitespaces).isEmpty }

    private func add() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        adding = true
        defer { adding = false }
        do {
            _ = try await Backend.eventInfo().addEquipment(dealId: dealId, name: name,
                                                           qty: Int(newQty))
            newName = ""
            newQty = ""
            Haptics.success()
            await load()
            // Счётчики этапов считают позиции — новая меняет «6/6» на «6/7».
            onChanged()
        } catch {
            errorText = "Не удалось добавить позицию. Заводить оборудование может админ чата."
            Haptics.warning()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: kind.icon).foregroundStyle(Theme.accent)
            Text(checked == items.count ? "Всё отмечено" : "Отмечено \(checked) из \(items.count)")
                .font(Typography.callout)
                .foregroundStyle(checked == items.count ? Theme.success : Theme.textPrimary)
            Spacer()
            // Не «только просмотр», а почему: у каждой половины чеклиста своя
            // сторона, и без объяснения неактивные строки выглядят как поломка.
            if !canCheck {
                Text(kind.owner).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    /// Заголовок склада: свой подсвечен, чужие приглушены и свёрнуты.
    private func warehouseHeader(_ group: WarehouseGroup) -> some View {
        let open = isExpanded(group)
        let done = group.items.filter { $0.isChecked(kind) }.count
        return Button {
            withAnimation(.smooth(duration: 0.2)) { expandedOverride[group.id] = !open }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(group.title + (group.isMine ? " · ваш склад" : ""))
                    .font(.system(size: 11, weight: group.isMine ? .semibold : .regular))
                    .foregroundStyle(group.isMine ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                Text("\(done) из \(group.items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(done == group.items.count ? Theme.success : Theme.textSecondary)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// Строка позиции.
    ///
    /// Галочка и кнопка претензии — две разные кнопки, поэтому вся строка не может
    /// быть одной большой Button: вложенная в её label кнопка нажатий не получает.
    private func row(_ item: EquipmentDTO) -> some View {
        let on = item.isChecked(kind)
        return HStack(spacing: Spacing.s) {
            Button {
                Task { await toggle(item) }
            } label: {
                HStack(spacing: Spacing.s) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(on ? Theme.success.opacity(0.6) : Theme.textSecondary.opacity(0.5), lineWidth: 1)
                        if on {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.success.opacity(0.18))
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.success)
                        }
                    }
                    .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.qty.map { "\(item.name) · \($0) шт" } ?? item.name)
                            .font(Typography.callout)
                            .foregroundStyle(on ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(2)
                        if let who = item.checkedBy(kind) {
                            Text("отметил: \(who)").font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // Претензия по позиции: на приёмке важно видеть, по чему
                        // вопрос уже есть, — иначе заводят вторую такую же.
                        if let claim = item.claimTitle {
                            Text(claim + (item.claim_note.map { ": \($0)" } ?? ""))
                                .font(.system(size: 9))
                                .foregroundStyle(item.claim_status == "closed" ? Theme.textSecondary : Theme.danger)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: Spacing.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCheck || busyId != nil)

            // Претензию заводим там, где недостачу и видно: на приёмке и на
            // сверке после демонтажа.
            if canClaim, kind == .returned || kind == .dismantled, !item.hasClaim, busyId == nil {
                Button { claiming = item } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            if busyId == item.id { ProgressView().tint(Theme.accent).scaleEffect(0.7) }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    /// Зафиксировать претензию по позиции из чеклиста приёма.
    private func fileClaim(kind claimKind: String) async {
        guard let item = claiming else { return }
        claiming = nil
        busyId = item.id
        defer { busyId = nil }
        do {
            try await Backend.eventInfo().createClaim(
                dealId: dealId,
                items: [CreateClaimRequest.Item(position: item.name, kind: claimKind,
                                                note: "", qty: item.qty)])
            Haptics.success()
            await load()
        } catch {
            errorText = "Не удалось зафиксировать претензию. Это право админа чата, старшего или кладовщика."
            Haptics.warning()
        }
    }

    private func load() async {
        items = await Backend.eventInfo().equipment(dealId: dealId)
        isLoading = false
    }

    private func toggle(_ item: EquipmentDTO) async {
        guard canCheck else { return }
        busyId = item.id
        defer { busyId = nil }
        do {
            try await StagesService.check(dealId: dealId, itemId: item.id,
                                          kind: kind, on: !item.isChecked(kind))
            Haptics.selection()
            await load()
            onChanged()
        } catch {
            // Свою половину отмечает только своя сторона — отметить за другого
            // нельзя, в этом и смысл двойного чеклиста загрузки.
            if case let APIError.http(_, message) = error, message == "check_forbidden" {
                errorText = "Эту половину чеклиста отмечает другая сторона: \(kind.owner)."
            } else {
                errorText = "Не удалось отметить позицию. Проверьте связь и попробуйте ещё раз."
            }
            Haptics.warning()
        }
    }
}
