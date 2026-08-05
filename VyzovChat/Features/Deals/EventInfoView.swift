import SwiftUI
import UniformTypeIdentifiers

/// Обвязка мероприятия: оборудование, документы (акты), претензии и приглашение
/// по ссылке. Участник всё это видит, правит — админ чата; звать по ссылке может
/// ещё и куратор.
struct EventInfoView: View {
    let dealId: String
    let eventTitle: String
    let isChatAdmin: Bool
    let canInvite: Bool
    /// Документы (акты) правит ещё и старший.
    var canDocs: Bool = false
    /// Претензии — старший и кладовщик: он принимает оборудование обратно.
    var canClaims: Bool = false
    /// Подтема «Претензия» — туда уходит комментарий при урегулировании.
    var claimTopicId: Int?
    /// Фото с мероприятия запрещено использовать (галочка ниже).
    @State var photosRestricted: Bool = false

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var equipment: [EquipmentDTO] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // Добавление оборудования
    @State private var newItemName = ""
    @State private var newItemQty = ""

    // Приглашение
    @State private var invite: InviteDTO?
    @State private var invitingRole: String?

    @State private var showDocuments = false
    @State private var showClaims = false
    /// Метки и признаки мероприятия — их надо сохранить вместе с галочкой фото.
    @State private var currentTagIds: [Int] = []
    @State private var needsPhoto = false
    @State private var needsReport = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            if let errorText { ErrorBanner(text: errorText) }
                            restrictedCard
                            sectionsCard
                            if canInvite { inviteCard }
                            equipmentSection
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.vertical, Spacing.s)
                    }
                }
            }
            .navigationTitle("Мероприятие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showDocuments) {
                // Правит не только админ чата: акты ведёт и старший.
                EventDocumentsView(dealId: dealId, isChatAdmin: isChatAdmin || canDocs)
                    .environmentObject(session)
            }
            .sheet(isPresented: $showClaims) {
                ClaimsView(dealId: dealId, isChatAdmin: isChatAdmin || canClaims,
                           claimTopicId: claimTopicId)
                    .environmentObject(session)
            }
        }
    }

    /// Запрет на использование фото. Отдельной карточкой и с предупреждением:
    /// это не настройка «для порядка», а обязательство перед клиентом.
    private var restrictedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Toggle(isOn: Binding(
                    get: { photosRestricted },
                    set: { value in
                        photosRestricted = value
                        Task { await saveRestricted(value) }
                    }
                )) {
                    Label("Нельзя использовать фото", systemImage: "lock.fill")
                        .font(Typography.callout.weight(.medium))
                        .foregroundStyle(photosRestricted ? Theme.danger : Theme.textPrimary)
                }
                .tint(Theme.danger)
                .disabled(!isChatAdmin)

                Text("Клиент запретил публикацию съёмки. В фотобанке и в отчёте все кадры этого мероприятия получат красную пометку, чтобы их не взяли в рекламу или соцсети.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .stroke(photosRestricted ? Theme.danger.opacity(0.6) : .clear, lineWidth: 1)
        )
    }

    /// Разделы мероприятия отдельными экранами — как в вебе.
    private var sectionsCard: some View {
        VStack(spacing: Spacing.xs) {
            Button { showDocuments = true } label: {
                sectionRow("Документы", icon: "doc.text.fill",
                           hint: "Акты приёма и возврата, прочие файлы")
            }
            .buttonStyle(PressableStyle())

            Button { showClaims = true } label: {
                sectionRow("Претензии", icon: "exclamationmark.triangle.fill",
                           hint: "Ущерб и утеря по позициям оборудования")
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func sectionRow(_ title: String, icon: String, hint: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typography.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(hint).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
    }

    private func saveRestricted(_ value: Bool) async {
        errorText = nil
        do {
            // Метки и признаки уходят одним запросом — сохраняем уже выбранные,
            // иначе включение галочки сбросило бы метки мероприятия.
            try await session.directory.setEventTags(
                dealId: dealId, tagIds: currentTagIds,
                needsPhoto: needsPhoto, needsReport: needsReport, photosRestricted: value)
            Haptics.success()
        } catch {
            photosRestricted = !value
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    // MARK: - Приглашение по ссылке

    private var inviteCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Позвать по ссылке").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                // У ссылок разный срок жизни, и это важно: складскую кладут в
                // карточку сделки в CRM, к архивному мероприятию по ней заходят
                // и через год.
                Text("Ссылка подрядчика одноразовая и живёт неделю. Ссылка кладовщика бессрочная и без ограничения переходов — он только называет себя, пароль не нужен.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)

                if let invite, let url = invite.url {
                    ShareLink(item: url) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                            .font(Typography.button).foregroundStyle(Theme.textOnAccent)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Theme.accent, in: Capsule())
                    }
                    Text(url.absoluteString)
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).textSelection(.enabled)
                }

                HStack(spacing: Spacing.xs) {
                    inviteButton(title: "Подрядчик", role: "member")
                    // Ссылок ровно две: подрядчик и склад. Кладовщика зовёт
                    // только админ чата — куратору сервер понизил бы роль до
                    // подрядчика, и кнопка врала бы.
                    if isChatAdmin {
                        inviteButton(title: "Кладовщик", role: "storekeeper")
                    }
                }
            }
        }
    }

    private func inviteButton(title: String, role: String) -> some View {
        Button {
            Task { await makeInvite(role: role) }
        } label: {
            Group {
                if invitingRole == role { ProgressView().tint(Theme.accent) }
                else { Text(title).font(.caption.weight(.semibold)) }
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity).frame(height: 36)
            .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        }
        .buttonStyle(.plain)
        .disabled(invitingRole != nil)
    }

    private func makeInvite(role: String) async {
        invitingRole = role
        errorText = nil
        defer { invitingRole = nil }
        do {
            invite = try await session.eventInfo.createInvite(dealId: dealId, role: role)
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    // MARK: - Оборудование

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Оборудование").font(Typography.headline).foregroundStyle(Theme.textPrimary)
            if equipment.isEmpty {
                Text("Список пуст.").font(Typography.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(equipment) { item in
                HStack(spacing: Spacing.s) {
                    Image(systemName: "shippingbox.fill").foregroundStyle(Theme.groupTitle)
                    Text(item.name).font(Typography.callout)
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    if let qty = item.qty {
                        Text("\(qty) шт.").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    if isChatAdmin {
                        Button { Task { await deleteEquipment(item) } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(Spacing.s)
                .glass(cornerRadius: Theme.cornerSmall, elevated: false)
            }

            if isChatAdmin {
                HStack(spacing: Spacing.xs) {
                    TextField("Позиция", text: $newItemName)
                        .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                    TextField("Кол-во", text: $newItemQty)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .padding(.horizontal, Spacing.s).padding(.vertical, 8)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                    Button { Task { await addEquipment() } } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addEquipment() async {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let item = try await session.eventInfo.addEquipment(dealId: dealId, name: name, qty: Int(newItemQty))
            equipment.append(item)
            newItemName = ""
            newItemQty = ""
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.warning()
        }
    }

    private func deleteEquipment(_ item: EquipmentDTO) async {
        do {
            try await session.eventInfo.deleteEquipment(dealId: dealId, itemId: item.id)
            equipment.removeAll { $0.id == item.id }
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Загрузка

    private func load() async {
        async let eq = session.eventInfo.equipment(dealId: dealId)
        async let ev = session.directory.event(id: dealId)
        equipment = await eq
        // Метки и признаки читаем из карточки: галочка «нельзя использовать фото»
        // сохраняется вместе с ними одним запросом.
        if let dto = await ev {
            photosRestricted = dto.photos_restricted ?? false
            needsPhoto = dto.needs_photo ?? false
            needsReport = dto.needs_report ?? false
            currentTagIds = (dto.tags ?? []).map(\.id)
        }
        isLoading = false
    }
}

