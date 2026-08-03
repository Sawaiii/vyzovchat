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
    /// Отметили позицию — чтобы чат перечитал счётчики этапов.
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [EquipmentDTO] = []
    @State private var isLoading = true
    @State private var busyId: Int?
    @State private var errorText: String?

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
        } else if items.isEmpty {
            EmptyState(icon: "shippingbox",
                       title: "Оборудования нет",
                       message: "К мероприятию не привязано ни одной позиции — отмечать нечего.")
        } else {
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    header
                    ForEach(items) { item in row(item) }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: kind.icon).foregroundStyle(Theme.accent)
            Text(checked == items.count ? "Всё отмечено" : "Отмечено \(checked) из \(items.count)")
                .font(Typography.callout)
                .foregroundStyle(checked == items.count ? Theme.success : Theme.textPrimary)
            Spacer()
            if !canCheck {
                Text("только просмотр").font(.caption2).foregroundStyle(Theme.textSecondary)
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
