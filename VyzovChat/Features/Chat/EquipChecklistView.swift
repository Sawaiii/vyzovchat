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
    /// Отметили позицию — чтобы чат перечитал счётчики этапов.
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [EquipmentDTO] = []
    @State private var isLoading = true
    @State private var busyId: Int?
    @State private var errorText: String?
    // Добавление позиции руками: в CRM попадает не всё, а грузить надо всё.
    @State private var newName = ""
    @State private var newQty = ""
    @State private var adding = false

    private var checked: Int { items.filter { $0.isChecked(kind) }.count }

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
                        ForEach(items) { item in row(item) }
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
            // Не «только просмотр», а почему: галочки ставит склад, и без
            // объяснения неактивные строки выглядят как поломка.
            if !canCheck {
                Text("отмечает кладовщик").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func row(_ item: EquipmentDTO) -> some View {
        let on = item.isChecked(kind)
        return Button {
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
                }
                Spacer(minLength: Spacing.xs)
                if busyId == item.id { ProgressView().tint(Theme.accent).scaleEffect(0.7) }
            }
            .padding(Spacing.s)
            .glass(cornerRadius: Theme.cornerSmall, elevated: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canCheck || busyId != nil)
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
            errorText = "Не удалось отметить позицию. Проверьте связь и попробуйте ещё раз."
            Haptics.warning()
        }
    }
}
